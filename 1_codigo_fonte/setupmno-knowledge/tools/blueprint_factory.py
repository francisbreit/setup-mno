#!/usr/bin/python3
"""Valida e empacota Blueprints MNO de forma determinística e sem dependências."""

from __future__ import annotations

import argparse
from collections import Counter
import datetime as dt
import hashlib
import ipaddress
import io
import json
import os
import re
import sys
import tempfile
import urllib.parse
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any


BLUEPRINT_SCHEMA_VERSION = 1
BLUEPRINT_FACTORY_VERSION = "1.1.0"
MAX_BLUEPRINTS = 64
MAX_FILES_PER_BLUEPRINT = 128
MAX_FILE_BYTES = 2 << 20
MAX_BUNDLE_BYTES = 8 << 20
MAX_TOTAL_BUNDLE_BYTES = 32 << 20
SEMVER_RE = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
ID_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
URL_RE = re.compile(r"https://[^\s<>)\]}]+")
IPV4_RE = re.compile(r"(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])")
TEXT_SUFFIXES = {".json", ".md", ".txt", ".example"}
ALLOWED_SUFFIXES = TEXT_SUFFIXES | {".pdf", ".png", ".jpg", ".jpeg", ".webp"}
STATUSES = {"example", "draft", "reviewed", "homologated", "deprecated"}
RISKS = {"low", "medium", "high", "critical"}
ARCHITECTURES = {"amd64", "arm64"}
MEDIA_TYPES = {"video", "link"}
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

REQUIRED_FIELDS = {
    "schemaVersion",
    "blueprintId",
    "blueprintVersion",
    "title",
    "summary",
    "author",
    "status",
    "fictitious",
    "deployable",
    "setupVersion",
    "updatedAt",
    "architectures",
    "risk",
    "audiences",
    "tags",
    "aliases",
    "objective",
    "components",
    "resourceProfile",
    "installation",
    "validation",
    "rollback",
    "media",
    "documentation",
}


@dataclass(frozen=True)
class BlueprintRecord:
    directory: Path
    manifest: dict[str, Any]
    files: dict[str, bytes]
    bundle_path: str
    bundle_data: bytes


def canonical_json(value: Any) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
        + "\n"
    ).encode("utf-8")


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def is_iso_date(value: Any) -> bool:
    if not isinstance(value, str):
        return False
    try:
        dt.date.fromisoformat(value)
    except ValueError:
        return False
    return True


def is_safe_relative_path(value: str) -> bool:
    if not value or value.startswith("/") or "\\" in value:
        return False
    path = Path(value)
    return str(path) == value and path != Path(".") and ".." not in path.parts


def find_private_ips(text: str) -> list[str]:
    result: list[str] = []
    for candidate in IPV4_RE.findall(text):
        try:
            address = ipaddress.ip_address(candidate)
        except ValueError:
            continue
        if address.is_private or address.is_loopback or address.is_link_local:
            result.append(candidate)
    return sorted(set(result))


def catalog_architectures(entry: dict[str, Any]) -> set[str]:
    value = entry.get("arch")
    if value == "x86-arm":
        return {"amd64", "arm64"}
    if value == "x86":
        return {"amd64"}
    return set()


def validate_string_list(
    value: Any,
    field: str,
    *,
    identifiers: bool = False,
    minimum: int = 1,
) -> list[str]:
    errors: list[str] = []
    if not isinstance(value, list) or len(value) < minimum:
        return [f"{field} deve ser uma lista com ao menos {minimum} item(ns)"]
    if len(value) != len(set(map(str, value))):
        errors.append(f"{field} contém duplicatas")
    for item in value:
        if not isinstance(item, str) or not item.strip():
            errors.append(f"{field} contém texto vazio ou inválido")
        elif identifiers and not ID_RE.fullmatch(item):
            errors.append(f"{field} contém ID inválido: {item}")
    return errors


def validate_components(
    value: Any,
    blueprint_architectures: set[str],
    catalog_by_name: dict[str, dict[str, Any]],
) -> list[str]:
    errors: list[str] = []
    if not isinstance(value, list) or not value:
        return ["components deve ser uma lista não vazia"]
    seen_names: set[str] = set()
    orders: list[int] = []
    expected_fields = {"catalogName", "role", "required", "installOrder"}
    for index, component in enumerate(value):
        prefix = f"components[{index}]"
        if not isinstance(component, dict) or set(component) != expected_fields:
            errors.append(f"{prefix} deve conter exatamente {', '.join(sorted(expected_fields))}")
            continue
        name = component.get("catalogName")
        if not isinstance(name, str) or name not in catalog_by_name:
            errors.append(f"{prefix}.catalogName não existe no catálogo canônico")
        elif name in seen_names:
            errors.append(f"{prefix}.catalogName duplicado")
        else:
            seen_names.add(name)
            if component.get("required") is True:
                supported = catalog_architectures(catalog_by_name[name])
                if not blueprint_architectures.issubset(supported):
                    errors.append(
                        f"{prefix} é incompatível com as arquiteturas do Blueprint"
                    )
        role = component.get("role")
        if not isinstance(role, str) or not 5 <= len(role) <= 240:
            errors.append(f"{prefix}.role deve conter entre 5 e 240 caracteres")
        if not isinstance(component.get("required"), bool):
            errors.append(f"{prefix}.required deve ser booleano")
        order = component.get("installOrder")
        if not isinstance(order, int) or isinstance(order, bool) or order < 1:
            errors.append(f"{prefix}.installOrder deve ser inteiro positivo")
        else:
            orders.append(order)
    if sorted(orders) != list(range(1, len(value) + 1)):
        errors.append("components.installOrder deve formar uma sequência contínua iniciada em 1")
    return errors


def validate_installation(value: Any, components: Any) -> list[str]:
    errors: list[str] = []
    expected_fields = {"mode", "humanConfirmationRequired", "steps"}
    if not isinstance(value, dict) or set(value) != expected_fields:
        return ["installation possui campos ausentes ou desconhecidos"]
    if value.get("mode") != "assisted-manual":
        errors.append("installation.mode deve ser assisted-manual nesta fase")
    if value.get("humanConfirmationRequired") is not True:
        errors.append("installation.humanConfirmationRequired deve ser true")
    steps = value.get("steps")
    component_names = {
        item.get("catalogName") for item in components if isinstance(item, dict)
    } if isinstance(components, list) else set()
    expected_step_fields = {
        "step",
        "component",
        "title",
        "description",
        "humanConfirmation",
    }
    if not isinstance(steps, list) or not steps:
        return errors + ["installation.steps deve ser uma lista não vazia"]
    numbers: list[int] = []
    for index, step in enumerate(steps):
        prefix = f"installation.steps[{index}]"
        if not isinstance(step, dict) or set(step) != expected_step_fields:
            errors.append(f"{prefix} possui campos ausentes ou desconhecidos")
            continue
        number = step.get("step")
        if not isinstance(number, int) or isinstance(number, bool) or number < 1:
            errors.append(f"{prefix}.step deve ser inteiro positivo")
        else:
            numbers.append(number)
        if step.get("component") not in component_names:
            errors.append(f"{prefix}.component não existe em components")
        for field in ("title", "description"):
            if not isinstance(step.get(field), str) or len(step[field]) < 5:
                errors.append(f"{prefix}.{field} é inválido")
        if not isinstance(step.get("humanConfirmation"), bool):
            errors.append(f"{prefix}.humanConfirmation deve ser booleano")
    if sorted(numbers) != list(range(1, len(steps) + 1)):
        errors.append("installation.steps deve formar sequência contínua iniciada em 1")
    return errors


def validate_validation(value: Any, status: Any) -> list[str]:
    errors: list[str] = []
    expected_fields = {"homologatedAt", "checks"}
    if not isinstance(value, dict) or set(value) != expected_fields:
        return ["validation possui campos ausentes ou desconhecidos"]
    homologated_at = value.get("homologatedAt")
    if homologated_at is not None and not is_iso_date(homologated_at):
        errors.append("validation.homologatedAt deve ser nulo ou usar YYYY-MM-DD")
    if status == "homologated" and homologated_at is None:
        errors.append("Blueprint homologated exige validation.homologatedAt")
    if status != "homologated" and homologated_at is not None:
        errors.append("somente Blueprint homologated pode declarar homologatedAt")
    checks = value.get("checks")
    expected_check_fields = {"checkId", "description", "expected", "required"}
    if not isinstance(checks, list) or len(checks) < 3:
        return errors + ["validation.checks deve conter ao menos três verificações"]
    seen: set[str] = set()
    for index, check in enumerate(checks):
        prefix = f"validation.checks[{index}]"
        if not isinstance(check, dict) or set(check) != expected_check_fields:
            errors.append(f"{prefix} possui campos ausentes ou desconhecidos")
            continue
        check_id = check.get("checkId")
        if not isinstance(check_id, str) or not ID_RE.fullmatch(check_id):
            errors.append(f"{prefix}.checkId inválido")
        elif check_id in seen:
            errors.append(f"{prefix}.checkId duplicado")
        else:
            seen.add(check_id)
        for field in ("description", "expected"):
            if not isinstance(check.get(field), str) or len(check[field]) < 5:
                errors.append(f"{prefix}.{field} é inválido")
        if check.get("required") is not True:
            errors.append(f"{prefix}.required deve ser true")
    return errors


def validate_media(value: Any, fictitious: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(value, list):
        return ["media deve ser uma lista"]
    expected_fields = {"mediaId", "type", "title", "url", "status", "transcript"}
    seen: set[str] = set()
    for index, item in enumerate(value):
        prefix = f"media[{index}]"
        if not isinstance(item, dict) or set(item) != expected_fields:
            errors.append(f"{prefix} possui campos ausentes ou desconhecidos")
            continue
        media_id = item.get("mediaId")
        if not isinstance(media_id, str) or not ID_RE.fullmatch(media_id):
            errors.append(f"{prefix}.mediaId inválido")
        elif media_id in seen:
            errors.append(f"{prefix}.mediaId duplicado")
        else:
            seen.add(media_id)
        if item.get("type") not in MEDIA_TYPES:
            errors.append(f"{prefix}.type inválido")
        if not isinstance(item.get("title"), str) or len(item["title"]) < 5:
            errors.append(f"{prefix}.title inválido")
        url = item.get("url")
        parsed = urllib.parse.urlparse(url) if isinstance(url, str) else None
        if parsed is None or parsed.scheme != "https" or not parsed.hostname:
            errors.append(f"{prefix}.url deve usar HTTPS")
        elif fictitious is True and not parsed.hostname.endswith(".invalid"):
            errors.append(f"{prefix}.url fictícia deve usar domínio reservado .invalid")
        if item.get("status") not in {"example", "reviewed"}:
            errors.append(f"{prefix}.status inválido")
        transcript = item.get("transcript")
        if transcript is not None and (
            not isinstance(transcript, str) or not is_safe_relative_path(transcript)
        ):
            errors.append(f"{prefix}.transcript deve ser nulo ou caminho relativo seguro")
    return errors


def validate_manifest(
    manifest: Any,
    directory_name: str,
    catalog_by_name: dict[str, dict[str, Any]],
    setup_version: str,
) -> list[str]:
    if not isinstance(manifest, dict):
        return ["blueprint.json deve conter um objeto JSON"]
    errors: list[str] = []
    missing = REQUIRED_FIELDS - set(manifest)
    unknown = set(manifest) - REQUIRED_FIELDS
    if missing:
        errors.append("campos ausentes: " + ", ".join(sorted(missing)))
    if unknown:
        errors.append("campos desconhecidos: " + ", ".join(sorted(unknown)))
    if manifest.get("schemaVersion") != BLUEPRINT_SCHEMA_VERSION:
        errors.append(f"schemaVersion deve ser {BLUEPRINT_SCHEMA_VERSION}")
    blueprint_id = manifest.get("blueprintId")
    if not isinstance(blueprint_id, str) or not ID_RE.fullmatch(blueprint_id):
        errors.append("blueprintId inválido")
    elif blueprint_id != directory_name:
        errors.append("blueprintId deve ser idêntico ao nome da pasta")
    if not SEMVER_RE.fullmatch(str(manifest.get("blueprintVersion", ""))):
        errors.append("blueprintVersion deve seguir SemVer")
    if manifest.get("setupVersion") != setup_version:
        errors.append("setupVersion diverge da release em construção")
    if not is_iso_date(manifest.get("updatedAt")):
        errors.append("updatedAt deve usar YYYY-MM-DD")
    for field, minimum, maximum in (
        ("title", 8, 120),
        ("summary", 20, 360),
        ("author", 3, 120),
        ("objective", 20, 600),
    ):
        value = manifest.get(field)
        if not isinstance(value, str) or not minimum <= len(value) <= maximum:
            errors.append(f"{field} deve conter entre {minimum} e {maximum} caracteres")
    status = manifest.get("status")
    if status not in STATUSES:
        errors.append("status inválido")
    fictitious = manifest.get("fictitious")
    deployable = manifest.get("deployable")
    if not isinstance(fictitious, bool) or not isinstance(deployable, bool):
        errors.append("fictitious e deployable devem ser booleanos")
    if status == "example" and (fictitious is not True or deployable is not False):
        errors.append("status example exige fictitious=true e deployable=false")
    if status == "homologated" and (fictitious is not False or deployable is not True):
        errors.append("status homologated exige fictitious=false e deployable=true")
    architectures = manifest.get("architectures")
    errors.extend(validate_string_list(architectures, "architectures"))
    architecture_set = set(architectures) if isinstance(architectures, list) else set()
    if not architecture_set.issubset(ARCHITECTURES):
        errors.append("architectures contém valor inválido")
    if manifest.get("risk") not in RISKS:
        errors.append("risk inválido")
    errors.extend(validate_string_list(manifest.get("audiences"), "audiences", identifiers=True))
    errors.extend(validate_string_list(manifest.get("tags"), "tags", identifiers=True, minimum=2))
    errors.extend(validate_string_list(manifest.get("aliases"), "aliases", minimum=2))
    components = manifest.get("components")
    errors.extend(validate_components(components, architecture_set, catalog_by_name))

    resource = manifest.get("resourceProfile")
    expected_resource = {"minimumRamGB", "recommendedRamGB", "basis"}
    if not isinstance(resource, dict) or set(resource) != expected_resource:
        errors.append("resourceProfile possui campos ausentes ou desconhecidos")
    else:
        minimum = resource.get("minimumRamGB")
        recommended = resource.get("recommendedRamGB")
        if (
            not isinstance(minimum, int)
            or isinstance(minimum, bool)
            or minimum < 1
            or not isinstance(recommended, int)
            or isinstance(recommended, bool)
            or recommended < minimum
        ):
            errors.append("resourceProfile exige RAM inteira e recommendedRamGB >= minimumRamGB")
        if not isinstance(resource.get("basis"), str) or len(resource["basis"]) < 10:
            errors.append("resourceProfile.basis inválido")

    errors.extend(validate_installation(manifest.get("installation"), components))
    errors.extend(validate_validation(manifest.get("validation"), status))

    rollback = manifest.get("rollback")
    expected_rollback = {"strategy", "steps"}
    if not isinstance(rollback, dict) or set(rollback) != expected_rollback:
        errors.append("rollback possui campos ausentes ou desconhecidos")
    else:
        if not isinstance(rollback.get("strategy"), str) or len(rollback["strategy"]) < 10:
            errors.append("rollback.strategy inválido")
        errors.extend(validate_string_list(rollback.get("steps"), "rollback.steps", minimum=2))

    errors.extend(validate_media(manifest.get("media"), fictitious))
    documentation = manifest.get("documentation")
    expected_documentation = {"entrypoint", "artifacts"}
    if not isinstance(documentation, dict) or set(documentation) != expected_documentation:
        errors.append("documentation possui campos ausentes ou desconhecidos")
    else:
        if documentation.get("entrypoint") != "README.md":
            errors.append("documentation.entrypoint deve ser README.md")
        artifacts = documentation.get("artifacts")
        errors.extend(validate_string_list(artifacts, "documentation.artifacts"))
        if isinstance(artifacts, list) and any(
            not isinstance(path, str) or not is_safe_relative_path(path)
            for path in artifacts
        ):
            errors.append("documentation.artifacts contém caminho inseguro")
    return errors


def collect_source_files(
    directory: Path,
    *,
    fictitious: bool,
) -> tuple[dict[str, bytes], list[str]]:
    files: dict[str, bytes] = {}
    errors: list[str] = []
    for path in sorted(directory.rglob("*")):
        relative = path.relative_to(directory).as_posix()
        if path.is_symlink():
            errors.append(f"symlink proibido: {relative}")
            continue
        if path.is_dir():
            continue
        if not path.is_file():
            errors.append(f"entrada não regular: {relative}")
            continue
        if not is_safe_relative_path(relative):
            errors.append(f"caminho inseguro: {relative}")
            continue
        if path.suffix.casefold() not in ALLOWED_SUFFIXES:
            errors.append(f"extensão não permitida: {relative}")
            continue
        size = path.stat().st_size
        if size <= 0 or size > MAX_FILE_BYTES:
            errors.append(f"tamanho inválido: {relative}")
            continue
        data = path.read_bytes()
        if path.suffix.casefold() in TEXT_SUFFIXES:
            try:
                text = data.decode("utf-8")
            except UnicodeDecodeError:
                errors.append(f"arquivo textual não está em UTF-8: {relative}")
                continue
            for name, pattern in SECRET_PATTERNS.items():
                if pattern.search(text):
                    errors.append(f"{relative}: padrão proibido detectado: {name}")
            private_ips = find_private_ips(text)
            if private_ips:
                errors.append(f"{relative}: IP privado/local detectado")
            if fictitious:
                for url in URL_RE.findall(text):
                    hostname = urllib.parse.urlparse(url.rstrip(".,;:'\"")).hostname
                    if hostname is None or not hostname.endswith(".invalid"):
                        errors.append(
                            f"{relative}: URL fictícia fora do domínio reservado .invalid"
                        )
        files[relative] = data
    if len(files) > MAX_FILES_PER_BLUEPRINT:
        errors.append(f"quantidade de arquivos excede {MAX_FILES_PER_BLUEPRINT}")
    return files, errors


def deterministic_zip(blueprint_id: str, files: dict[str, bytes]) -> bytes:
    output = io.BytesIO()
    with zipfile.ZipFile(
        output,
        mode="w",
        compression=zipfile.ZIP_DEFLATED,
        compresslevel=9,
        strict_timestamps=True,
    ) as archive:
        for relative in sorted(files):
            info = zipfile.ZipInfo(
                filename=f"{blueprint_id}/{relative}",
                date_time=(1980, 1, 1, 0, 0, 0),
            )
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            info.flag_bits |= 0x800
            archive.writestr(info, files[relative], compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    return output.getvalue()


def load_blueprints(
    root: Path,
    catalog_path: Path,
    setup_version: str,
) -> list[BlueprintRecord]:
    if not SEMVER_RE.fullmatch(setup_version):
        raise ValueError("setup_version deve seguir SemVer")
    catalog = load_json(catalog_path)
    if not isinstance(catalog, list):
        raise ValueError("catálogo canônico deve ser uma lista")
    catalog_by_name = {
        entry["name"]: entry
        for entry in catalog
        if isinstance(entry, dict) and isinstance(entry.get("name"), str)
    }
    base = root / "blueprints"
    if not base.is_dir():
        raise ValueError("diretório blueprints ausente")
    directories = [path for path in sorted(base.iterdir()) if path.is_dir()]
    if not directories:
        raise ValueError("nenhum Blueprint encontrado")
    if len(directories) > MAX_BLUEPRINTS:
        raise ValueError(f"quantidade de Blueprints excede {MAX_BLUEPRINTS}")
    records: list[BlueprintRecord] = []
    seen_ids: set[str] = set()
    all_errors: list[str] = []
    total_bundle_bytes = 0
    for directory in directories:
        prefix = directory.relative_to(root).as_posix()
        manifest_path = directory / "blueprint.json"
        if not manifest_path.is_file() or manifest_path.is_symlink():
            all_errors.append(f"{prefix}: blueprint.json regular ausente")
            continue
        try:
            manifest = load_json(manifest_path)
        except (OSError, json.JSONDecodeError) as exc:
            all_errors.append(f"{prefix}: blueprint.json inválido: {exc}")
            continue
        errors = validate_manifest(
            manifest,
            directory.name,
            catalog_by_name,
            setup_version,
        )
        files, file_errors = collect_source_files(
            directory,
            fictitious=isinstance(manifest, dict) and manifest.get("fictitious") is True,
        )
        errors.extend(file_errors)
        blueprint_id = manifest.get("blueprintId") if isinstance(manifest, dict) else None
        if isinstance(blueprint_id, str):
            if blueprint_id in seen_ids:
                errors.append("blueprintId duplicado")
            seen_ids.add(blueprint_id)
        documentation = manifest.get("documentation", {}) if isinstance(manifest, dict) else {}
        for relative in documentation.get("artifacts", []) if isinstance(documentation, dict) else []:
            if isinstance(relative, str) and relative not in files:
                errors.append(f"artefato declarado não existe: {relative}")
        for item in manifest.get("media", []) if isinstance(manifest, dict) else []:
            transcript = item.get("transcript") if isinstance(item, dict) else None
            if transcript is not None and transcript not in files:
                errors.append(f"transcrição declarada não existe: {transcript}")
        if errors:
            all_errors.extend(f"{prefix}: {error}" for error in errors)
            continue
        assert isinstance(blueprint_id, str)
        version = manifest["blueprintVersion"]
        bundle_path = f"blueprints/bundles/{blueprint_id}-v{version}.zip"
        bundle_data = deterministic_zip(blueprint_id, files)
        if len(bundle_data) <= 0 or len(bundle_data) > MAX_BUNDLE_BYTES:
            all_errors.append(f"{prefix}: bundle excede o limite de {MAX_BUNDLE_BYTES} bytes")
            continue
        total_bundle_bytes += len(bundle_data)
        records.append(
            BlueprintRecord(
                directory=directory,
                manifest=manifest,
                files=files,
                bundle_path=bundle_path,
                bundle_data=bundle_data,
            )
        )
    if total_bundle_bytes > MAX_TOTAL_BUNDLE_BYTES:
        all_errors.append("soma dos bundles excede o limite global")
    if all_errors:
        raise ValueError("\n".join(sorted(all_errors)))
    return records


def build_blueprint_package(
    root: Path,
    catalog_path: Path,
    setup_version: str,
) -> tuple[dict[str, bytes], dict[str, Any]]:
    records = load_blueprints(root, catalog_path, setup_version)
    entries: list[dict[str, Any]] = []
    package_files: dict[str, bytes] = {}
    latest_date = ""
    for record in sorted(records, key=lambda item: item.manifest["blueprintId"]):
        manifest = record.manifest
        latest_date = max(latest_date, manifest["updatedAt"])
        package_files[record.bundle_path] = record.bundle_data
        entries.append(
            {
                "aliases": manifest["aliases"],
                "architectures": manifest["architectures"],
                "author": manifest["author"],
                "blueprintId": manifest["blueprintId"],
                "blueprintVersion": manifest["blueprintVersion"],
                "bundleBytes": len(record.bundle_data),
                "bundlePath": record.bundle_path,
                "bundleSHA256": sha256_hex(record.bundle_data),
                "components": [item["catalogName"] for item in manifest["components"]],
                "deployable": manifest["deployable"],
                "fictitious": manifest["fictitious"],
                "media": manifest["media"],
                "objective": manifest["objective"],
                "resourceProfile": manifest["resourceProfile"],
                "risk": manifest["risk"],
                "status": manifest["status"],
                "summary": manifest["summary"],
                "tags": manifest["tags"],
                "title": manifest["title"],
                "updatedAt": manifest["updatedAt"],
            }
        )
    statuses = dict(sorted(Counter(entry["status"] for entry in entries).items()))
    index = {
        "schemaVersion": BLUEPRINT_SCHEMA_VERSION,
        "factoryVersion": BLUEPRINT_FACTORY_VERSION,
        "setupVersion": setup_version,
        "blueprintCount": len(entries),
        "statuses": statuses,
        "entries": entries,
    }
    index_data = canonical_json(index)
    schema_data = (root / "schema" / "blueprint.schema.json").read_bytes()
    package_files["blueprints/index.json"] = index_data
    package_files["blueprints/schema/blueprint.schema.json"] = schema_data
    inventory = [
        {
            "path": path,
            "sha256": sha256_hex(data),
            "size": len(data),
        }
        for path, data in sorted(package_files.items())
    ]
    blueprint_manifest = {
        "schemaVersion": BLUEPRINT_SCHEMA_VERSION,
        "factoryVersion": BLUEPRINT_FACTORY_VERSION,
        "setupVersion": setup_version,
        "generatedAt": latest_date + "T00:00:00Z",
        "blueprintEntries": len(entries),
        "bundleEntries": len(records),
        "indexFile": "blueprints/index.json",
        "indexSHA256": sha256_hex(index_data),
        "files": inventory,
    }
    package_files["blueprints/manifest.json"] = canonical_json(blueprint_manifest)
    return package_files, {
        "blueprintEntries": len(entries),
        "blueprintBundleEntries": len(records),
        "blueprintFactoryVersion": BLUEPRINT_FACTORY_VERSION,
        "blueprintIndexSHA256": sha256_hex(index_data),
        "latestBlueprintDate": latest_date,
    }


def atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink():
        raise ValueError(f"destino não pode ser symlink: {path}")
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=path.name + ".",
        suffix=".tmp",
        dir=path.parent,
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o644)
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def generate_output(
    root: Path,
    catalog: Path,
    output: Path,
    setup_version: str,
) -> dict[str, Any]:
    package_files, summary = build_blueprint_package(root, catalog, setup_version)
    output.mkdir(parents=True, exist_ok=True)
    expected: dict[str, bytes] = {}
    for package_path, data in package_files.items():
        if package_path == "blueprints/index.json":
            expected["index.json"] = data
        elif package_path == "blueprints/manifest.json":
            expected["manifest.json"] = data
        elif package_path.startswith("blueprints/"):
            expected[package_path.removeprefix("blueprints/")] = data
    expected_paths = set(expected)
    for existing in sorted(output.rglob("*"), reverse=True):
        if existing.is_symlink():
            raise ValueError(f"destino contém symlink: {existing}")
        if existing.is_file() and existing.relative_to(output).as_posix() not in expected_paths:
            existing.unlink()
        elif existing.is_dir() and not any(existing.iterdir()):
            existing.rmdir()
    for relative, data in expected.items():
        atomic_write(output / relative, data)
    first = {path: sha256_hex(data) for path, data in expected.items()}
    second_files, _ = build_blueprint_package(root, catalog, setup_version)
    second: dict[str, str] = {}
    for package_path, data in second_files.items():
        normalized = package_path.removeprefix("blueprints/")
        second[normalized] = sha256_hex(data)
    if first != second:
        raise ValueError("a fábrica de Blueprints não é reproduzível")
    return summary


def parse_args() -> argparse.Namespace:
    default_root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=default_root)
    parser.add_argument(
        "--catalog",
        type=Path,
        default=default_root.parent / "setupmno-control" / "catalog.json",
    )
    parser.add_argument("--output", type=Path)
    parser.add_argument("--setup-version", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        root = args.root.resolve()
        catalog = args.catalog.resolve()
        if args.output is None:
            files, summary = build_blueprint_package(root, catalog, args.setup_version)
            result = {
                "result": "ok",
                **summary,
                "packageFiles": len(files),
            }
        else:
            summary = generate_output(
                root,
                catalog,
                args.output.resolve(),
                args.setup_version,
            )
            result = {"result": "ok", **summary}
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"ERRO: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
