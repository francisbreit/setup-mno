#!/usr/bin/python3
"""Prepara metadados editoriais para certificação após revisão humana completa."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

import homologation_runner as runner
from import_homologation_review import load_review_pack
from lint_knowledge import parse_document


def canonical_document(metadata: dict[str, Any], body: str) -> bytes:
    return (
        "---\n"
        + json.dumps(metadata, ensure_ascii=False, indent=2)
        + "\n---\n"
        + body.rstrip("\n")
        + "\n"
    ).encode("utf-8")


def prepare(packs: list[Path], root: Path, package_dir: Path) -> dict[str, Any]:
    _, registry = runner.validate_package(package_dir)
    entries = runner.registry_by_id(registry)
    candidates: list[dict[str, Any]] = []
    setup_id = ""
    setup_version = ""
    for pack in packs:
        candidate, decision, _, _ = load_review_pack(pack.resolve())
        if decision["decision"] != "approved":
            raise ValueError("somente pacotes aprovados podem preparar a documentação")
        if not setup_id:
            setup_id, setup_version = candidate["setupId"], candidate["setupVersion"]
        if candidate["setupId"] != setup_id or candidate["setupVersion"] != setup_version:
            raise ValueError("os pacotes pertencem a setups ou versões diferentes")
        candidates.append(candidate)
    entry = entries.get(setup_id)
    if entry is None:
        raise ValueError("setup ausente do registro do Runner")
    architectures = {item["architecture"] for item in candidates}
    if architectures != set(entry["architectures"]):
        raise ValueError("a preparação editorial exige todas as arquiteturas declaradas")
    document_path = root / "setups" / setup_id / "overview.md"
    document = parse_document(document_path)
    metadata = json.loads(json.dumps(document.metadata))
    if metadata.get("setupId") != setup_id or metadata.get("status") not in {"reviewed", "homologated"}:
        raise ValueError("o documento precisa estar revisado antes da homologação")
    ports = metadata.get("homologation", {}).get("verifiedPorts")
    if not isinstance(ports, list) or not ports or not all(isinstance(port, int) and 1 <= port <= 65535 for port in ports):
        raise ValueError("o documento não possui portas verificadas; solicite revisão técnica")
    latest = max(item["createdAt"] for item in candidates)[:10]
    dt.date.fromisoformat(latest)
    images = sorted({image for item in candidates for image in item["images"]})
    metadata["status"] = "homologated"
    metadata["updatedAt"] = latest
    metadata["homologation"] = {
        "verifiedAt": latest,
        "verifiedPorts": ports,
        "verifiedImages": images,
    }
    data = canonical_document(metadata, document.body)
    token = hashlib.sha256(data).hexdigest()[:12].upper()
    return {
        "setupId": setup_id,
        "setupVersion": setup_version,
        "architectures": sorted(architectures),
        "documentPath": str(document_path.relative_to(root)),
        "verifiedAt": latest,
        "verifiedPorts": ports,
        "verifiedImages": images,
        "confirmationToken": token,
        "data": data,
        "path": document_path,
    }


def public(prepared: dict[str, Any], applied: bool) -> dict[str, Any]:
    return {key: value for key, value in prepared.items() if key not in {"data", "path"}} | {
        "mode": "apply" if applied else "dry-run",
        "documentPrepared": applied,
        "officialSeal": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack", action="append", type=Path, required=True)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--package-dir", type=Path, required=True)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--confirm", default="")
    args = parser.parse_args()
    root = args.root.resolve()
    prepared = prepare(args.pack, root, args.package_dir.resolve())
    if not args.apply:
        print(json.dumps(public(prepared, False), ensure_ascii=False, sort_keys=True))
        return 0
    if args.confirm != prepared["confirmationToken"]:
        raise ValueError("confirmação editorial inválida")
    runner.atomic_write(prepared["path"], prepared["data"], 0o644)
    print(json.dumps(public(prepared, True), ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"ERRO: {exc}", file=sys.stderr)
        raise SystemExit(2)
