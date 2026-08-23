#!/usr/bin/python3
"""Importa release-pack PRO MASTER na base canônica com dry-run e rollback."""

from __future__ import annotations

import argparse
import copy
import datetime as dt
import hashlib
import io
import json
import os
import re
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path
from typing import Any

import homologation_runner as runner
from certify_homologation import ALL_CHECKS, canonical_json, parse_utc, validate_ledger
from lint_knowledge import parse_document


MAX_PACK_BYTES = 16 << 20
MAX_MEMBER_BYTES = 8 << 20
MAX_TOTAL_BYTES = 32 << 20
MAX_MEMBERS = 64
SUPPORTED_LEGACY_SOURCE_VERSIONS = {"7.27.0"}
SHA256_RE = re.compile(r"^[a-f0-9]{64}$")
SEMVER_RE = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
ID_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
IMAGE_RE = re.compile(r"^[a-z0-9][a-z0-9._/-]*(?::[A-Za-z0-9._-]+)?@sha256:[a-f0-9]{64}$")
IMPORT_LEDGER_KIND = "setupmno-canonical-import-ledger"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_regular(path: Path, limit: int) -> bytes:
    if path.is_symlink() or not path.is_file() or not 0 < path.stat().st_size <= limit:
        raise ValueError(f"arquivo ausente, inseguro ou fora do limite: {path}")
    return path.read_bytes()


def load_json(data: bytes, label: str) -> Any:
    try:
        return json.loads(data)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"JSON inválido em {label}") from exc


def safe_relative(value: str) -> str:
    path = Path(str(value))
    if not value or path.is_absolute() or ".." in path.parts or path.as_posix() != value:
        raise ValueError(f"caminho inseguro no pacote: {value}")
    return value


def load_pack(path: Path) -> tuple[dict[str, Any], dict[str, bytes], str]:
    data = read_regular(path, MAX_PACK_BYTES)
    try:
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
            members = archive.getmembers()
            if not 2 <= len(members) <= MAX_MEMBERS:
                raise ValueError("quantidade de entradas do pacote é inválida")
            names: list[str] = []
            payloads: dict[str, bytes] = {}
            total = 0
            for member in members:
                name = safe_relative(member.name)
                if name in names or not member.isfile() or member.issym() or member.islnk():
                    raise ValueError("pacote contém entrada duplicada ou não regular")
                pax = member.pax_headers
                if (
                    set(pax) - {"path"}
                    or ("path" in pax and pax["path"] != name)
                    or member.size <= 0
                    or member.size > MAX_MEMBER_BYTES
                ):
                    raise ValueError(f"entrada insegura ou fora do limite: {name}")
                total += member.size
                if total > MAX_TOTAL_BYTES:
                    raise ValueError("conteúdo descompactado excede o limite")
                stream = archive.extractfile(member)
                if stream is None:
                    raise ValueError(f"entrada ilegível: {name}")
                payloads[name] = stream.read(MAX_MEMBER_BYTES + 1)
                names.append(name)
    except (tarfile.TarError, EOFError) as exc:
        raise ValueError("release-pack inválido") from exc
    if "manifest.json" not in payloads:
        raise ValueError("manifest.json ausente")
    manifest = load_json(payloads["manifest.json"], "manifest.json")
    common = {
        "schemaVersion", "kind", "setupId", "setupVersion", "sealId",
        "sealSHA256", "officialSeal", "automaticPublication",
        "requiresCanonicalImport", "files",
    }
    version = manifest.get("schemaVersion") if isinstance(manifest, dict) else None
    expected = common if version == 1 else common | {"sourceAttestation"}
    if not isinstance(manifest, dict) or version not in {1, 2} or set(manifest) != expected:
        raise ValueError("manifesto do release-pack possui campos inesperados")
    if (
        manifest["kind"] != "setupmno-official-seal-release-pack"
        or manifest["officialSeal"] is not True
        or manifest["automaticPublication"] is not False
        or manifest["requiresCanonicalImport"] is not True
    ):
        raise ValueError("release-pack tentou ultrapassar a fronteira de confiança")
    inventory = manifest.get("files")
    if not isinstance(inventory, list) or not inventory:
        raise ValueError("inventário autenticado está vazio")
    inventory_names: list[str] = []
    for item in inventory:
        if not isinstance(item, dict) or set(item) != {"path", "sha256", "size"}:
            raise ValueError("entrada inválida no inventário autenticado")
        name = safe_relative(item["path"])
        if name in inventory_names or name == "manifest.json" or name not in payloads:
            raise ValueError("inventário autenticado contém caminho inválido")
        payload = payloads[name]
        if item["size"] != len(payload) or item["sha256"] != sha256(payload):
            raise ValueError(f"integridade divergente: {name}")
        inventory_names.append(name)
    if set(payloads) != set(inventory_names) | {"manifest.json"}:
        raise ValueError("inventário do tar diverge do manifesto")
    return manifest, payloads, sha256(data)


def payload_json(payloads: dict[str, bytes], relative: str) -> dict[str, Any]:
    name = f"setupmno-knowledge/{safe_relative(relative)}"
    if name not in payloads:
        raise ValueError(f"arquivo autenticado ausente: {relative}")
    value = load_json(payloads[name], relative)
    if not isinstance(value, dict):
        raise ValueError(f"objeto JSON esperado em {relative}")
    return value


def validate_source_attestation(
    manifest: dict[str, Any], payloads: dict[str, bytes], root: Path,
    catalog: Path, package_dir: Path,
) -> str:
    source_version = manifest["setupVersion"]
    current_registry_data = read_regular(root / "registry" / "setups.json", 4 << 20)
    current_registry = load_json(current_registry_data, "registry/setups.json")
    current_version = current_registry.get("setupVersion")
    if not SEMVER_RE.fullmatch(str(source_version)) or not SEMVER_RE.fullmatch(str(current_version)):
        raise ValueError("versão de origem ou destino inválida")
    if manifest["schemaVersion"] == 1:
        if source_version not in SUPPORTED_LEGACY_SOURCE_VERSIONS:
            raise ValueError("pacote legado pertence a uma versão não permitida")
        return "legacy-artifact-bound"
    attestation = manifest["sourceAttestation"]
    expected = {
        "kind", "setupVersion", "catalogSHA256",
        "homologationPackageManifestSHA256", "runnerRegistrySHA256",
        "canonicalRegistrySHA256",
    }
    if not isinstance(attestation, dict) or set(attestation) != expected:
        raise ValueError("atestação de origem possui campos inesperados")
    if (
        attestation["kind"] not in {"runtime-attested", "canonical-source"}
        or attestation["setupVersion"] != source_version
        or any(not SHA256_RE.fullmatch(str(attestation[key])) for key in expected - {"kind", "setupVersion"})
    ):
        raise ValueError("atestação de origem inválida")
    if source_version != current_version:
        raise ValueError("pacote v2 pertence a outra versão; use a origem canônica correspondente")
    expected_hashes = {
        "catalogSHA256": runner.sha256_file(catalog),
        "homologationPackageManifestSHA256": sha256(read_regular(package_dir / "manifest.json", 256 << 10)),
        "runnerRegistrySHA256": sha256(read_regular(package_dir / "runner-registry.json", 4 << 20)),
        "canonicalRegistrySHA256": sha256(current_registry_data),
    }
    if any(attestation[key] != digest for key, digest in expected_hashes.items()):
        raise ValueError("atestação de origem não corresponde à base canônica atual")
    return attestation["kind"]


def validate_seal(manifest: dict[str, Any], payloads: dict[str, bytes]) -> tuple[dict[str, Any], str, bytes]:
    setup_id = manifest["setupId"]
    seal_id = manifest["sealId"]
    if not ID_RE.fullmatch(str(setup_id)) or not ID_RE.fullmatch(str(seal_id)) or not str(seal_id).endswith("-official"):
        raise ValueError("identidade do selo inválida")
    seal_path = f"certifications/{setup_id}/{seal_id}.json"
    seal_name = f"setupmno-knowledge/{seal_path}"
    if seal_name not in payloads:
        raise ValueError("selo declarado não existe no pacote")
    seal_data = payloads[seal_name]
    seal = load_json(seal_data, seal_path)
    expected = {
        "schemaVersion", "kind", "sealId", "setupId", "setupVersion",
        "issuedAt", "issuedBy", "reason", "architectures", "artifacts",
        "images", "evidenceRefs", "decisionRefs", "reviewPacks", "status",
        "immutable", "automaticPromotion", "officialSeal",
    }
    if not isinstance(seal, dict) or set(seal) != expected:
        raise ValueError("selo possui campos inesperados")
    if (
        seal["schemaVersion"] != 1
        or seal["kind"] != "setupmno-official-homologation-seal"
        or seal["sealId"] != seal_id
        or seal["setupId"] != setup_id
        or seal["setupVersion"] != manifest["setupVersion"]
        or seal["status"] != "issued"
        or seal["immutable"] is not True
        or seal["automaticPromotion"] is not False
        or seal["officialSeal"] is not True
        or manifest["sealSHA256"] != sha256(seal_data)
        or not isinstance(seal["issuedBy"], str)
        or not 2 <= len(seal["issuedBy"].strip()) <= 80
        or not isinstance(seal["reason"], str)
        or not 3 <= len(seal["reason"].strip()) <= 240
    ):
        raise ValueError("conteúdo do selo diverge do manifesto")
    parse_utc(seal["issuedAt"], "issuedAt do selo")
    runner.reject_sensitive(seal, "selo importado")
    if (
        not isinstance(seal["images"], list)
        or seal["images"] != sorted(set(seal["images"]))
        or any(not IMAGE_RE.fullmatch(str(image)) for image in seal["images"])
    ):
        raise ValueError("selo não fixa todas as imagens por digest")
    return seal, seal_path, seal_data


def validate_refs(seal: dict[str, Any], payloads: dict[str, bytes]) -> set[str]:
    expected_paths: set[str] = set()
    architectures = seal["architectures"]
    if architectures != sorted(set(architectures)) or not architectures:
        raise ValueError("arquiteturas do selo são inválidas")
    evidence_by_arch: dict[str, dict[str, Any]] = {}
    decision_by_arch: dict[str, dict[str, Any]] = {}
    artifact_by_arch = {item["architecture"]: item for item in seal["artifacts"]}
    for collection, kind in (("evidenceRefs", "evidence"), ("decisionRefs", "decision")):
        refs = seal[collection]
        if not isinstance(refs, list) or len(refs) != len(architectures):
            raise ValueError(f"{collection} não cobre todas as arquiteturas")
        seen: set[str] = set()
        for ref in refs:
            if not isinstance(ref, dict) or set(ref) != {"architecture", "path", "sha256"}:
                raise ValueError(f"referência inválida em {collection}")
            arch, path, digest = ref["architecture"], safe_relative(ref["path"]), ref["sha256"]
            if arch not in architectures or arch in seen or not SHA256_RE.fullmatch(str(digest)):
                raise ValueError(f"identidade inválida em {collection}")
            name = f"setupmno-knowledge/{path}"
            if name not in payloads or sha256(payloads[name]) != digest:
                raise ValueError(f"integridade divergente: {path}")
            value = load_json(payloads[name], path)
            runner.reject_sensitive(value, f"{kind} importada")
            if kind == "evidence":
                evidence_keys = {
                    "schemaVersion", "evidenceId", "setupId", "setupVersion",
                    "architecture", "verifiedAt", "environment", "artifact",
                    "images", "checks", "result", "sanitized", "review",
                }
                if (
                    not isinstance(value, dict)
                    or set(value) != evidence_keys
                    or value.get("schemaVersion") != 1
                    or value.get("setupId") != seal["setupId"]
                    or value.get("setupVersion") != seal["setupVersion"]
                    or value.get("architecture") != arch
                    or value.get("result") != "passed"
                    or value.get("sanitized") is not True
                    or value.get("artifact") != {
                        "path": artifact_by_arch.get(arch, {}).get("path"),
                        "sha256": artifact_by_arch.get(arch, {}).get("sha256"),
                    }
                    or not set(value.get("images", [])).issubset(set(seal["images"]))
                    or not path.startswith(f"evidence/{seal['setupId']}/{arch}/")
                    or set(value.get("environment", {})) != {"platform", "orchestrator", "isolation"}
                    or value.get("environment", {}).get("orchestrator") != "docker-swarm"
                    or value.get("environment", {}).get("isolation") != "setupmno-hml"
                    or set(value.get("review", {})) != {"decision", "reviewedBy", "reviewedAt"}
                    or value.get("review", {}).get("decision") != "approved"
                    or set(value.get("checks", {})) != set(ALL_CHECKS)
                    or any(
                        set(value.get("checks", {}).get(check, {})) != {"status", "evidence"}
                        for check in ALL_CHECKS
                    )
                    or any(value.get("checks", {}).get(check, {}).get("status") != "passed" for check in ALL_CHECKS)
                ):
                    raise ValueError(f"evidência operacional inválida: {path}")
                evidence_by_arch[arch] = value
            else:
                decision_keys = {
                    "schemaVersion", "kind", "decisionId", "candidateId",
                    "candidateBundleSHA256", "decision", "reasonCode", "reason",
                    "reviewedBy", "reviewedAt", "immutable", "governanceUpdated",
                    "officialSeal",
                }
                if (
                    not isinstance(value, dict)
                    or set(value) != decision_keys
                    or value.get("schemaVersion") != 1
                    or value.get("kind") != "setupmno-homologation-review-decision"
                    or value.get("decision") != "approved"
                    or value.get("reasonCode") != "operational-evidence-accepted"
                    or value.get("immutable") is not True
                    or value.get("governanceUpdated") is not False
                    or value.get("officialSeal") is not False
                    or not path.startswith(f"certifications/{seal['setupId']}/decisions/")
                ):
                    raise ValueError(f"decisão de revisão inválida: {path}")
                decision_by_arch[arch] = value
            expected_paths.add(name)
            seen.add(arch)
    for arch in architectures:
        evidence = evidence_by_arch[arch]
        decision = decision_by_arch[arch]
        if (
            decision.get("candidateId") != f"{evidence.get('evidenceId')}-candidate"
            or decision.get("reviewedBy") != evidence.get("review", {}).get("reviewedBy")
            or decision.get("reviewedAt", "")[:10] != evidence.get("review", {}).get("reviewedAt")
            or parse_utc(decision.get("reviewedAt"), "reviewedAt da decisão") > parse_utc(seal["issuedAt"], "issuedAt do selo")
        ):
            raise ValueError(f"decisão e evidência divergem na arquitetura {arch}")
    review_packs = seal["reviewPacks"]
    if (
        not isinstance(review_packs, list)
        or len(review_packs) != len(architectures)
        or {item.get("architecture") for item in review_packs if isinstance(item, dict)} != set(architectures)
        or any(
            not isinstance(item, dict)
            or set(item) != {"architecture", "sha256"}
            or not SHA256_RE.fullmatch(str(item.get("sha256")))
            for item in review_packs
        )
    ):
        raise ValueError("inventário dos review-packs é inválido")
    return expected_paths


def validate_artifacts(seal: dict[str, Any], root: Path, package_dir: Path) -> None:
    _, runner_registry = runner.validate_package(package_dir)
    package_entry = runner.registry_by_id(runner_registry).get(seal["setupId"])
    registry = load_json(read_regular(root / "registry" / "setups.json", 4 << 20), "registry/setups.json")
    entry = next((item for item in registry.get("setups", []) if item.get("setupId") == seal["setupId"]), None)
    if entry is None or package_entry is None or sorted(entry["architectures"]) != seal["architectures"]:
        raise ValueError("selo diverge das arquiteturas canônicas")
    artifacts = seal["artifacts"]
    if not isinstance(artifacts, list) or len(artifacts) != len(seal["architectures"]):
        raise ValueError("artefatos do selo estão incompletos")
    seen: set[str] = set()
    for artifact in artifacts:
        if not isinstance(artifact, dict) or set(artifact) != {"architecture", "path", "sha256"}:
            raise ValueError("artefato do selo possui campos inesperados")
        arch = artifact["architecture"]
        if arch in seen or artifact != {"architecture": arch, **package_entry["artifacts"].get(arch, {})}:
            raise ValueError(f"artefato homologado diverge do registro atual: {arch}")
        source = root.parent / artifact["path"]
        if runner.sha256_file(source) != artifact["sha256"]:
            raise ValueError(f"código vivo mudou após a homologação: {arch}")
        seen.add(arch)


def validate_document_delta(
    payloads: dict[str, bytes], root: Path, seal: dict[str, Any],
) -> tuple[Path, bytes]:
    relative = f"setups/{seal['setupId']}/overview.md"
    name = f"setupmno-knowledge/{relative}"
    if name not in payloads:
        raise ValueError("documento homologado ausente no pacote")
    current_path = root / relative
    with tempfile.TemporaryDirectory(prefix="setupmno-import-doc-") as directory:
        source_path = Path(directory) / "overview.md"
        source_path.write_bytes(payloads[name])
        source = parse_document(source_path)
    current = parse_document(current_path)
    mutable = {"setupVersion", "status", "updatedAt", "homologation"}
    source_fixed = {key: value for key, value in source.metadata.items() if key not in mutable}
    current_fixed = {key: value for key, value in current.metadata.items() if key not in mutable}
    if source.body != current.body or source_fixed != current_fixed:
        raise ValueError("pacote tentou alterar conteúdo editorial fora da homologação")
    if source.metadata.get("status") != "homologated" or source.metadata.get("setupVersion") != seal["setupVersion"]:
        raise ValueError("documento do pacote não representa o selo emitido")
    homologation = source.metadata.get("homologation")
    if not isinstance(homologation, dict) or set(homologation) != {"verifiedAt", "verifiedPorts", "verifiedImages"}:
        raise ValueError("metadados de homologação do documento são inválidos")
    if not set(seal["images"]).issubset(set(homologation["verifiedImages"])):
        raise ValueError("documento não cobre as imagens do selo")
    try:
        updated_at = dt.date.fromisoformat(source.metadata["updatedAt"])
        verified_at = dt.date.fromisoformat(homologation["verifiedAt"])
    except (KeyError, TypeError, ValueError) as exc:
        raise ValueError("datas do documento homologado são inválidas") from exc
    if (
        updated_at < verified_at
        or not isinstance(homologation["verifiedPorts"], list)
        or not homologation["verifiedPorts"]
        or len(homologation["verifiedPorts"]) != len(set(homologation["verifiedPorts"]))
        or any(not isinstance(port, int) or not 1 <= port <= 65535 for port in homologation["verifiedPorts"])
        or not isinstance(homologation["verifiedImages"], list)
        or any(not IMAGE_RE.fullmatch(str(image)) for image in homologation["verifiedImages"])
    ):
        raise ValueError("metadados de homologação do documento são inconsistentes")
    target_metadata = copy.deepcopy(current.metadata)
    target_metadata.update({
        "status": "homologated",
        "updatedAt": source.metadata["updatedAt"],
        "homologation": homologation,
    })
    target = "---\n" + json.dumps(target_metadata, ensure_ascii=False, indent=2) + "\n---\n" + current.body + "\n"
    return current_path, target.encode("utf-8")


def validate_snapshots(
    payloads: dict[str, bytes], seal: dict[str, Any], seal_path: str,
) -> set[str]:
    setup_id = seal["setupId"]
    governance_path = "registry/governance.json"
    ledger_path = "registry/certification-ledger.json"
    quality_path = "registry/quality-report.json"
    governance = payload_json(payloads, governance_path)
    ledger = payload_json(payloads, ledger_path)
    quality = payload_json(payloads, quality_path)
    seal_hash = sha256(payloads[f"setupmno-knowledge/{seal_path}"])
    expected_promotion = {
        "maturity": "homologated",
        "architectureScope": "complete",
        "evidenceRefs": [{"path": item["path"], "sha256": item["sha256"]} for item in seal["evidenceRefs"]],
        "sealRef": {"path": seal_path, "sha256": seal_hash},
    }
    if governance.get("promotions", {}).get(setup_id) != expected_promotion:
        raise ValueError("snapshot de governança não confirma exatamente o selo")
    expected_ledger = {
        "sealId": seal["sealId"], "setupId": setup_id,
        "setupVersion": seal["setupVersion"], "issuedAt": seal["issuedAt"],
        "path": seal_path, "sha256": seal_hash,
    }
    if expected_ledger not in ledger.get("entries", []):
        raise ValueError("snapshot do ledger não contém o selo declarado")
    quality_entry = next((item for item in quality.get("entries", []) if item.get("setupId") == setup_id), None)
    if quality_entry is None or quality_entry.get("maturity") != "homologated":
        raise ValueError("snapshot de qualidade não confirma a homologação")
    return {
        f"setupmno-knowledge/{governance_path}",
        f"setupmno-knowledge/{ledger_path}",
        f"setupmno-knowledge/{quality_path}",
    }


def load_import_ledger(root: Path) -> tuple[Path, dict[str, Any]]:
    path = root / "registry" / "canonical-import-ledger.json"
    if not path.exists():
        return path, {"schemaVersion": 1, "kind": IMPORT_LEDGER_KIND, "entries": []}
    ledger = load_json(read_regular(path, 2 << 20), str(path))
    if not isinstance(ledger, dict) or set(ledger) != {"schemaVersion", "kind", "entries"}:
        raise ValueError("ledger de importação possui campos inesperados")
    if ledger["schemaVersion"] != 1 or ledger["kind"] != IMPORT_LEDGER_KIND or not isinstance(ledger["entries"], list):
        raise ValueError("ledger de importação é incompatível")
    return path, ledger


def git_state(root: Path) -> tuple[Path, str, bool]:
    completed = subprocess.run(
        ["git", "-C", str(root), "rev-parse", "--show-toplevel"],
        check=False, capture_output=True, text=True,
    )
    if completed.returncode != 0:
        raise ValueError("a importação canônica exige um repositório Git")
    repo = Path(completed.stdout.strip()).resolve()
    head = subprocess.run(
        ["git", "-C", str(repo), "rev-parse", "HEAD"], check=True,
        capture_output=True, text=True,
    ).stdout.strip()
    dirty = bool(subprocess.run(
        ["git", "-C", str(repo), "status", "--porcelain"], check=True,
        capture_output=True, text=True,
    ).stdout.strip())
    return repo, head, dirty


def plan_import(
    pack: Path, root: Path, catalog: Path, package_dir: Path,
    imported_by: str, imported_at: str,
) -> dict[str, Any]:
    imported_by = " ".join(imported_by.split())
    if not 2 <= len(imported_by) <= 80:
        raise ValueError("identificação do importador deve ter entre 2 e 80 caracteres")
    runner.reject_sensitive(imported_by, "identificação do importador")
    parse_utc(imported_at, "importedAt")
    manifest, payloads, pack_hash = load_pack(pack)
    provenance = validate_source_attestation(manifest, payloads, root, catalog, package_dir)
    seal, seal_path, seal_data = validate_seal(manifest, payloads)
    validate_artifacts(seal, root, package_dir)
    ref_paths = validate_refs(seal, payloads)
    snapshot_paths = validate_snapshots(payloads, seal, seal_path)
    document_path, document_data = validate_document_delta(payloads, root, seal)
    expected_payloads = ref_paths | snapshot_paths | {
        f"setupmno-knowledge/{seal_path}",
        f"setupmno-knowledge/setups/{seal['setupId']}/overview.md",
    }
    if set(payloads) != expected_payloads | {"manifest.json"}:
        raise ValueError("release-pack contém arquivos não autorizados")

    governance_path = root / "registry" / "governance.json"
    governance = load_json(read_regular(governance_path, 2 << 20), str(governance_path))
    if any(item.get("setupId") == seal["setupId"] for item in governance.get("knownIssues", [])):
        raise ValueError("importação bloqueada por pendências canônicas atuais")
    governance_new = copy.deepcopy(governance)
    governance_new.setdefault("promotions", {})[seal["setupId"]] = {
        "maturity": "homologated", "architectureScope": "complete",
        "evidenceRefs": [{"path": item["path"], "sha256": item["sha256"]} for item in seal["evidenceRefs"]],
        "sealRef": {"path": seal_path, "sha256": sha256(seal_data)},
    }
    ledger_path, ledger = validate_ledger(root)
    ledger_new = copy.deepcopy(ledger)
    ledger_entry = {
        "sealId": seal["sealId"], "setupId": seal["setupId"],
        "setupVersion": seal["setupVersion"], "issuedAt": seal["issuedAt"],
        "path": seal_path, "sha256": sha256(seal_data),
    }
    if any(item["sealId"] == seal["sealId"] or item["path"] == seal_path for item in ledger_new["entries"]):
        raise ValueError("este selo já foi importado no ledger canônico")
    ledger_new["entries"].append(ledger_entry)
    ledger_new["entries"].sort(key=lambda item: (item["issuedAt"], item["sealId"]))

    import_ledger_path, import_ledger = load_import_ledger(root)
    if any(item.get("packageSHA256") == pack_hash or item.get("sealId") == seal["sealId"] for item in import_ledger["entries"]):
        raise ValueError("este release-pack já foi importado")
    import_ledger_new = copy.deepcopy(import_ledger)
    import_ledger_new["entries"].append({
        "sealId": seal["sealId"], "setupId": seal["setupId"],
        "sourceSetupVersion": seal["setupVersion"], "packageSHA256": pack_hash,
        "provenance": provenance, "importedAt": imported_at, "importedBy": imported_by,
        "sealPath": seal_path, "sealSHA256": sha256(seal_data),
    })
    import_ledger_new["entries"].sort(key=lambda item: (item["importedAt"], item["sealId"]))

    writes: list[tuple[Path, bytes | None, bool]] = []
    new_evidence_paths = {item["path"] for item in seal["evidenceRefs"]}
    current_promotion = governance.get("promotions", {}).get(seal["setupId"], {})
    for reference in current_promotion.get("evidenceRefs", []):
        relative = safe_relative(reference.get("path", ""))
        parts = Path(relative).parts
        if (
            relative not in new_evidence_paths
            and len(parts) == 4
            and parts[:2] == ("evidence", seal["setupId"])
        ):
            previous_path = root / relative
            previous_data = read_regular(previous_path, 1 << 20)
            if sha256(previous_data) != reference.get("sha256"):
                raise ValueError(f"evidência anterior diverge da governança: {relative}")
            writes.append((previous_path, None, False))
    for item in seal["evidenceRefs"] + seal["decisionRefs"]:
        writes.append((root / item["path"], payloads[f"setupmno-knowledge/{item['path']}"], True))
    writes.extend([
        (root / seal_path, seal_data, True),
        (document_path, document_data, False),
        (governance_path, canonical_json(governance_new), False),
        (ledger_path, canonical_json(ledger_new), False),
        (import_ledger_path, canonical_json(import_ledger_new), False),
    ])
    repo, head, dirty = git_state(root)
    changes = []
    token_material = [pack_hash.encode(), head.encode()]
    for path, data, _ in writes:
        old = read_regular(path, 8 << 20) if path.exists() else b""
        state = (
            "delete" if data is None
            else "unchanged" if old == data
            else "update" if old
            else "create"
        )
        changes.append({
            "path": path.relative_to(repo).as_posix(), "status": state,
            "oldSHA256": sha256(old) if old else None,
            "newSHA256": sha256(data) if data is not None else None,
        })
        token_material.extend([
            str(path).encode(), sha256(old).encode(),
            sha256(data).encode() if data is not None else b"DELETE",
        ])
    token = hashlib.sha256(b"\0".join(token_material)).hexdigest()[:16].upper()
    return {
        "pack": pack, "packSHA256": pack_hash, "manifest": manifest, "seal": seal,
        "sealPath": seal_path, "provenance": provenance, "writes": writes,
        "catalog": catalog, "root": root, "repo": repo, "gitHead": head,
        "gitDirty": dirty, "changes": changes, "confirmationToken": token,
    }


def validate_destination(root: Path, path: Path) -> None:
    if not path.is_relative_to(root) or path == root or path.is_symlink():
        raise ValueError(f"destino inseguro: {path}")
    current = path.parent
    while current != root:
        if current.is_symlink():
            raise ValueError(f"diretório de destino inseguro: {current}")
        current = current.parent


def apply_transaction(plan: dict[str, Any]) -> None:
    root, repo = plan["root"], plan["repo"]
    _, current_head, dirty = git_state(root)
    if dirty or current_head != plan["gitHead"]:
        raise ValueError("o repositório mudou após o dry-run; limpe-o e gere um novo token")
    quality_path = root / "registry" / "quality-report.json"
    originals: dict[Path, bytes | None] = {}
    targets = plan["writes"]
    for path, data, immutable in targets:
        validate_destination(root, path)
        if path in originals:
            raise ValueError(f"destino repetido: {path}")
        original = read_regular(path, 8 << 20) if path.exists() else None
        if immutable and original is not None and original != data:
            raise ValueError(f"destino imutável já contém outro conteúdo: {path}")
        originals[path] = original
    originals[quality_path] = read_regular(quality_path, 8 << 20) if quality_path.exists() else None
    try:
        for path, data, immutable in targets:
            if data is None:
                path.unlink(missing_ok=True)
            elif originals[path] != data:
                runner.atomic_write(path, data, 0o644)
        quality = subprocess.run([
            sys.executable, "-B", str(root / "tools" / "knowledge_quality.py"),
            "--root", str(root), "--catalog", str(plan["catalog"]),
            "--write-report", str(quality_path), "--enforce-baseline",
        ], check=True, capture_output=True, text=True)
        if not quality.stdout.strip():
            raise ValueError("gate de qualidade não produziu evidência")
        subprocess.run([
            sys.executable, "-B", str(root / "tools" / "lint_knowledge.py"), "lint",
            "--root", str(root), "--catalog", str(plan["catalog"]),
            "--setup-version", load_json(read_regular(root / "registry" / "setups.json", 4 << 20), "registry")["setupVersion"],
        ], check=True, capture_output=True, text=True)
        changed = set(filter(None, subprocess.run(
            ["git", "-C", str(repo), "diff", "--name-only"], check=True,
            capture_output=True, text=True,
        ).stdout.splitlines()))
        expected = {path.relative_to(repo).as_posix() for path, _, _ in targets} | {quality_path.relative_to(repo).as_posix()}
        if changed - expected:
            raise ValueError("o gate detectou alterações fora do delta autorizado: " + ", ".join(sorted(changed - expected)))
    except Exception:
        for path, original in reversed(list(originals.items())):
            if original is None:
                path.unlink(missing_ok=True)
                current = path.parent
                while current != root and current.exists():
                    try:
                        current.rmdir()
                    except OSError:
                        break
                    current = current.parent
            else:
                runner.atomic_write(path, original, 0o644)
        raise


def public_result(plan: dict[str, Any], applied: bool) -> dict[str, Any]:
    return {
        "mode": "apply" if applied else "dry-run",
        "setupId": plan["seal"]["setupId"],
        "sourceSetupVersion": plan["seal"]["setupVersion"],
        "sealId": plan["seal"]["sealId"],
        "sealSHA256": sha256(canonical_json(plan["seal"])),
        "packageSHA256": plan["packSHA256"],
        "provenance": plan["provenance"],
        "confirmationToken": plan["confirmationToken"],
        "gitHead": plan["gitHead"], "gitClean": not plan["gitDirty"],
        "changes": plan["changes"],
        "gates": {
            "strictInventory": True, "sourceAttestation": True,
            "immutableArtifacts": True, "allArchitectures": True,
            "allNineChecks": True, "snapshotAssertions": True,
            "transactionalRollback": True,
        },
        "canonicalImported": applied, "releaseReady": applied,
        "automaticPublication": False, "commitCreated": False,
        "tagCreated": False, "releaseCreated": False,
    }


def main() -> int:
    default_root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack", type=Path, required=True)
    parser.add_argument("--root", type=Path, default=default_root)
    parser.add_argument("--catalog", type=Path, default=default_root.parent / "setupmno-control" / "catalog.json")
    parser.add_argument("--package-dir", type=Path, default=default_root.parent / "setupmno-control" / "homologation-package")
    parser.add_argument("--imported-by", required=True)
    parser.add_argument("--imported-at", default=dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"))
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--confirm", default="")
    args = parser.parse_args()
    plan = plan_import(
        args.pack.resolve(), args.root.resolve(), args.catalog.resolve(),
        args.package_dir.resolve(), args.imported_by, args.imported_at,
    )
    if not args.apply:
        print(json.dumps(public_result(plan, False), ensure_ascii=False, sort_keys=True))
        return 0
    if plan["gitDirty"]:
        raise ValueError("a aplicação exige Git limpo; preserve ou descarte as alterações antes de importar")
    if args.confirm != plan["confirmationToken"]:
        raise ValueError("confirmação inválida; execute o dry-run e informe o token exibido")
    apply_transaction(plan)
    print(json.dumps(public_result(plan, True), ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, json.JSONDecodeError, subprocess.CalledProcessError) as exc:
        detail = str(exc)
        if isinstance(exc, subprocess.CalledProcessError):
            detail = (exc.stderr or exc.stdout or detail).strip()
        print(f"ERRO: {detail}", file=sys.stderr)
        raise SystemExit(2)
