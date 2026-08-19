#!/usr/bin/python3
"""Gera o pacote runtime verificável do Homologation Runner."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import json
import os
import re
import shutil
import tarfile
import tempfile
from pathlib import Path
from typing import Any

from homologation_runner import (
    CANDIDATE_SCHEMA_VERSION,
    RUNNER_RELEASE_DATE,
    RUNNER_VERSION,
)


SEMVER_RE = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
MAX_MAINTAINER_WORKSPACE_BYTES = 8 << 20


def canonical_json(value: Any) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        + "\n"
    ).encode("utf-8")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_regular(path: Path, max_bytes: int = 256 << 10) -> bytes:
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"fonte ausente ou insegura: {path}")
    if path.stat().st_size <= 0 or path.stat().st_size > max_bytes:
        raise ValueError(f"fonte fora do limite: {path}")
    return path.read_bytes()


def load_json(path: Path) -> Any:
    return json.loads(read_regular(path))


def build_registry(root: Path, setup_version: str) -> dict[str, Any]:
    source = load_json(root / "registry" / "setups.json")
    if source.get("setupVersion") != setup_version:
        raise ValueError("registro de setups pertence a outra versão")
    entries: list[dict[str, Any]] = []
    for item in source.get("setups", []):
        architectures = item["architectures"]
        artifacts: dict[str, dict[str, str]] = {}
        for architecture in architectures:
            prefix = "x86" if architecture == "amd64" else "arm"
            relative = f"{prefix}/SetupLowCodeMno/{item['script']}"
            source_script = root.parent / relative
            script_data = read_regular(source_script)
            artifacts[architecture] = {
                "path": relative,
                "sha256": sha256_bytes(script_data),
            }
        entries.append({
            "setupId": item["setupId"],
            "catalogName": item["catalogName"],
            "script": item["script"],
            "architectures": architectures,
            "artifacts": artifacts,
        })
    entries.sort(key=lambda item: item["setupId"])
    if not entries:
        raise ValueError("registro do runner ficou vazio")
    return {
        "schemaVersion": 1,
        "runnerVersion": RUNNER_VERSION,
        "setupVersion": setup_version,
        "entries": entries,
    }


def build_maintainer_workspace(root: Path) -> bytes:
    """Empacota a base editável necessária à certificação, sem fontes dos instaladores."""
    selected = (
        "VERSION", "quality-baseline.json", "blueprints", "evals", "evidence",
        "glossary", "infra", "policies", "registry", "schema", "setups",
        "templates", "troubleshooting", "tools",
    )
    files: dict[str, bytes] = {}
    for name in selected:
        source = root / name
        candidates = [source] if source.is_file() else sorted(source.rglob("*"))
        for candidate in candidates:
            if candidate.is_symlink():
                raise ValueError(f"workspace contém symlink: {candidate}")
            if not candidate.is_file():
                continue
            relative = candidate.relative_to(root)
            if "__pycache__" in relative.parts or candidate.suffix in {".pyc", ".pyo"}:
                continue
            if candidate.name.startswith("test_") or candidate.name.endswith("_test.sh"):
                continue
            data = candidate.read_bytes()
            if len(data) > 2 << 20:
                raise ValueError(f"arquivo do workspace excede 2 MiB: {relative}")
            files[f"setupmno-knowledge/{relative.as_posix()}"] = data
    catalog = root.parent / "setupmno-control" / "catalog.json"
    files["setupmno-control/catalog.json"] = read_regular(catalog, 2 << 20)
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w", format=tarfile.PAX_FORMAT) as archive:
        for name in sorted(files):
            data = files[name]
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = 0o755 if name.endswith(".sh") or "/tools/" in name and name.endswith(".py") else 0o644
            info.mtime = 0
            info.uid = 0
            info.gid = 0
            info.uname = ""
            info.gname = ""
            archive.addfile(info, io.BytesIO(data))
    compressed = io.BytesIO()
    with gzip.GzipFile(filename="", mode="wb", fileobj=compressed, mtime=0, compresslevel=9) as stream:
        stream.write(buffer.getvalue())
    result = compressed.getvalue()
    if not result or len(result) > MAX_MAINTAINER_WORKSPACE_BYTES:
        raise ValueError("workspace do mantenedor fora do limite de 8 MiB")
    return result


def generate(root: Path, output: Path, setup_version: str) -> dict[str, Any]:
    if not SEMVER_RE.fullmatch(setup_version):
        raise ValueError("versão do Setup MNO inválida")
    tools = root / "tools"
    runner_data = read_regular(tools / "homologation_runner.py")
    wizard_data = read_regular(tools / "homologation_wizard.sh")
    schema_data = read_regular(root / "schema" / "homologation-candidate.schema.json")
    decision_schema_data = read_regular(root / "schema" / "homologation-review-decision.schema.json")
    review_pack_schema_data = read_regular(root / "schema" / "homologation-review-pack.schema.json")
    registry_data = canonical_json(build_registry(root, setup_version))
    maintainer_workspace_data = build_maintainer_workspace(root)
    files = {
        "homologation_runner.py": runner_data,
        "homologation_wizard.sh": wizard_data,
        "homologation-candidate.schema.json": schema_data,
        "homologation-review-decision.schema.json": decision_schema_data,
        "homologation-review-pack.schema.json": review_pack_schema_data,
        "runner-registry.json": registry_data,
        "maintainer_console.sh": read_regular(tools / "maintainer_console.sh"),
        "maintainer_workspace.sh": read_regular(tools / "maintainer_workspace.sh"),
        "maintainer_validation_wizard.sh": read_regular(tools / "maintainer_validation_wizard.sh"),
        "certification_wizard.sh": read_regular(tools / "certification_wizard.sh"),
        "maintainer-workspace.tar.gz": maintainer_workspace_data,
    }
    manifest = {
        "schemaVersion": 1,
        "runnerVersion": RUNNER_VERSION,
        "candidateSchemaVersion": CANDIDATE_SCHEMA_VERSION,
        "setupVersion": setup_version,
        "generatedAt": f"{RUNNER_RELEASE_DATE}T00:00:00Z",
        "registryEntries": len(json.loads(registry_data)["entries"]),
        "maintainerWorkspaceBytes": len(maintainer_workspace_data),
        "maintainerWorkspaceSHA256": sha256_bytes(maintainer_workspace_data),
        "remoteCertification": True,
        "files": [
            {"path": name, "sha256": sha256_bytes(data), "size": len(data)}
            for name, data in sorted(files.items())
        ],
    }
    output_parent = output.parent.resolve()
    output_parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=f".{output.name}.", dir=output_parent))
    try:
        for name, data in files.items():
            target = temporary / name
            target.write_bytes(data)
            target.chmod(0o644)
        (temporary / "manifest.json").write_bytes(canonical_json(manifest))
        (temporary / "manifest.json").chmod(0o644)
        if output.exists():
            if output.is_symlink() or not output.is_dir():
                raise ValueError("destino do pacote é inseguro")
            shutil.rmtree(output)
        os.replace(temporary, output)
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--setup-version", required=True)
    args = parser.parse_args()
    manifest = generate(args.root.resolve(), args.output.resolve(), args.setup_version)
    print(json.dumps(manifest, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
