#!/usr/bin/python3
"""Emite o selo oficial somente após revisão completa e confirmação do mantenedor."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

import homologation_runner as runner
from import_homologation_review import (
    MAX_PACK_BYTES,
    canonical_json,
    load_review_pack,
    read_regular,
    sha256,
)
from lint_knowledge import parse_document
from knowledge_quality import build_report as build_quality_report


SEAL_SCHEMA_VERSION = 1
LEDGER_SCHEMA_VERSION = 1
ALL_CHECKS = (
    "deploy", "convergence", "health", "persistence", "restart",
    "update", "backup", "restore", "cleanup",
)
SHA256_RE = re.compile(r"^[a-f0-9]{64}$")
ID_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
SEMVER_RE = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")


def parse_utc(value: str, label: str) -> dt.datetime:
    if not isinstance(value, str) or not value.endswith("Z"):
        raise ValueError(f"{label} deve usar UTC e terminar em Z")
    try:
        parsed = dt.datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError as exc:
        raise ValueError(f"{label} inválido") from exc
    if parsed.utcoffset() != dt.timedelta(0):
        raise ValueError(f"{label} deve usar UTC")
    return parsed


def now_utc() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def require_text(value: str, label: str, minimum: int, maximum: int) -> str:
    text = " ".join(str(value).split())
    if not minimum <= len(text) <= maximum:
        raise ValueError(f"{label} deve ter entre {minimum} e {maximum} caracteres")
    runner.reject_sensitive(text, label)
    return text


def load_json_regular(path: Path, limit: int = 2 << 20) -> Any:
    return json.loads(read_regular(path, limit))


def relative_regular(root: Path, relative: str, expected_hash: str, limit: int) -> bytes:
    parts = Path(relative).parts
    if not parts or ".." in parts or Path(relative).is_absolute():
        raise ValueError(f"caminho canônico inválido: {relative}")
    path = root / relative
    parents = [root / Path(*parts[:index]) for index in range(1, len(parts))]
    if any(parent.is_symlink() for parent in parents):
        raise ValueError(f"caminho canônico contém symlink: {relative}")
    data = read_regular(path, limit)
    if sha256(data) != expected_hash:
        raise ValueError(f"SHA-256 canônico diverge: {relative}")
    return data


def validate_ledger(root: Path) -> tuple[Path, dict[str, Any]]:
    ledger_path = root / "registry" / "certification-ledger.json"
    ledger = load_json_regular(ledger_path)
    if not isinstance(ledger, dict) or set(ledger) != {"schemaVersion", "kind", "entries"}:
        raise ValueError("ledger de certificação possui campos inesperados")
    if ledger["schemaVersion"] != LEDGER_SCHEMA_VERSION or ledger["kind"] != "setupmno-certification-ledger":
        raise ValueError("ledger de certificação é incompatível")
    entries = ledger.get("entries")
    if not isinstance(entries, list):
        raise ValueError("ledger de certificação deve possuir uma lista de entradas")
    seen_ids: set[str] = set()
    seen_paths: set[str] = set()
    previous_key: tuple[str, str] | None = None
    for item in entries:
        expected = {"sealId", "setupId", "setupVersion", "issuedAt", "path", "sha256"}
        if not isinstance(item, dict) or set(item) != expected:
            raise ValueError("entrada inválida no ledger de certificação")
        seal_id = item.get("sealId")
        setup_id = item.get("setupId")
        path = item.get("path")
        digest = item.get("sha256")
        if (
            not ID_RE.fullmatch(str(seal_id))
            or not str(seal_id).endswith("-official")
            or not ID_RE.fullmatch(str(setup_id))
            or not SEMVER_RE.fullmatch(str(item.get("setupVersion")))
            or not SHA256_RE.fullmatch(str(digest))
            or path != f"certifications/{setup_id}/{seal_id}.json"
        ):
            raise ValueError("identidade inválida no ledger de certificação")
        parse_utc(item.get("issuedAt"), "issuedAt do ledger")
        if seal_id in seen_ids or path in seen_paths:
            raise ValueError("ledger de certificação contém duplicidade")
        key = (item["issuedAt"], seal_id)
        if previous_key is not None and key < previous_key:
            raise ValueError("ledger de certificação não está em ordem cronológica")
        previous_key = key
        seen_ids.add(seal_id)
        seen_paths.add(path)
        relative_regular(root, path, digest, 256 << 10)
    return ledger_path, ledger


def validate_document(root: Path, setup_id: str, entry: dict[str, Any], evidences: list[dict[str, Any]]) -> None:
    document = parse_document(root / "setups" / setup_id / "overview.md")
    metadata = document.metadata
    if metadata.get("setupId") != setup_id or metadata.get("status") != "homologated":
        raise ValueError(
            f"{setup_id}: documento precisa estar revisado e com status editorial homologated"
        )
    if set(metadata.get("architectures", [])) != set(entry["architectures"]):
        raise ValueError(f"{setup_id}: arquiteturas do documento divergem do registro")
    homologation = metadata.get("homologation")
    if not isinstance(homologation, dict):
        raise ValueError(f"{setup_id}: metadados de homologação ausentes")
    verified_at = homologation.get("verifiedAt")
    try:
        verified_date = dt.date.fromisoformat(verified_at)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{setup_id}: verifiedAt editorial inválido") from exc
    ports = homologation.get("verifiedPorts")
    documented_images = homologation.get("verifiedImages")
    if not isinstance(ports, list) or not ports or not all(isinstance(port, int) and 1 <= port <= 65535 for port in ports):
        raise ValueError(f"{setup_id}: verifiedPorts editorial está incompleto")
    evidence_images = {image for evidence in evidences for image in evidence["images"]}
    if (
        not isinstance(documented_images, list)
        or not documented_images
        or not evidence_images.issubset(set(documented_images))
    ):
        raise ValueError(f"{setup_id}: verifiedImages não cobre os digests homologados")
    newest_evidence = max(parse_utc(item["verifiedAt"], "verifiedAt da evidência").date() for item in evidences)
    if verified_date < newest_evidence:
        raise ValueError(f"{setup_id}: documento é anterior à evidência mais recente")


def prepare_certification(
    packs: list[Path], root: Path, catalog: Path, package_dir: Path,
    maintainer: str, reason: str, issued_at: str,
) -> dict[str, Any]:
    if root.is_symlink() or not root.is_dir():
        raise ValueError("raiz canônica ausente ou insegura")
    maintainer = require_text(maintainer, "identificação do mantenedor", 2, 80)
    reason = require_text(reason, "justificativa", 3, 240)
    issued_time = parse_utc(issued_at, "issuedAt")
    _, package_registry = runner.validate_package(package_dir)
    package_entries = runner.registry_by_id(package_registry)
    registry = load_json_regular(root / "registry" / "setups.json")
    registry_entries = {item["setupId"]: item for item in registry.get("setups", [])}
    if registry.get("setupVersion") != package_registry.get("setupVersion"):
        raise ValueError("registro canônico e pacote do runner divergem na versão")
    if not packs:
        raise ValueError("informe ao menos um pacote de revisão")

    records: list[dict[str, Any]] = []
    setup_id = ""
    setup_version = ""
    seen_architectures: set[str] = set()
    seen_decisions: set[str] = set()
    for pack in packs:
        pack = pack.resolve()
        candidate, decision, evidence, evidence_data = load_review_pack(pack)
        if not setup_id:
            setup_id = candidate["setupId"]
            setup_version = candidate["setupVersion"]
        if candidate["setupId"] != setup_id or candidate["setupVersion"] != setup_version:
            raise ValueError("todos os pacotes devem pertencer ao mesmo setup e versão")
        architecture = candidate["architecture"]
        if architecture in seen_architectures:
            raise ValueError(f"pacote duplicado para arquitetura {architecture}")
        if decision["decisionId"] in seen_decisions:
            raise ValueError("decisionId duplicado")
        if any(candidate["checks"][name]["status"] != "passed" for name in ALL_CHECKS):
            raise ValueError(f"{architecture}: os nove checks precisam estar aprovados")
        if parse_utc(candidate["createdAt"], "createdAt do candidato") > issued_time:
            raise ValueError("o selo não pode ser anterior ao candidato")
        if parse_utc(decision["reviewedAt"], "reviewedAt da decisão") > issued_time:
            raise ValueError("o selo não pode ser anterior à decisão")
        runner.reject_sensitive(candidate, "candidato homologado")
        runner.reject_sensitive(decision, "decisão homologada")
        entry = package_entries.get(setup_id)
        if entry is None or candidate["artifact"] != entry["artifacts"].get(architecture):
            raise ValueError(f"{architecture}: pacote do runner diverge do artefato aprovado")
        source_script = root.parent / candidate["artifact"]["path"]
        if runner.sha256_file(source_script) != candidate["artifact"]["sha256"]:
            raise ValueError(f"{architecture}: código vivo mudou após a homologação")
        records.append({
            "pack": pack,
            "packSHA256": sha256(read_regular(pack, MAX_PACK_BYTES)),
            "candidate": candidate,
            "decision": decision,
            "decisionData": canonical_json(decision),
            "evidence": evidence,
            "evidenceData": evidence_data,
        })
        seen_architectures.add(architecture)
        seen_decisions.add(decision["decisionId"])

    entry = registry_entries.get(setup_id)
    package_entry = package_entries.get(setup_id)
    if entry is None or package_entry is None:
        raise ValueError("setup não existe no registro canônico atual")
    if setup_version != registry["setupVersion"]:
        raise ValueError("a evidência não pertence à versão atual do Setup MNO")
    declared = set(entry["architectures"])
    if seen_architectures != declared:
        missing = sorted(declared - seen_architectures)
        extra = sorted(seen_architectures - declared)
        raise ValueError(f"cobertura arquitetural incompleta; ausentes={missing}; extras={extra}")
    if package_entry["architectures"] != entry["architectures"]:
        raise ValueError("arquiteturas divergem entre registros canônicos")
    governance_path = root / "registry" / "governance.json"
    governance = load_json_regular(governance_path)
    issues = sorted(
        item["code"] for item in governance.get("knownIssues", [])
        if item.get("setupId") == setup_id
    )
    if issues:
        raise ValueError("certificação bloqueada por pendências: " + ", ".join(issues))
    validate_document(root, setup_id, entry, [record["evidence"] for record in records])
    ledger_path, ledger = validate_ledger(root)
    build_quality_report(root, catalog)

    ordered = sorted(records, key=lambda item: item["candidate"]["architecture"])
    timestamp = issued_time.strftime("%Y%m%d%H%M%S")
    version_id = setup_version.replace(".", "-")
    seal_id = f"{setup_id}-{version_id}-{timestamp}-official"
    evidence_refs: list[dict[str, str]] = []
    decision_refs: list[dict[str, str]] = []
    artifacts: list[dict[str, str]] = []
    review_packs: list[dict[str, str]] = []
    writes: list[tuple[Path, bytes]] = []
    for record in ordered:
        architecture = record["candidate"]["architecture"]
        evidence_relative = Path("evidence") / setup_id / architecture / f"{record['evidence']['evidenceId']}.json"
        decision_relative = Path("certifications") / setup_id / "decisions" / f"{record['decision']['decisionId']}.json"
        evidence_hash = sha256(record["evidenceData"])
        decision_hash = sha256(record["decisionData"])
        evidence_refs.append({"architecture": architecture, "path": evidence_relative.as_posix(), "sha256": evidence_hash})
        decision_refs.append({"architecture": architecture, "path": decision_relative.as_posix(), "sha256": decision_hash})
        artifacts.append({"architecture": architecture, **record["candidate"]["artifact"]})
        review_packs.append({"architecture": architecture, "sha256": record["packSHA256"]})
        writes.extend([
            (root / evidence_relative, record["evidenceData"]),
            (root / decision_relative, record["decisionData"]),
        ])
    seal = {
        "schemaVersion": SEAL_SCHEMA_VERSION,
        "kind": "setupmno-official-homologation-seal",
        "sealId": seal_id,
        "setupId": setup_id,
        "setupVersion": setup_version,
        "issuedAt": issued_at,
        "issuedBy": maintainer,
        "reason": reason,
        "architectures": sorted(declared),
        "artifacts": artifacts,
        "images": sorted({image for record in ordered for image in record["candidate"]["images"]}),
        "evidenceRefs": evidence_refs,
        "decisionRefs": decision_refs,
        "reviewPacks": review_packs,
        "status": "issued",
        "immutable": True,
        "automaticPromotion": False,
        "officialSeal": True,
    }
    runner.reject_sensitive(seal, "selo oficial")
    seal_data = canonical_json(seal)
    seal_relative = Path("certifications") / setup_id / f"{seal_id}.json"
    seal_hash = sha256(seal_data)
    writes.append((root / seal_relative, seal_data))
    ledger_entry = {
        "sealId": seal_id,
        "setupId": setup_id,
        "setupVersion": setup_version,
        "issuedAt": issued_at,
        "path": seal_relative.as_posix(),
        "sha256": seal_hash,
    }
    if any(item["sealId"] == seal_id or item["path"] == ledger_entry["path"] for item in ledger["entries"]):
        raise ValueError("este selo já existe no ledger imutável")
    ledger["entries"].append(ledger_entry)
    ledger["entries"].sort(key=lambda item: (item["issuedAt"], item["sealId"]))

    governance_updated = json.loads(json.dumps(governance))
    governance_updated.setdefault("promotions", {})[setup_id] = {
        "maturity": "homologated",
        "architectureScope": "complete",
        "evidenceRefs": [
            {"path": item["path"], "sha256": item["sha256"]}
            for item in evidence_refs
        ],
        "sealRef": {"path": seal_relative.as_posix(), "sha256": seal_hash},
    }
    confirmation_token = hashlib.sha256(
        seal_data + canonical_json(governance_updated) + canonical_json(ledger)
    ).hexdigest()[:12].upper()
    return {
        "setupId": setup_id,
        "setupVersion": setup_version,
        "architectures": sorted(declared),
        "seal": seal,
        "sealPath": seal_relative.as_posix(),
        "sealSHA256": seal_hash,
        "confirmationToken": confirmation_token,
        "writes": writes,
        "governancePath": governance_path,
        "governance": governance_updated,
        "ledgerPath": ledger_path,
        "ledger": ledger,
        "catalog": catalog,
    }


def write_transaction(prepared: dict[str, Any], root: Path) -> None:
    quality_path = root / "registry" / "quality-report.json"
    immutable_targets = list(prepared["writes"])
    mutable_targets = [
        (prepared["ledgerPath"], canonical_json(prepared["ledger"])),
        (prepared["governancePath"], canonical_json(prepared["governance"])),
    ]
    targets = immutable_targets + mutable_targets
    originals: dict[Path, bytes | None] = {}
    for path, data in targets:
        validate_destination(root, path)
        if path in originals:
            raise ValueError(f"destino repetido na transação: {path}")
        originals[path] = read_regular(path, 4 << 20) if path.exists() else None
        if path in {item[0] for item in immutable_targets} and originals[path] is not None and originals[path] != data:
            raise ValueError(f"destino imutável já existe com conteúdo diferente: {path}")
    originals[quality_path] = read_regular(quality_path, 8 << 20) if quality_path.exists() else None
    try:
        for path, data in targets:
            if path in {item[0] for item in mutable_targets} or originals[path] is None:
                runner.atomic_write(path, data, 0o644)
        command = [
            sys.executable, "-B", str(root / "tools" / "knowledge_quality.py"),
            "--root", str(root), "--catalog", str(prepared["catalog"]),
            "--write-report", str(quality_path), "--enforce-baseline",
        ]
        completed = subprocess.run(command, check=True, capture_output=True, text=True)
        if not completed.stdout.strip():
            raise ValueError("gate de qualidade não retornou evidência")
        report = json.loads(completed.stdout)
        entry = next((item for item in report.get("entries", []) if item.get("setupId") == prepared["setupId"]), None)
        if entry is None or entry.get("maturity") != "homologated":
            raise ValueError("gate final não confirmou a maturidade homologated")
    except Exception:
        for path, original in reversed(list(originals.items())):
            if original is None:
                path.unlink(missing_ok=True)
                parent = path.parent
                while parent != root and parent.exists():
                    try:
                        parent.rmdir()
                    except OSError:
                        break
                    parent = parent.parent
            else:
                runner.atomic_write(path, original, 0o644)
        raise


def public_result(prepared: dict[str, Any], applied: bool) -> dict[str, Any]:
    return {
        "mode": "apply" if applied else "dry-run",
        "setupId": prepared["setupId"],
        "setupVersion": prepared["setupVersion"],
        "architectures": prepared["architectures"],
        "targetMaturity": "homologated",
        "sealId": prepared["seal"]["sealId"],
        "sealPath": prepared["sealPath"],
        "sealSHA256": prepared["sealSHA256"],
        "confirmationToken": prepared["confirmationToken"],
        "gates": {
            "allArchitectures": True,
            "allNineChecks": True,
            "currentArtifacts": True,
            "documentHomologated": True,
            "knownIssues": False,
            "ledgerConsistent": True,
        },
        "governanceUpdated": applied,
        "officialSeal": applied,
        "automaticPromotion": False,
        "gitChanged": False,
        "releaseCreated": False,
    }


def validate_destination(root: Path, path: Path) -> None:
    if not path.is_relative_to(root) or path == root:
        raise ValueError(f"destino fora da raiz canônica: {path}")
    if path.is_symlink():
        raise ValueError(f"destino não pode ser symlink: {path}")
    current = path.parent
    while current != root:
        if current.is_symlink():
            raise ValueError(f"diretório de destino não pode ser symlink: {current}")
        current = current.parent


def main() -> int:
    default_root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack", action="append", type=Path, required=True, help="pacote aprovado; repita para cada arquitetura")
    parser.add_argument("--root", type=Path, default=default_root)
    parser.add_argument("--catalog", type=Path, default=default_root.parent / "setupmno-control" / "catalog.json")
    parser.add_argument("--package-dir", type=Path, default=default_root.parent / "setupmno-control" / "homologation-package")
    parser.add_argument("--maintainer", required=True)
    parser.add_argument("--reason", required=True)
    parser.add_argument("--issued-at", default=now_utc())
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--confirm", default="")
    arguments = parser.parse_args()
    root = arguments.root.resolve()
    prepared = prepare_certification(
        arguments.pack, root, arguments.catalog.resolve(), arguments.package_dir.resolve(),
        arguments.maintainer, arguments.reason, arguments.issued_at,
    )
    if not arguments.apply:
        print(json.dumps(public_result(prepared, False), ensure_ascii=False, sort_keys=True))
        return 0
    if arguments.confirm != prepared["confirmationToken"]:
        raise ValueError("confirmação inválida; execute o dry-run e informe o token exibido")
    write_transaction(prepared, root)
    print(json.dumps(public_result(prepared, True), ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, json.JSONDecodeError, subprocess.CalledProcessError) as exc:
        detail = str(exc)
        if isinstance(exc, subprocess.CalledProcessError) and exc.stderr:
            detail = exc.stderr.strip() or detail
        print(f"ERRO: {detail}", file=sys.stderr)
        raise SystemExit(2)
