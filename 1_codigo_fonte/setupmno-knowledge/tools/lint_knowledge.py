#!/usr/bin/python3
"""Valida e resolve a base canônica do Assistente MNO sem dependências externas."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import ipaddress
import json
import re
import sys
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import Any


KNOWLEDGE_DIRECTORIES = (
    "infra",
    "setups",
    "troubleshooting",
    "blueprints",
    "policies",
    "glossary",
    "evals",
)

REQUIRED_FIELDS = {
    "schemaVersion",
    "documentId",
    "documentVersion",
    "contentSHA256",
    "documentType",
    "title",
    "setupVersion",
    "architectures",
    "category",
    "status",
    "updatedAt",
    "sourceType",
    "risk",
    "language",
    "tags",
    "sources",
    "homologation",
}

OPTIONAL_FIELDS = {
    "setupId",
    "topicId",
    "blueprintId",
    "fictitious",
    "deployable",
}
SEMVER_RE = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
SHA256_RE = re.compile(r"^[a-f0-9]{64}$")
ID_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
PORT_RE = re.compile(r"(?i)\b(?:porta|port)\s*[:=]?\s*(\d{1,5})\b|:(\d{2,5})\b")
IMAGE_RE = re.compile(
    r"(?i)\b(?:[a-z0-9.-]+/)+(?:[a-z0-9._-]+):(?:[a-z0-9._-]+)\b"
)
IPV4_RE = re.compile(r"(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])")
HOST_ASSIGNMENT_RE = re.compile(r"(?i)\bhostname\s*[:=]\s*[^\s`]+")

SECRET_PATTERNS = {
    "chave privada": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    "chave OpenAI": re.compile(r"\bsk-[A-Za-z0-9_-]{16,}\b"),
    "token GitHub": re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}\b"),
    "access key AWS": re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    "JWT": re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{8,}\b"),
    "Bearer token": re.compile(r"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{16,}\b"),
    "atribuição de segredo": re.compile(
        r"(?i)\b(?:password|passwd|senha|secret|token|api[_-]?key)\s*[:=]\s*"
        r"[\"']?[A-Za-z0-9+/=_-]{12,}[\"']?"
    ),
}

REQUIRED_SECTIONS = {
    "setup": (
        "## Quando usar",
        "## Arquitetura no Setup MNO",
        "## Pré-requisitos",
        "## Fluxo seguro",
        "## Validação",
        "## Riscos e limites",
        "## Diagnóstico",
    ),
    "infrastructure": (
        "## Papel no Setup MNO",
        "## Princípios",
        "## Validação",
        "## Riscos e limites",
    ),
    "blueprint": (
        "## Estado de homologação",
        "## Objetivo",
        "## Topologia",
        "## Componentes",
        "## Pré-requisitos",
        "## Ordem segura",
        "## Validação",
        "## Riscos e limites",
        "## Rollback",
    ),
}


@dataclass(frozen=True)
class KnowledgeDocument:
    path: Path
    metadata: dict[str, Any]
    body: str


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def parse_document(path: Path) -> KnowledgeDocument:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    if not lines or lines[0] != "---":
        raise ValueError("o documento deve começar com o delimitador ---")
    try:
        closing = lines.index("---", 1)
    except ValueError as exc:
        raise ValueError("o bloco de metadados não possui delimitador final ---") from exc
    raw_metadata = "\n".join(lines[1:closing])
    try:
        metadata = json.loads(raw_metadata)
    except json.JSONDecodeError as exc:
        raise ValueError(f"metadados JSON inválidos: {exc}") from exc
    if not isinstance(metadata, dict):
        raise ValueError("metadados devem ser um objeto JSON")
    body = "\n".join(lines[closing + 1 :]).strip()
    if not body:
        raise ValueError("o corpo Markdown está vazio")
    return KnowledgeDocument(path=path, metadata=metadata, body=body)


def is_iso_date(value: Any) -> bool:
    if not isinstance(value, str):
        return False
    try:
        dt.date.fromisoformat(value)
    except ValueError:
        return False
    return True


def find_private_ips(text: str) -> list[str]:
    private_ips: list[str] = []
    for candidate in IPV4_RE.findall(text):
        try:
            address = ipaddress.ip_address(candidate)
        except ValueError:
            continue
        if address.is_private or address.is_loopback or address.is_link_local:
            private_ips.append(candidate)
    return sorted(set(private_ips))


def normalize_alias(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value.casefold())
    ascii_text = "".join(
        character for character in normalized if not unicodedata.combining(character)
    )
    return " ".join(re.sub(r"[^a-z0-9]+", " ", ascii_text).split())


def validate_retrieval_taxonomy(taxonomy: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if taxonomy.get("schemaVersion") != 2:
        errors.append("schema/taxonomy.json: schemaVersion deve ser 2")
    synonyms = taxonomy.get("synonyms")
    if not isinstance(synonyms, dict):
        return errors + ["schema/taxonomy.json: synonyms deve ser um objeto"]
    expected_targets = set(taxonomy.get("infrastructureTopics", [])) | set(
        taxonomy.get("architectures", [])
    )
    if set(synonyms) != expected_targets:
        missing = expected_targets - set(synonyms)
        unknown = set(synonyms) - expected_targets
        if missing:
            errors.append(
                "schema/taxonomy.json: synonyms sem alvos: "
                + ", ".join(sorted(missing))
            )
        if unknown:
            errors.append(
                "schema/taxonomy.json: synonyms com alvos desconhecidos: "
                + ", ".join(sorted(unknown))
            )
    owners: dict[str, str] = {}
    for target, aliases in synonyms.items():
        prefix = f"schema/taxonomy.json: synonyms.{target}"
        if not isinstance(aliases, list) or not aliases:
            errors.append(f"{prefix} deve ser uma lista não vazia")
            continue
        local: set[str] = set()
        for alias in aliases:
            if not isinstance(alias, str) or not alias.strip():
                errors.append(f"{prefix} contém alias vazio ou inválido")
                continue
            normalized = normalize_alias(alias)
            if not normalized:
                errors.append(f"{prefix} contém alias sem termos recuperáveis")
                continue
            if normalized in local:
                errors.append(f"{prefix} contém alias normalizado duplicado: {alias}")
            local.add(normalized)
            owner = owners.get(normalized)
            if owner is not None and owner != target:
                errors.append(
                    f"{prefix} contém alias ambíguo com {owner}: {alias}"
                )
            owners[normalized] = target
    return errors


def validate_source(
    source: Any,
    source_index: int,
    taxonomy: dict[str, Any],
    source_root: Path,
) -> list[str]:
    prefix = f"sources[{source_index}]"
    errors: list[str] = []
    required = {
        "sourceId",
        "title",
        "sourceType",
        "location",
        "license",
        "verifiedAt",
    }
    if not isinstance(source, dict):
        return [f"{prefix} deve ser um objeto"]
    missing = required - set(source)
    unknown = set(source) - required
    if missing:
        errors.append(f"{prefix} sem campos: {', '.join(sorted(missing))}")
    if unknown:
        errors.append(f"{prefix} contém campos desconhecidos: {', '.join(sorted(unknown))}")
    if not ID_RE.fullmatch(str(source.get("sourceId", ""))):
        errors.append(f"{prefix}.sourceId inválido")
    if source.get("sourceType") not in taxonomy["sourceTypes"]:
        errors.append(f"{prefix}.sourceType fora da taxonomia")
    if source.get("license") not in taxonomy["licenses"]:
        errors.append(f"{prefix}.license fora da taxonomia")
    if not is_iso_date(source.get("verifiedAt")):
        errors.append(f"{prefix}.verifiedAt deve usar YYYY-MM-DD")

    location = source.get("location")
    if source.get("sourceType") == "setup-mno" and isinstance(location, str):
        candidate = source_root / location
        if not candidate.is_file():
            errors.append(f"{prefix}.location não existe: {location}")
    return errors


def validate_document(
    document: KnowledgeDocument,
    taxonomy: dict[str, Any],
    registry_by_id: dict[str, dict[str, Any]],
    catalog_names: set[str],
    source_root: Path,
) -> list[str]:
    metadata = document.metadata
    errors: list[str] = []
    missing = REQUIRED_FIELDS - set(metadata)
    unknown = set(metadata) - REQUIRED_FIELDS - OPTIONAL_FIELDS
    if missing:
        errors.append(f"campos obrigatórios ausentes: {', '.join(sorted(missing))}")
    if unknown:
        errors.append(f"campos desconhecidos: {', '.join(sorted(unknown))}")

    if metadata.get("schemaVersion") != 1:
        errors.append("schemaVersion deve ser 1")
    if not ID_RE.fullmatch(str(metadata.get("documentId", ""))):
        errors.append("documentId inválido")
    if not SEMVER_RE.fullmatch(str(metadata.get("documentVersion", ""))):
        errors.append("documentVersion deve seguir SemVer")
    content_hash = str(metadata.get("contentSHA256", ""))
    expected_hash = hashlib.sha256(document.body.encode("utf-8")).hexdigest()
    if not SHA256_RE.fullmatch(content_hash):
        errors.append("contentSHA256 deve conter 64 caracteres hexadecimais minúsculos")
    elif content_hash != expected_hash:
        errors.append(f"contentSHA256 divergente; esperado {expected_hash}")
    if not SEMVER_RE.fullmatch(str(metadata.get("setupVersion", ""))):
        errors.append("setupVersion deve seguir SemVer")
    if metadata.get("documentType") not in taxonomy["documentTypes"]:
        errors.append("documentType fora da taxonomia")
    if metadata.get("category") not in taxonomy["categories"]:
        errors.append("category fora da taxonomia")
    if metadata.get("status") not in taxonomy["statuses"]:
        errors.append("status fora da taxonomia")
    if metadata.get("sourceType") not in taxonomy["sourceTypes"]:
        errors.append("sourceType fora da taxonomia")
    if metadata.get("risk") not in taxonomy["risks"]:
        errors.append("risk fora da taxonomia")
    if metadata.get("language") != "pt-BR":
        errors.append("language deve ser pt-BR")
    if not is_iso_date(metadata.get("updatedAt")):
        errors.append("updatedAt deve usar YYYY-MM-DD")

    title = metadata.get("title")
    if not isinstance(title, str) or not 5 <= len(title) <= 120:
        errors.append("title deve conter entre 5 e 120 caracteres")

    architectures = metadata.get("architectures")
    if not isinstance(architectures, list) or not architectures:
        errors.append("architectures deve ser uma lista não vazia")
    elif len(architectures) != len(set(architectures)):
        errors.append("architectures contém duplicatas")
    elif any(item not in taxonomy["architectures"] for item in architectures):
        errors.append("architectures contém valor fora da taxonomia")

    tags = metadata.get("tags")
    if not isinstance(tags, list) or len(tags) < 2:
        errors.append("tags deve conter ao menos dois IDs")
    elif len(tags) != len(set(tags)):
        errors.append("tags contém duplicatas")
    elif any(not isinstance(tag, str) or not ID_RE.fullmatch(tag) for tag in tags):
        errors.append("tags contém ID inválido")

    sources = metadata.get("sources")
    if not isinstance(sources, list) or not sources:
        errors.append("sources deve conter ao menos uma fonte")
    else:
        for index, source in enumerate(sources):
            errors.extend(validate_source(source, index, taxonomy, source_root))

    document_type = metadata.get("documentType")
    if document_type == "setup":
        setup_id = metadata.get("setupId")
        registry_entry = registry_by_id.get(setup_id)
        if not registry_entry:
            errors.append("setupId não existe no registro do lote piloto")
        else:
            if registry_entry["catalogName"] not in catalog_names:
                errors.append("setupId aponta para nome ausente no catálogo canônico")
            if isinstance(architectures, list) and not set(architectures).issubset(
                registry_entry["architectures"]
            ):
                errors.append("arquitetura incompatível com o registro do setup")
    elif "setupId" in metadata:
        errors.append("setupId só é permitido em documentos do tipo setup")

    if document_type == "infrastructure":
        if metadata.get("topicId") not in taxonomy["infrastructureTopics"]:
            errors.append("topicId fora da taxonomia de infraestrutura")
    elif "topicId" in metadata:
        errors.append("topicId só é permitido em documentos de infraestrutura")

    blueprint_fields = {"blueprintId", "fictitious", "deployable"}
    if document_type == "blueprint":
        blueprint_id = metadata.get("blueprintId")
        fictitious = metadata.get("fictitious")
        deployable = metadata.get("deployable")
        if not isinstance(blueprint_id, str) or not ID_RE.fullmatch(blueprint_id):
            errors.append("blueprintId inválido")
        if not isinstance(fictitious, bool) or not isinstance(deployable, bool):
            errors.append("fictitious e deployable devem ser booleanos")
        if isinstance(blueprint_id, str) and document.path.parent.name != blueprint_id:
            errors.append("blueprintId diverge da pasta canônica")
        manifest_path = document.path.parent / "blueprint.json"
        try:
            blueprint_manifest = load_json(manifest_path)
        except (OSError, json.JSONDecodeError):
            blueprint_manifest = None
            errors.append("blueprint.json correspondente está ausente ou inválido")
        if isinstance(blueprint_manifest, dict):
            for field in blueprint_fields:
                if metadata.get(field) != blueprint_manifest.get(field):
                    errors.append(f"{field} diverge do manifesto canônico do Blueprint")
            if metadata.get("architectures") != blueprint_manifest.get("architectures"):
                errors.append("architectures diverge do manifesto canônico do Blueprint")
            if metadata.get("risk") != blueprint_manifest.get("risk"):
                errors.append("risk diverge do manifesto canônico do Blueprint")
        if fictitious is True:
            if deployable is not False or metadata.get("status") != "reviewed":
                errors.append(
                    "fixture fictícia exige deployable=false e status=reviewed"
                )
            if metadata.get("sourceType") != "homologation-test":
                errors.append("fixture fictícia exige sourceType=homologation-test")
        elif deployable is True and metadata.get("status") != "homologated":
            errors.append("Blueprint implantável exige status=homologated")
        elif fictitious is False and deployable is False:
            if metadata.get("status") != "reviewed":
                errors.append("Blueprint Beta não implantável exige status=reviewed")
            if metadata.get("sourceType") != "maintainer-authored":
                errors.append("Blueprint Beta exige sourceType=maintainer-authored")
    elif any(field in metadata for field in blueprint_fields):
        errors.append(
            "blueprintId, fictitious e deployable só são permitidos em documentos blueprint"
        )

    homologation = metadata.get("homologation")
    verified_ports: set[int] = set()
    verified_images: set[str] = set()
    if not isinstance(homologation, dict):
        errors.append("homologation deve ser um objeto")
    else:
        expected = {"verifiedAt", "verifiedPorts", "verifiedImages"}
        if set(homologation) != expected:
            errors.append("homologation deve conter apenas verifiedAt, verifiedPorts e verifiedImages")
        if homologation.get("verifiedAt") is not None and not is_iso_date(
            homologation.get("verifiedAt")
        ):
            errors.append("homologation.verifiedAt deve ser nulo ou usar YYYY-MM-DD")
        ports = homologation.get("verifiedPorts")
        images = homologation.get("verifiedImages")
        if not isinstance(ports, list) or any(
            not isinstance(port, int) or not 1 <= port <= 65535 for port in ports
        ):
            errors.append("homologation.verifiedPorts inválido")
        else:
            verified_ports = set(ports)
            if len(verified_ports) != len(ports):
                errors.append("homologation.verifiedPorts contém duplicatas")
        if not isinstance(images, list) or any(
            not isinstance(image, str) or not image for image in images
        ):
            errors.append("homologation.verifiedImages inválido")
        else:
            verified_images = set(images)
            if len(verified_images) != len(images):
                errors.append("homologation.verifiedImages contém duplicatas")
        if metadata.get("status") == "homologated" and homologation.get("verifiedAt") is None:
            errors.append("documento homologated exige homologation.verifiedAt")

    for section in REQUIRED_SECTIONS.get(str(document_type), ()):
        if section not in document.body:
            errors.append(f"seção editorial obrigatória ausente: {section}")

    for secret_name, pattern in SECRET_PATTERNS.items():
        if pattern.search(document.body):
            errors.append(f"padrão proibido detectado no corpo: {secret_name}")

    private_ips = find_private_ips(document.body)
    if private_ips:
        errors.append(f"IP privado/local detectado: {', '.join(private_ips)}")
    if HOST_ASSIGNMENT_RE.search(document.body):
        errors.append("atribuição de hostname detectada no corpo")

    declared_ports = {
        int(port)
        for match in PORT_RE.findall(document.body)
        for port in match
        if port
    }
    unverified_ports = declared_ports - verified_ports
    if unverified_ports:
        errors.append(
            "portas citadas sem homologação: "
            + ", ".join(str(port) for port in sorted(unverified_ports))
        )

    declared_images = set(IMAGE_RE.findall(document.body))
    unverified_images = declared_images - verified_images
    if unverified_images:
        errors.append(
            "imagens citadas sem homologação: " + ", ".join(sorted(unverified_images))
        )
    return errors


def load_documents(root: Path) -> tuple[list[KnowledgeDocument], list[str]]:
    documents: list[KnowledgeDocument] = []
    errors: list[str] = []
    for directory in KNOWLEDGE_DIRECTORIES:
        base = root / directory
        if not base.is_dir():
            errors.append(f"{directory}: diretório obrigatório ausente")
            continue
        for path in sorted(base.rglob("*.md")):
            # README.md pertence ao bundle humano do Blueprint. Somente o
            # arquivo knowledge.md, criado após revisão/homologação, pode
            # participar da base recuperável pelo Assistente.
            if directory == "blueprints" and path.name != "knowledge.md":
                continue
            try:
                documents.append(parse_document(path))
            except (OSError, ValueError) as exc:
                errors.append(f"{path.relative_to(root)}: {exc}")
    return documents, errors


def validate_registry(
    registry: dict[str, Any],
    catalog_names: set[str],
    source_root: Path,
) -> list[str]:
    errors: list[str] = []
    if registry.get("schemaVersion") != 2:
        errors.append("registry/setups.json: schemaVersion deve ser 2")
    entries = registry.get("setups")
    if not isinstance(entries, list) or not entries or len(entries) > len(catalog_names):
        errors.append(
            "registry/setups.json deve conter de 1 até a quantidade de setups do catálogo"
        )
        return errors
    seen_ids: set[str] = set()
    seen_names: set[str] = set()
    alias_owners: dict[str, str] = {}
    for index, entry in enumerate(entries):
        prefix = f"registry.setups[{index}]"
        if not isinstance(entry, dict):
            errors.append(f"{prefix} deve ser um objeto")
            continue
        expected = {
            "setupId",
            "catalogName",
            "script",
            "architectures",
            "aliases",
        }
        if set(entry) != expected:
            errors.append(f"{prefix} deve conter exatamente {', '.join(sorted(expected))}")
            continue
        setup_id = entry["setupId"]
        catalog_name = entry["catalogName"]
        if not ID_RE.fullmatch(str(setup_id)):
            errors.append(f"{prefix}.setupId inválido")
        if setup_id in seen_ids:
            errors.append(f"{prefix}.setupId duplicado")
        if catalog_name in seen_names:
            errors.append(f"{prefix}.catalogName duplicado")
        seen_ids.add(setup_id)
        seen_names.add(catalog_name)
        aliases = entry["aliases"]
        if not isinstance(aliases, list) or not aliases:
            errors.append(f"{prefix}.aliases deve ser uma lista não vazia")
        else:
            local_aliases: set[str] = set()
            owned_values = [str(setup_id), str(catalog_name), *aliases]
            for alias in owned_values:
                if not isinstance(alias, str) or not alias.strip():
                    errors.append(f"{prefix}.aliases contém valor vazio ou inválido")
                    continue
                normalized = normalize_alias(alias)
                if not normalized:
                    errors.append(f"{prefix}.aliases contém valor sem termos recuperáveis")
                    continue
                if alias in aliases and normalized in local_aliases:
                    errors.append(
                        f"{prefix}.aliases contém alias normalizado duplicado: {alias}"
                    )
                if alias in aliases:
                    local_aliases.add(normalized)
                owner = alias_owners.get(normalized)
                if owner is not None and owner != setup_id:
                    errors.append(
                        f"{prefix}.aliases contém alias ambíguo com {owner}: {alias}"
                    )
                alias_owners[normalized] = setup_id
        if catalog_name not in catalog_names:
            errors.append(f"{prefix}.catalogName ausente no catálogo canônico")
        for architecture, directory in (("amd64", "x86"), ("arm64", "arm")):
            if architecture in entry["architectures"]:
                script = source_root / directory / "SetupLowCodeMno" / entry["script"]
                if not script.is_file():
                    errors.append(f"{prefix}: script {architecture} ausente: {script}")
    return errors


def build_context(args: argparse.Namespace) -> tuple[
    Path,
    dict[str, Any],
    dict[str, Any],
    set[str],
    dict[str, dict[str, Any]],
    list[KnowledgeDocument],
    list[str],
]:
    root = args.root.resolve()
    source_root = root.parent
    taxonomy = load_json(root / "schema" / "taxonomy.json")
    registry = load_json(root / "registry" / "setups.json")
    catalog = load_json(args.catalog.resolve())
    if not isinstance(catalog, list):
        raise ValueError("o catálogo canônico deve ser uma lista")
    catalog_names = {
        entry.get("name")
        for entry in catalog
        if isinstance(entry, dict) and isinstance(entry.get("name"), str)
    }
    registry_entries = registry.get("setups", [])
    registry_by_id = {
        entry["setupId"]: entry
        for entry in registry_entries
        if isinstance(entry, dict) and isinstance(entry.get("setupId"), str)
    }
    documents, errors = load_documents(root)
    errors.extend(validate_retrieval_taxonomy(taxonomy))
    errors.extend(validate_registry(registry, catalog_names, source_root))
    return (
        root,
        taxonomy,
        registry,
        catalog_names,
        registry_by_id,
        documents,
        errors,
    )


def lint(args: argparse.Namespace) -> int:
    (
        root,
        taxonomy,
        _registry,
        catalog_names,
        registry_by_id,
        documents,
        errors,
    ) = build_context(args)
    source_root = root.parent
    document_ids: dict[str, Path] = {}
    setup_documents: dict[str, int] = {}
    knowledge_version = (root / "VERSION").read_text(encoding="utf-8").strip()
    if not SEMVER_RE.fullmatch(knowledge_version):
        errors.append("VERSION da base de conhecimento não segue SemVer")
    if taxonomy.get("knowledgeVersion") != knowledge_version:
        errors.append("VERSION diverge de schema/taxonomy.json")

    for document in documents:
        relative = document.path.relative_to(root)
        for error in validate_document(
            document,
            taxonomy,
            registry_by_id,
            catalog_names,
            source_root,
        ):
            errors.append(f"{relative}: {error}")
        document_id = document.metadata.get("documentId")
        if isinstance(document_id, str):
            if document_id in document_ids:
                errors.append(
                    f"{relative}: documentId duplicado com "
                    f"{document_ids[document_id].relative_to(root)}"
                )
            document_ids[document_id] = document.path
        setup_id = document.metadata.get("setupId")
        if document.metadata.get("documentType") == "setup" and isinstance(setup_id, str):
            setup_documents[setup_id] = setup_documents.get(setup_id, 0) + 1

    for setup_id in registry_by_id:
        if setup_documents.get(setup_id, 0) == 0:
            errors.append(f"setups/{setup_id}: nenhum documento encontrado")

    if errors:
        for error in sorted(errors):
            print(f"ERRO: {error}", file=sys.stderr)
        print(
            f"FALHA: {len(errors)} erro(s), {len(documents)} documento(s) analisado(s).",
            file=sys.stderr,
        )
        return 1

    statuses: dict[str, int] = {}
    types: dict[str, int] = {}
    for document in documents:
        status = str(document.metadata["status"])
        document_type = str(document.metadata["documentType"])
        statuses[status] = statuses.get(status, 0) + 1
        types[document_type] = types.get(document_type, 0) + 1
    print(
        json.dumps(
            {
                "result": "ok",
                "knowledgeVersion": knowledge_version,
                "documents": len(documents),
                "setups": len(setup_documents),
                "statuses": statuses,
                "types": types,
            },
            ensure_ascii=False,
            sort_keys=True,
        )
    )
    return 0


def resolve(args: argparse.Namespace) -> int:
    (
        root,
        taxonomy,
        _registry,
        catalog_names,
        registry_by_id,
        documents,
        errors,
    ) = build_context(args)
    if errors:
        for error in sorted(errors):
            print(f"ERRO: {error}", file=sys.stderr)
        return 1
    if args.setup_id not in registry_by_id:
        print(f"ERRO: setupId desconhecido: {args.setup_id}", file=sys.stderr)
        return 2
    if args.architecture not in taxonomy["architectures"]:
        print(f"ERRO: arquitetura desconhecida: {args.architecture}", file=sys.stderr)
        return 2
    if not SEMVER_RE.fullmatch(args.setup_version):
        print("ERRO: setup-version deve seguir SemVer", file=sys.stderr)
        return 2

    allowed_statuses = set(taxonomy["normalRetrievalStatuses"])
    if args.include_drafts:
        allowed_statuses.add("draft")
    resolved: list[dict[str, Any]] = []
    for document in documents:
        metadata = document.metadata
        if metadata.get("documentType") != "setup":
            continue
        if metadata.get("setupId") != args.setup_id:
            continue
        if metadata.get("setupVersion") != args.setup_version:
            continue
        if args.architecture not in metadata.get("architectures", []):
            continue
        if metadata.get("status") not in allowed_statuses:
            continue
        validation_errors = validate_document(
            document,
            taxonomy,
            registry_by_id,
            catalog_names,
            root.parent,
        )
        if validation_errors:
            continue
        resolved.append(
            {
                "documentId": metadata["documentId"],
                "documentVersion": metadata["documentVersion"],
                "status": metadata["status"],
                "path": str(document.path.relative_to(root)),
                "title": metadata["title"],
            }
        )
    print(
        json.dumps(
            {
                "setupId": args.setup_id,
                "setupVersion": args.setup_version,
                "architecture": args.architecture,
                "documents": sorted(resolved, key=lambda item: item["documentId"]),
            },
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        )
    )
    return 0 if resolved else 3


def hashes(args: argparse.Namespace) -> int:
    root = args.root.resolve()
    documents, errors = load_documents(root)
    if errors:
        for error in sorted(errors):
            print(f"ERRO: {error}", file=sys.stderr)
        return 1
    result = {
        str(document.path.relative_to(root)): hashlib.sha256(
            document.body.encode("utf-8")
        ).hexdigest()
        for document in documents
    }
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
        help="raiz de setupmno-knowledge",
    )
    parser.add_argument(
        "--catalog",
        type=Path,
        default=Path(__file__).resolve().parent.parent.parent
        / "setupmno-control"
        / "catalog.json",
        help="catalog.json canônico do Control Center",
    )
    parser.add_argument(
        "command",
        nargs="?",
        choices=("lint", "resolve", "hashes"),
        default="lint",
    )
    parser.add_argument("--setup-id")
    parser.add_argument("--setup-version")
    parser.add_argument("--architecture")
    parser.add_argument("--include-drafts", action="store_true")
    args = parser.parse_args()
    if args.command == "resolve":
        missing = [
            option
            for option, value in (
                ("--setup-id", args.setup_id),
                ("--setup-version", args.setup_version),
                ("--architecture", args.architecture),
            )
            if not value
        ]
        if missing:
            parser.error("resolve exige " + ", ".join(missing))
    return args


def main() -> int:
    try:
        args = parse_args()
        if args.command == "resolve":
            return resolve(args)
        if args.command == "hashes":
            return hashes(args)
        return lint(args)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"ERRO: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
