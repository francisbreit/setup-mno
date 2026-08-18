#!/usr/bin/python3
"""Gera o pacote runtime verificável do Homologation Runner."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import tempfile
from pathlib import Path
from typing import Any

from homologation_runner import (
    CANDIDATE_SCHEMA_VERSION,
    RUNNER_RELEASE_DATE,
    RUNNER_VERSION,
)


SEMVER_RE = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")


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


def generate(root: Path, output: Path, setup_version: str) -> dict[str, Any]:
    if not SEMVER_RE.fullmatch(setup_version):
        raise ValueError("versão do Setup MNO inválida")
    tools = root / "tools"
    runner_data = read_regular(tools / "homologation_runner.py")
    wizard_data = read_regular(tools / "homologation_wizard.sh")
    schema_data = read_regular(root / "schema" / "homologation-candidate.schema.json")
    registry_data = canonical_json(build_registry(root, setup_version))
    files = {
        "homologation_runner.py": runner_data,
        "homologation_wizard.sh": wizard_data,
        "homologation-candidate.schema.json": schema_data,
        "runner-registry.json": registry_data,
    }
    manifest = {
        "schemaVersion": 1,
        "runnerVersion": RUNNER_VERSION,
        "candidateSchemaVersion": CANDIDATE_SCHEMA_VERSION,
        "setupVersion": setup_version,
        "generatedAt": f"{RUNNER_RELEASE_DATE}T00:00:00Z",
        "registryEntries": len(json.loads(registry_data)["entries"]),
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
