#!/usr/bin/python3
"""Importa um pacote aprovado sem permitir promoção automática ao selo oficial."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path
from typing import Any

import homologation_runner as runner


MAX_PACK_BYTES = 2 << 20
EXPECTED_MEMBERS = [
    "candidate.tar.gz",
    "decision.json",
    "operational-evidence.json",
    "manifest.json",
]


def canonical_json(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode()


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_regular(path: Path, limit: int) -> bytes:
    if path.is_symlink() or not path.is_file() or not 1 < path.stat().st_size <= limit:
        raise ValueError(f"arquivo ausente, inseguro ou fora do limite: {path}")
    return path.read_bytes()


def load_review_pack(path: Path) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any], bytes]:
    pack_data = read_regular(path, MAX_PACK_BYTES)
    try:
        with tarfile.open(fileobj=io.BytesIO(pack_data), mode="r:gz") as archive:
            members = archive.getmembers()
            if [item.name for item in members] != EXPECTED_MEMBERS:
                raise ValueError("inventário do pacote de revisão é inesperado")
            if any(not item.isfile() or item.issym() or item.islnk() for item in members):
                raise ValueError("pacote de revisão contém entrada não regular")
            payloads = {item.name: archive.extractfile(item).read() for item in members}
    except (tarfile.TarError, EOFError) as exc:
        raise ValueError("pacote de revisão inválido") from exc
    manifest = json.loads(payloads["manifest.json"])
    expected_manifest_keys = {
        "schemaVersion", "kind", "candidateId", "createdAt", "files",
        "automaticPromotion", "governanceUpdated", "officialSeal",
    }
    if not isinstance(manifest, dict) or set(manifest) != expected_manifest_keys:
        raise ValueError("manifesto do pacote possui campos inesperados")
    if (
        manifest["schemaVersion"] != 1
        or manifest["kind"] != "setupmno-homologation-review-pack"
        or manifest["automaticPromotion"] is not False
        or manifest["governanceUpdated"] is not False
        or manifest["officialSeal"] is not False
    ):
        raise ValueError("pacote tentou ultrapassar a fronteira de confiança")
    inventory = manifest.get("files")
    expected_payloads = EXPECTED_MEMBERS[:-1]
    if not isinstance(inventory, list) or [item.get("path") for item in inventory] != expected_payloads:
        raise ValueError("inventário autenticado do pacote é inválido")
    for item in inventory:
        if set(item) != {"path", "sha256", "size"}:
            raise ValueError("entrada inválida no inventário autenticado")
        payload = payloads[item["path"]]
        if item["size"] != len(payload) or item["sha256"] != sha256(payload):
            raise ValueError(f"integridade divergente: {item['path']}")
    decision = json.loads(payloads["decision.json"])
    evidence = json.loads(payloads["operational-evidence.json"])
    with tempfile.TemporaryDirectory(prefix="setupmno-review-import-") as directory:
        bundle = Path(directory) / "candidate.tar.gz"
        bundle.write_bytes(payloads["candidate.tar.gz"])
        candidate, _ = runner.read_bundle(bundle)
    if manifest["candidateId"] != candidate["candidateId"]:
        raise ValueError("manifesto e candidato divergem")
    expected_decision_keys = {
        "schemaVersion", "kind", "decisionId", "candidateId", "candidateBundleSHA256",
        "decision", "reasonCode", "reason", "reviewedBy", "reviewedAt", "immutable",
        "governanceUpdated", "officialSeal",
    }
    if not isinstance(decision, dict) or set(decision) != expected_decision_keys:
        raise ValueError("decisão possui campos inesperados")
    if (
        decision["schemaVersion"] != 1
        or decision["kind"] != "setupmno-homologation-review-decision"
        or decision["candidateId"] != candidate["candidateId"]
        or decision["candidateBundleSHA256"] != sha256(payloads["candidate.tar.gz"])
        or decision["decision"] != "approved"
        or decision["reasonCode"] != "operational-evidence-accepted"
        or decision["immutable"] is not True
        or decision["governanceUpdated"] is not False
        or decision["officialSeal"] is not False
    ):
        raise ValueError("somente uma aprovação íntegra pode ser importada")
    if evidence.get("evidenceId") != candidate["candidateId"].removesuffix("-candidate"):
        raise ValueError("evidência não corresponde ao candidato")
    projection = {
        "setupId": candidate["setupId"], "setupVersion": candidate["setupVersion"],
        "architecture": candidate["architecture"], "verifiedAt": candidate["createdAt"],
        "environment": candidate["environment"], "artifact": candidate["artifact"],
        "images": candidate["images"], "checks": candidate["checks"],
    }
    if any(evidence.get(key) != value for key, value in projection.items()):
        raise ValueError("conteúdo da evidência diverge do candidato aprovado")
    if evidence.get("result") != "passed" or evidence.get("sanitized") is not True:
        raise ValueError("evidência aprovada possui resultado inválido")
    review = evidence.get("review", {})
    if review.get("decision") != "approved" or review.get("reviewedBy") != decision["reviewedBy"]:
        raise ValueError("revisor da evidência diverge da decisão")
    runner.reject_sensitive(decision, "decisão importada")
    runner.reject_sensitive(evidence, "evidência importada")
    return candidate, decision, evidence, canonical_json(evidence)


def main() -> int:
    parser = argparse.ArgumentParser(description="Importador canônico de evidência revisada do Setup MNO")
    parser.add_argument("--pack", type=Path, required=True)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--catalog", type=Path, required=True)
    parser.add_argument("--package-dir", type=Path, required=True)
    parser.add_argument("--apply", action="store_true", help="aplicar após o dry-run explícito")
    args = parser.parse_args()
    root = args.root.resolve()
    catalog = args.catalog.resolve()
    package_dir = args.package_dir.resolve()
    candidate, decision, evidence, evidence_data = load_review_pack(args.pack.resolve())
    _, registry = runner.validate_package(package_dir)
    entry = runner.registry_by_id(registry).get(candidate["setupId"])
    if entry is None or candidate["artifact"] != entry["artifacts"].get(candidate["architecture"]):
        raise ValueError("o instalador canônico atual diverge do artefato aprovado")
    source_script = root.parent / candidate["artifact"]["path"]
    if runner.sha256_file(source_script) != candidate["artifact"]["sha256"]:
        raise ValueError("o código vivo do instalador mudou após a homologação")
    governance_path = root / "registry" / "governance.json"
    quality_path = root / "registry" / "quality-report.json"
    governance = json.loads(read_regular(governance_path, 2 << 20))
    blocking_issues = [
        item["code"] for item in governance.get("knownIssues", [])
        if item.get("setupId") == candidate["setupId"]
    ]
    if blocking_issues:
        raise ValueError("promoção bloqueada por pendências: " + ", ".join(sorted(blocking_issues)))
    relative = Path("evidence") / candidate["setupId"] / candidate["architecture"] / f"{evidence['evidenceId']}.json"
    target = root / relative
    evidence_hash = sha256(evidence_data)
    promotions = governance.setdefault("promotions", {})
    promotion = promotions.setdefault(candidate["setupId"], {})
    references = promotion.setdefault("evidenceRefs", [])
    reference = {"path": relative.as_posix(), "sha256": evidence_hash}
    existing = next((item for item in references if item.get("path") == reference["path"]), None)
    if existing is not None and existing != reference:
        raise ValueError("o caminho de evidência já existe com outro hash")
    if existing is None:
        references.append(reference)
    references.sort(key=lambda item: item["path"])
    declared = set(entry["architectures"])
    covered = {
        parts[2]
        for item in references
        if len(parts := Path(str(item.get("path", ""))).parts) >= 3
        and parts[0] == "evidence"
        and parts[1] == candidate["setupId"]
        and parts[2] in declared
    }
    promotion["maturity"] = "operational-reviewed"
    promotion["architectureScope"] = "complete" if covered == declared else "partial"
    preview = {
        "mode": "apply" if args.apply else "dry-run",
        "candidateId": candidate["candidateId"],
        "decisionId": decision["decisionId"],
        "setupId": candidate["setupId"],
        "architecture": candidate["architecture"],
        "evidencePath": relative.as_posix(),
        "evidenceSHA256": evidence_hash,
        "targetMaturity": "operational-reviewed",
        "architectureScope": promotion["architectureScope"],
        "officialSeal": False,
    }
    if not args.apply:
        print(json.dumps(preview, ensure_ascii=False, sort_keys=True))
        return 0
    if target.exists() and read_regular(target, 1 << 20) != evidence_data:
        raise ValueError("a evidência canônica existente possui conteúdo diferente")
    governance_original = governance_path.read_bytes()
    quality_original = quality_path.read_bytes() if quality_path.exists() else None
    created_evidence = not target.exists()
    target.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    temporary = target.with_name(f".{target.name}.tmp")
    try:
        if created_evidence:
            runner.atomic_write(temporary, evidence_data)
            temporary.chmod(0o644)
            os.replace(temporary, target)
        runner.atomic_write(governance_path, canonical_json(governance))
        command = [
            sys.executable, "-B", str(root / "tools" / "knowledge_quality.py"),
            "--root", str(root), "--catalog", str(catalog),
            "--write-report", str(quality_path), "--enforce-baseline",
        ]
        subprocess.run(command, check=True)
    except Exception:
        runner.atomic_write(governance_path, governance_original)
        if quality_original is None:
            quality_path.unlink(missing_ok=True)
        else:
            runner.atomic_write(quality_path, quality_original)
        if created_evidence:
            target.unlink(missing_ok=True)
        temporary.unlink(missing_ok=True)
        raise
    print(json.dumps(preview, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, json.JSONDecodeError, subprocess.CalledProcessError) as exc:
        print(f"ERRO: {exc}", file=sys.stderr)
        raise SystemExit(2)
