#!/usr/bin/env python3
"""Gate da fronteira SHC e inventario dos modulos externos verificados."""

from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import os
import re
import stat
import sys
import tempfile
from pathlib import Path, PurePosixPath


SHC_INPUT_RE = re.compile(r"\bshc\b[^\n]*?\s-f\s+[\"']?([^\s\"']+\.sh)")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
ANCHOR_RE = re.compile(r'^EXPECTED_CONTROL_RELEASE_SHA256="[0-9a-f]{64}"$', re.MULTILINE)


class BoundaryError(RuntimeError):
    pass


def load_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise BoundaryError(f"JSON invalido em {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise BoundaryError(f"Objeto JSON esperado em {path}")
    return value


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def atomic_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary_name = tempfile.mkstemp(prefix=f"{path.name}.tmp.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as temporary:
            json.dump(value, temporary, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
            temporary.write("\n")
            temporary.flush()
            os.fsync(temporary.fileno())
        os.chmod(temporary_name, 0o644)
        os.replace(temporary_name, path)
    finally:
        if os.path.exists(temporary_name):
            os.unlink(temporary_name)


def validate_policy(policy: dict) -> None:
    if policy.get("schemaVersion") != 1 or policy.get("policyVersion") != "1.0.0":
        raise BoundaryError("schema ou versao da politica SHC nao suportada")
    if policy.get("maturity") != "beta":
        raise BoundaryError("a nova fronteira SHC deve permanecer BETA")
    if policy.get("defaultForNewModules") != "external-verified":
        raise BoundaryError("novos modulos devem ser externos e verificados por padrao")
    if policy.get("trustAnchor") != "shc-embedded-release-sha256":
        raise BoundaryError("ancora de confianca SHC ausente")
    for field in (
        "protectedEntrypoints",
        "protectedRuntimeCore",
        "legacyApplicationInstallers",
        "externalScopes",
        "forbiddenShcPatterns",
    ):
        values = policy.get(field)
        if not isinstance(values, list) or not values or len(values) != len(set(values)):
            raise BoundaryError(f"lista ausente, vazia ou duplicada: {field}")


def audit_shc(source_root: Path, policy_path: Path) -> dict:
    policy = load_json(policy_path)
    validate_policy(policy)
    registry = load_json(source_root / "setupmno-knowledge/registry/setups.json")
    canonical = {item.get("script") for item in registry.get("setups", []) if item.get("script")}
    core = set(policy["protectedRuntimeCore"])
    legacy = set(policy["legacyApplicationInstallers"])
    allowed = canonical | core | legacy
    forbidden = policy["forbiddenShcPatterns"]
    starts = {
        "amd64": source_root / "x86/start_full.sh",
        "arm64": source_root / "arm/start_arm_full.sh",
    }
    observed: dict[str, set[str]] = {}
    for architecture, start in starts.items():
        text = start.read_text(encoding="utf-8")
        names = {Path(match).name for match in SHC_INPUT_RE.findall(text)}
        if not names:
            raise BoundaryError(f"nenhuma entrada SHC encontrada em {start}")
        denied = sorted(name for name in names if any(fnmatch.fnmatch(name, rule) for rule in forbidden))
        unknown = sorted(names - allowed)
        if denied:
            raise BoundaryError(f"modulos externos tentaram entrar no SHC ({architecture}): {', '.join(denied)}")
        if unknown:
            raise BoundaryError(f"entradas SHC sem classificacao ({architecture}): {', '.join(unknown)}")
        expected = policy["expectedCurrentShcInputs"]
        if len(names) != expected:
            raise BoundaryError(f"quantidade SHC divergente em {architecture}: {len(names)} != {expected}")
        observed[architecture] = names
    if observed["amd64"] != observed["arm64"]:
        raise BoundaryError("fronteira SHC diverge entre AMD64 e ARM64")
    if not canonical <= observed["amd64"]:
        missing = sorted(canonical - observed["amd64"])
        raise BoundaryError(f"instaladores canonicos fora do SHC: {', '.join(missing)}")
    return {
        "canonicalApplicationInstallers": len(canonical),
        "legacyApplicationInstallers": len(legacy),
        "protectedRuntimeCore": len(core),
        "shcInputsPerArchitecture": len(observed["amd64"]),
    }


def safe_relative(path: str) -> bool:
    pure = PurePosixPath(path)
    return bool(path) and not pure.is_absolute() and ".." not in pure.parts and path == pure.as_posix()


def artifact_scope(path: str) -> str:
    if path == "control-source.tar.gz":
        return "control-runtime"
    if path == "catalog.json":
        return "schemas"
    prefix = path.split("/", 1)[0]
    return {
        "homologation-package": "homologation",
        "knowledge-package": "knowledge",
        "sre-engine": "sre-engine",
        "supply-chain": "supply-chain",
    }.get(prefix, "control-runtime")


def package_files(package: Path) -> list[Path]:
    excluded = {"release.json", "protection-boundary.json"}
    files: list[Path] = []
    for path in sorted(package.rglob("*")):
        relative = path.relative_to(package).as_posix()
        if path.is_symlink():
            raise BoundaryError(f"link simbolico proibido no pacote: {relative}")
        if path.is_file() and relative not in excluded:
            files.append(path)
    return files


def build_boundary(package: Path, policy_path: Path, setup_version: str, architecture: str) -> dict:
    policy = load_json(policy_path)
    validate_policy(policy)
    if architecture not in {"amd64", "arm64"}:
        raise BoundaryError("arquitetura invalida")
    artifacts = []
    for path in package_files(package):
        relative = path.relative_to(package).as_posix()
        artifacts.append(
            {
                "bytes": path.stat().st_size,
                "mode": "verified-external",
                "path": relative,
                "scope": artifact_scope(relative),
                "sha256": sha256(path),
            }
        )
    if not artifacts:
        raise BoundaryError("pacote externo vazio")
    used_scopes = {item["scope"] for item in artifacts}
    if not used_scopes <= set(policy["externalScopes"]):
        raise BoundaryError("escopo externo nao permitido pela politica")
    return {
        "architecture": architecture,
        "artifactCount": len(artifacts),
        "artifacts": artifacts,
        "boundaryVersion": policy["policyVersion"],
        "defaultForNewModules": policy["defaultForNewModules"],
        "maturity": policy["maturity"],
        "schemaVersion": 1,
        "setupVersion": setup_version,
        "trustAnchor": policy["trustAnchor"],
    }


def validate_boundary(package: Path, policy_path: Path, setup_version: str, architecture: str) -> dict:
    expected = build_boundary(package, policy_path, setup_version, architecture)
    actual = load_json(package / "protection-boundary.json")
    if actual != expected:
        raise BoundaryError("inventario da fronteira nao corresponde exatamente aos modulos externos")
    return actual


def bind_anchor(start_script: Path, release: Path) -> str:
    release_sha = sha256(release)
    text = start_script.read_text(encoding="utf-8")
    replacement = f'EXPECTED_CONTROL_RELEASE_SHA256="{release_sha}"'
    updated, count = ANCHOR_RE.subn(replacement, text)
    if count != 1:
        raise BoundaryError(f"ancora SHC ausente ou duplicada em {start_script}")
    if updated != text:
        mode = stat.S_IMODE(start_script.stat().st_mode)
        fd, temporary_name = tempfile.mkstemp(prefix=f"{start_script.name}.tmp.", dir=start_script.parent)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as temporary:
                temporary.write(updated)
                temporary.flush()
                os.fsync(temporary.fileno())
            os.chmod(temporary_name, mode)
            os.replace(temporary_name, start_script)
        finally:
            if os.path.exists(temporary_name):
                os.unlink(temporary_name)
    return release_sha


def assert_anchor(start_script: Path, release: Path) -> None:
    match = ANCHOR_RE.search(start_script.read_text(encoding="utf-8"))
    if not match:
        raise BoundaryError(f"ancora SHC invalida em {start_script}")
    anchored = match.group(0).split('"', 2)[1]
    if not SHA256_RE.fullmatch(anchored) or anchored != sha256(release):
        raise BoundaryError(f"release sem vinculo com a ancora SHC em {start_script}")


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser()
    sub = result.add_subparsers(dest="command", required=True)
    audit = sub.add_parser("audit")
    audit.add_argument("--source-root", type=Path, required=True)
    audit.add_argument("--policy", type=Path, required=True)
    for name in ("generate", "validate"):
        command = sub.add_parser(name)
        command.add_argument("--package", type=Path, required=True)
        command.add_argument("--policy", type=Path, required=True)
        command.add_argument("--setup-version", required=True)
        command.add_argument("--architecture", choices=("amd64", "arm64"), required=True)
    bind = sub.add_parser("bind")
    bind.add_argument("--start-script", type=Path, required=True)
    bind.add_argument("--release", type=Path, required=True)
    check = sub.add_parser("assert-anchor")
    check.add_argument("--start-script", type=Path, required=True)
    check.add_argument("--release", type=Path, required=True)
    return result


def main() -> int:
    args = parser().parse_args()
    try:
        if args.command == "audit":
            print(json.dumps(audit_shc(args.source_root, args.policy), sort_keys=True))
        elif args.command == "generate":
            boundary = build_boundary(args.package, args.policy, args.setup_version, args.architecture)
            atomic_json(args.package / "protection-boundary.json", boundary)
            print(json.dumps({"artifactCount": boundary["artifactCount"]}, sort_keys=True))
        elif args.command == "validate":
            boundary = validate_boundary(args.package, args.policy, args.setup_version, args.architecture)
            print(json.dumps({"artifactCount": boundary["artifactCount"]}, sort_keys=True))
        elif args.command == "bind":
            print(bind_anchor(args.start_script, args.release))
        else:
            assert_anchor(args.start_script, args.release)
    except BoundaryError as exc:
        print(f"ERRO: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
