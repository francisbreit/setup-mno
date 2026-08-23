#!/usr/bin/env python3
"""Gera e valida evidencias deterministicas de supply chain do Setup MNO."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import sys
from pathlib import Path
from typing import Any


GENERATOR_VERSION = "1.0.0"
SCHEMA_VERSION = 1
CYCLONEDX_SPEC_VERSION = "1.6"
STATEMENT_TYPE = "https://in-toto.io/Statement/v1"
PREDICATE_TYPE = "https://slsa.dev/provenance/v1"
BUILD_TYPE = "https://manualnegocioonline.com.br/setup-mno/build-types/runtime-supply-chain/v1"
BUILDER_ID = "https://manualnegocioonline.com.br/setup-mno/builders/supply-chain/v1"
SIGNATURE_STATUS = "unsigned-sha256-bound"
EXPECTED_FILES = {
    "attestation.intoto.json",
    "image-inventory.json",
    "manifest.json",
    "sbom.cdx.json",
}
HEX64_RE = re.compile(r"^[0-9a-f]{64}$")
SEMVER_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
IMAGE_ASSIGNMENT_RE = re.compile(
    r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*IMAGE[A-Za-z0-9_]*)=(.*)$"
)
YAML_IMAGE_RE = re.compile(r"^\s*image:\s*(.+?)\s*$")
FALLBACK_RE = re.compile(r"\$\{[A-Za-z_][A-Za-z0-9_]*:-([^}]+)\}")


class SupplyChainError(RuntimeError):
    pass


def canonical_json(data: Any) -> bytes:
    return (json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def regular_file(path: Path, *, maximum: int = 16 << 20) -> bytes:
    info = path.lstat()
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise SupplyChainError(f"arquivo não regular: {path}")
    if info.st_size < 2 or info.st_size > maximum:
        raise SupplyChainError(f"tamanho inválido: {path}")
    return path.read_bytes()


def file_record(path: Path, display_path: str) -> dict[str, Any]:
    data = regular_file(path)
    return {"path": display_path, "sha256": sha256_bytes(data), "size": len(data)}


def parse_json_file(path: Path, *, maximum: int = 16 << 20) -> Any:
    try:
        return json.loads(regular_file(path, maximum=maximum))
    except json.JSONDecodeError as exc:
        raise SupplyChainError(f"JSON inválido em {path}: {exc}") from exc


def clean_shell_value(raw: str) -> str:
    value = raw.strip()
    if " #" in value:
        value = value.split(" #", 1)[0].rstrip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
        value = value[1:-1]
    return value.strip()


def plausible_image_reference(value: str) -> bool:
    if not value or any(char.isspace() for char in value):
        return False
    if value.startswith(("http://", "https://", "/")):
        return False
    if value in {"true", "false", "none", "null"}:
        return False
    return "/" in value or ":" in value or value.replace("-", "").replace("_", "").isalnum()


def classify_reference(reference: str) -> str:
    if re.search(r"@sha256:[0-9a-fA-F]{64}$", reference):
        return "digest"
    leaf = reference.rsplit("/", 1)[-1]
    if ":" not in leaf:
        return "implicit-latest"
    tag = leaf.rsplit(":", 1)[-1].lower()
    if tag in {"latest", "stable", "main", "master", "edge", "nightly", "dev", "develop"}:
        return "high-risk-mutable-tag"
    return "mutable-tag"


def inventory_images(source_root: Path, architecture: str) -> dict[str, Any]:
    arch_dir = "x86" if architecture == "amd64" else "arm"
    script_root = source_root / arch_dir / "SetupLowCodeMno"
    if not script_root.is_dir() or script_root.is_symlink():
        raise SupplyChainError(f"diretório de scripts inválido: {script_root}")

    references: dict[str, dict[str, Any]] = {}
    unresolved: list[dict[str, Any]] = []
    scripts: list[dict[str, Any]] = []
    for script_path in sorted(script_root.glob("*.sh")):
        if script_path.name == "setupmno_control.sh":
            continue
        data = regular_file(script_path, maximum=2 << 20)
        relative = script_path.relative_to(source_root).as_posix()
        scripts.append({"path": relative, "sha256": sha256_bytes(data), "size": len(data)})
        text = data.decode("utf-8", errors="strict")
        for line_number, line in enumerate(text.splitlines(), 1):
            match = IMAGE_ASSIGNMENT_RE.match(line) or YAML_IMAGE_RE.match(line)
            if not match:
                continue
            raw = match.group(match.lastindex or 1)
            value = clean_shell_value(raw)
            fallback = FALLBACK_RE.fullmatch(value)
            if fallback:
                value = clean_shell_value(fallback.group(1))
            if any(marker in value for marker in ("$", "`", "$(")):
                unresolved.append({"expression": value, "line": line_number, "sourcePath": relative})
                continue
            if not plausible_image_reference(value):
                continue
            entry = references.setdefault(
                value,
                {"reference": value, "referenceType": classify_reference(value), "sources": []},
            )
            entry["sources"].append({"line": line_number, "path": relative})

    if not scripts:
        raise SupplyChainError(f"nenhum script encontrado para {architecture}")
    ordered_refs = []
    for reference in sorted(references):
        entry = references[reference]
        entry["sources"] = sorted(entry["sources"], key=lambda item: (item["path"], item["line"]))
        ordered_refs.append(entry)
    unresolved.sort(key=lambda item: (item["sourcePath"], item["line"], item["expression"]))
    counts = {
        "digestPinned": sum(item["referenceType"] == "digest" for item in ordered_refs),
        "highRiskMutableTags": sum(item["referenceType"] == "high-risk-mutable-tag" for item in ordered_refs),
        "implicitLatest": sum(item["referenceType"] == "implicit-latest" for item in ordered_refs),
        "mutableTags": sum(item["referenceType"] == "mutable-tag" for item in ordered_refs),
        "references": len(ordered_refs),
        "scripts": len(scripts),
        "unresolvedExpressions": len(unresolved),
    }
    return {
        "schemaVersion": SCHEMA_VERSION,
        "generatorVersion": GENERATOR_VERSION,
        "architecture": architecture,
        "scope": "installer-shell-image-references",
        "completeness": {
            "patternsScanned": ["shell-image-assignment", "compose-yaml-image"],
            "resolvedContainerDigests": False,
            "status": "partial",
        },
        "counts": counts,
        "references": ordered_refs,
        "scripts": scripts,
        "unresolved": unresolved,
    }


def component_ref(kind: str, value: str) -> str:
    return f"urn:setupmno:{kind}:{hashlib.sha256(value.encode()).hexdigest()}"


def build_sbom(setup_version: str, architecture: str, artifacts: list[dict[str, Any]], inventory: dict[str, Any]) -> dict[str, Any]:
    root_ref = f"pkg:generic/setup-mno@{setup_version}?arch={architecture}"
    components: list[dict[str, Any]] = []
    dependencies: list[str] = []
    for artifact in artifacts:
        bom_ref = component_ref("artifact", artifact["path"])
        components.append({
            "type": "file",
            "bom-ref": bom_ref,
            "name": artifact["path"],
            "version": setup_version,
            "hashes": [{"alg": "SHA-256", "content": artifact["sha256"]}],
            "properties": [
                {"name": "setupmno:architecture", "value": architecture},
                {"name": "setupmno:size", "value": str(artifact["size"])},
            ],
        })
        dependencies.append(bom_ref)
    for image in inventory["references"]:
        bom_ref = component_ref("container", image["reference"])
        components.append({
            "type": "container",
            "bom-ref": bom_ref,
            "name": image["reference"],
            "version": image["reference"],
            "properties": [
                {"name": "setupmno:architecture", "value": architecture},
                {"name": "setupmno:referenceType", "value": image["referenceType"]},
            ],
        })
        dependencies.append(bom_ref)
    return {
        "bomFormat": "CycloneDX",
        "specVersion": CYCLONEDX_SPEC_VERSION,
        "version": 1,
        "metadata": {
            "component": {
                "type": "application",
                "bom-ref": root_ref,
                "name": "Setup MNO",
                "version": setup_version,
                "properties": [{"name": "setupmno:architecture", "value": architecture}],
            },
            "properties": [
                {"name": "setupmno:generatorVersion", "value": GENERATOR_VERSION},
                {"name": "setupmno:inventoryCompleteness", "value": "partial"},
            ],
        },
        "components": components,
        "dependencies": [{"ref": root_ref, "dependsOn": sorted(dependencies)}],
        "compositions": [{"aggregate": "incomplete", "assemblies": [root_ref]}],
    }


def build_attestation(setup_version: str, architecture: str, artifacts: list[dict[str, Any]], sbom: dict[str, Any], inventory: dict[str, Any]) -> dict[str, Any]:
    sbom_bytes = canonical_json(sbom)
    inventory_bytes = canonical_json(inventory)
    return {
        "_type": STATEMENT_TYPE,
        "subject": [
            {"name": "supply-chain/sbom.cdx.json", "digest": {"sha256": sha256_bytes(sbom_bytes)}},
            {"name": "supply-chain/image-inventory.json", "digest": {"sha256": sha256_bytes(inventory_bytes)}},
        ],
        "predicateType": PREDICATE_TYPE,
        "predicate": {
            "buildDefinition": {
                "buildType": BUILD_TYPE,
                "externalParameters": {"architecture": architecture, "setupVersion": setup_version},
                "internalParameters": {
                    "generatorVersion": GENERATOR_VERSION,
                    "inventoryCompleteness": "partial",
                    "signatureStatus": SIGNATURE_STATUS,
                },
                "resolvedDependencies": [
                    {"uri": f"file:{item['path']}", "digest": {"sha256": item["sha256"]}}
                    for item in artifacts
                ],
            },
            "runDetails": {"builder": {"id": BUILDER_ID}, "byproducts": []},
        },
    }


def generate(args: argparse.Namespace) -> None:
    source_root = args.source_root.resolve()
    target = args.target.resolve()
    if args.architecture not in {"amd64", "arm64"}:
        raise SupplyChainError("arquitetura inválida")
    if not SEMVER_RE.fullmatch(args.setup_version):
        raise SupplyChainError("versão inválida")
    target.mkdir(parents=True, exist_ok=True)
    if target.is_symlink():
        raise SupplyChainError("destino não pode ser symlink")
    for child in target.iterdir():
        if child.name not in EXPECTED_FILES or child.is_dir() or child.is_symlink():
            raise SupplyChainError(f"conteúdo inesperado no destino: {child.name}")
        child.unlink()

    artifacts = [file_record(Path(path), name) for name, path in sorted(args.artifact)]
    inventory = inventory_images(source_root, args.architecture)
    inventory["setupVersion"] = args.setup_version
    sbom = build_sbom(args.setup_version, args.architecture, artifacts, inventory)
    attestation = build_attestation(args.setup_version, args.architecture, artifacts, sbom, inventory)
    payloads = {
        "image-inventory.json": canonical_json(inventory),
        "sbom.cdx.json": canonical_json(sbom),
        "attestation.intoto.json": canonical_json(attestation),
    }
    for name, data in payloads.items():
        (target / name).write_bytes(data)
        os.chmod(target / name, 0o644)

    counts = inventory["counts"]
    manifest = {
        "schemaVersion": SCHEMA_VERSION,
        "generatorVersion": GENERATOR_VERSION,
        "setupVersion": args.setup_version,
        "architecture": args.architecture,
        "sbom": {"format": "CycloneDX", "specVersion": CYCLONEDX_SPEC_VERSION, "composition": "incomplete"},
        "attestation": {"statementType": STATEMENT_TYPE, "predicateType": PREDICATE_TYPE, "signatureStatus": SIGNATURE_STATUS},
        "inventory": {
            "completeness": "partial",
            "digestPinnedImages": counts["digestPinned"],
            "highRiskMutableTagImages": counts["highRiskMutableTags"],
            "implicitLatestImages": counts["implicitLatest"],
            "imageReferences": counts["references"],
            "mutableTagImages": counts["mutableTags"],
            "unresolvedExpressions": counts["unresolvedExpressions"],
        },
        "files": [
            {"path": name, "sha256": sha256_bytes(data), "size": len(data)}
            for name, data in sorted(payloads.items())
        ],
    }
    (target / "manifest.json").write_bytes(canonical_json(manifest))
    os.chmod(target / "manifest.json", 0o644)
    validate_directory(target, args.setup_version, args.architecture)


def require_hash(value: Any, label: str) -> None:
    if not isinstance(value, str) or not HEX64_RE.fullmatch(value):
        raise SupplyChainError(f"SHA-256 inválido: {label}")


def validate_directory(directory: Path, setup_version: str | None = None, architecture: str | None = None) -> dict[str, Any]:
    info = directory.lstat()
    if not stat.S_ISDIR(info.st_mode) or stat.S_ISLNK(info.st_mode):
        raise SupplyChainError("diretório supply-chain inválido")
    entries = {path.name for path in directory.iterdir()}
    if entries != EXPECTED_FILES:
        raise SupplyChainError(f"inventário de arquivos divergente: {sorted(entries)}")
    manifest = parse_json_file(directory / "manifest.json", maximum=64 << 10)
    if set(manifest) != {"architecture", "attestation", "files", "generatorVersion", "inventory", "sbom", "schemaVersion", "setupVersion"}:
        raise SupplyChainError("campos do manifesto supply-chain divergentes")
    if manifest["schemaVersion"] != SCHEMA_VERSION or manifest["generatorVersion"] != GENERATOR_VERSION:
        raise SupplyChainError("schema ou gerador supply-chain incompatível")
    if not SEMVER_RE.fullmatch(str(manifest["setupVersion"])) or manifest["architecture"] not in {"amd64", "arm64"}:
        raise SupplyChainError("identidade supply-chain inválida")
    if setup_version is not None and manifest["setupVersion"] != setup_version:
        raise SupplyChainError("versão supply-chain divergente")
    if architecture is not None and manifest["architecture"] != architecture:
        raise SupplyChainError("arquitetura supply-chain divergente")
    if manifest["sbom"] != {"format": "CycloneDX", "specVersion": CYCLONEDX_SPEC_VERSION, "composition": "incomplete"}:
        raise SupplyChainError("metadados SBOM inválidos")
    if manifest["attestation"] != {"statementType": STATEMENT_TYPE, "predicateType": PREDICATE_TYPE, "signatureStatus": SIGNATURE_STATUS}:
        raise SupplyChainError("metadados de atestação inválidos")
    records = manifest["files"]
    if not isinstance(records, list) or {item.get("path") for item in records} != EXPECTED_FILES - {"manifest.json"}:
        raise SupplyChainError("arquivos declarados no manifesto divergentes")
    for item in records:
        if set(item) != {"path", "sha256", "size"}:
            raise SupplyChainError("registro de arquivo inválido")
        require_hash(item["sha256"], item["path"])
        data = regular_file(directory / item["path"], maximum=8 << 20)
        if len(data) != item["size"] or sha256_bytes(data) != item["sha256"]:
            raise SupplyChainError(f"integridade divergente: {item['path']}")

    inventory = parse_json_file(directory / "image-inventory.json", maximum=8 << 20)
    if inventory.get("schemaVersion") != SCHEMA_VERSION or inventory.get("setupVersion") != manifest["setupVersion"] or inventory.get("architecture") != manifest["architecture"]:
        raise SupplyChainError("inventário de imagens incompatível")
    counts = inventory.get("counts", {})
    expected_counts = manifest["inventory"]
    count_map = {
        "digestPinnedImages": "digestPinned",
        "highRiskMutableTagImages": "highRiskMutableTags",
        "implicitLatestImages": "implicitLatest",
        "imageReferences": "references",
        "mutableTagImages": "mutableTags",
        "unresolvedExpressions": "unresolvedExpressions",
    }
    if expected_counts.get("completeness") != "partial" or any(expected_counts.get(target) != counts.get(source) for target, source in count_map.items()):
        raise SupplyChainError("contadores do inventário divergentes")
    if counts.get("references", 0) < 1 or counts.get("scripts", 0) < 1:
        raise SupplyChainError("inventário de imagens vazio")

    sbom = parse_json_file(directory / "sbom.cdx.json", maximum=8 << 20)
    if sbom.get("bomFormat") != "CycloneDX" or sbom.get("specVersion") != CYCLONEDX_SPEC_VERSION or sbom.get("version") != 1:
        raise SupplyChainError("SBOM CycloneDX incompatível")
    if not isinstance(sbom.get("components"), list) or not sbom["components"]:
        raise SupplyChainError("SBOM sem componentes")
    if sbom.get("compositions") != [{"aggregate": "incomplete", "assemblies": [f"pkg:generic/setup-mno@{manifest['setupVersion']}?arch={manifest['architecture']}"]}]:
        raise SupplyChainError("completude do SBOM divergente")

    attestation = parse_json_file(directory / "attestation.intoto.json", maximum=2 << 20)
    if attestation.get("_type") != STATEMENT_TYPE or attestation.get("predicateType") != PREDICATE_TYPE:
        raise SupplyChainError("atestação in-toto incompatível")
    subjects = {item.get("name"): item.get("digest", {}).get("sha256") for item in attestation.get("subject", [])}
    for name in ("sbom.cdx.json", "image-inventory.json"):
        expected = next(item["sha256"] for item in records if item["path"] == name)
        if subjects.get(f"supply-chain/{name}") != expected:
            raise SupplyChainError(f"subject da atestação divergente: {name}")
    parameters = attestation.get("predicate", {}).get("buildDefinition", {}).get("externalParameters", {})
    internal = attestation.get("predicate", {}).get("buildDefinition", {}).get("internalParameters", {})
    if parameters != {"architecture": manifest["architecture"], "setupVersion": manifest["setupVersion"]} or internal.get("signatureStatus") != SIGNATURE_STATUS:
        raise SupplyChainError("predicado da atestação divergente")
    return manifest


def parse_artifact(value: str) -> tuple[str, str]:
    if "=" not in value:
        raise argparse.ArgumentTypeError("use NOME=CAMINHO")
    name, path = value.split("=", 1)
    if not name or name.startswith("/") or ".." in Path(name).parts or not path:
        raise argparse.ArgumentTypeError("artefato inválido")
    return name, path


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    generate_parser = subparsers.add_parser("generate")
    generate_parser.add_argument("--source-root", type=Path, required=True)
    generate_parser.add_argument("--target", type=Path, required=True)
    generate_parser.add_argument("--architecture", required=True)
    generate_parser.add_argument("--setup-version", required=True)
    generate_parser.add_argument("--artifact", action="append", type=parse_artifact, default=[], required=True)
    validate_parser = subparsers.add_parser("validate")
    validate_parser.add_argument("--directory", type=Path, required=True)
    validate_parser.add_argument("--architecture")
    validate_parser.add_argument("--setup-version")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        if args.command == "generate":
            generate(args)
        else:
            validate_directory(args.directory.resolve(), args.setup_version, args.architecture)
    except (OSError, SupplyChainError) as exc:
        print(f"ERRO: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
