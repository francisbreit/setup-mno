#!/usr/bin/python3
"""Classifica maturidade editorial e bloqueia promoções sem evidência."""

from __future__ import annotations

import argparse
from collections import Counter
import datetime as dt
import json
import os
import re
import sys
import tempfile
from pathlib import Path
from typing import Any

from lint_knowledge import load_json, parse_document


SCHEMA_VERSION = 1
MATURITY_LEVELS = (
    "structural",
    "source-reviewed",
    "script-reviewed",
    "operational-reviewed",
    "homologated",
)
EDITORIAL_STATUSES = {"draft", "reviewed", "homologated", "outdated", "deprecated"}
SEMVER_RE = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
CJK_RE = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff]")


def catalog_architectures(value: Any) -> set[str]:
    mapping = {
        "x86": {"amd64"},
        "arm": {"arm64"},
        "x86-arm": {"amd64", "arm64"},
    }
    if value not in mapping:
        raise ValueError(f"arquitetura desconhecida no catálogo: {value!r}")
    return mapping[value]


def evidence_for_promotion(promotion: Any) -> dict[str, Any]:
    if promotion is None:
        return {}
    if not isinstance(promotion, dict):
        raise ValueError("promoção deve ser um objeto")
    return promotion


def build_report(root: Path, catalog_path: Path) -> dict[str, Any]:
    governance = load_json(root / "registry" / "governance.json")
    registry = load_json(root / "registry" / "setups.json")
    catalog = load_json(catalog_path)
    knowledge_version = (root / "VERSION").read_text(encoding="utf-8").strip()
    if governance.get("schemaVersion") != SCHEMA_VERSION:
        raise ValueError("registry/governance.json possui schemaVersion incompatível")
    if governance.get("maturityLevels") != list(MATURITY_LEVELS):
        raise ValueError("registry/governance.json alterou a ordem canônica de maturidade")
    if governance.get("defaultMaturity") != "structural":
        raise ValueError("a maturidade padrão deve permanecer structural")
    if governance.get("setupVersion") != registry.get("setupVersion"):
        raise ValueError("governança e registro divergem na versão do Setup")
    if governance.get("knowledgeVersion") != knowledge_version:
        raise ValueError("governança e VERSION divergem na versão do conhecimento")
    if not SEMVER_RE.fullmatch(knowledge_version):
        raise ValueError("VERSION da base não segue SemVer")
    if not isinstance(catalog, list) or not catalog:
        raise ValueError("catálogo inválido")

    catalog_by_name = {entry["name"]: entry for entry in catalog}
    if len(catalog_by_name) != len(catalog):
        raise ValueError("catálogo possui nomes duplicados")
    source_exceptions = {
        entry["setupId"]: entry["reason"]
        for entry in governance.get("sourceExceptions", [])
    }
    promotions = governance.get("promotions", {})
    if not isinstance(promotions, dict):
        raise ValueError("governance.promotions deve ser um objeto")
    known_issues: dict[str, set[str]] = {}
    for issue in governance.get("knownIssues", []):
        setup_id = issue.get("setupId")
        code = issue.get("code")
        reason = issue.get("reason")
        if not all(isinstance(value, str) and value.strip() for value in (setup_id, code, reason)):
            raise ValueError("knownIssues contém entrada inválida")
        known_issues.setdefault(setup_id, set()).add(code)

    documents: dict[str, Any] = {}
    for path in sorted((root / "setups").glob("*/overview.md")):
        document = parse_document(path)
        setup_id = document.metadata.get("setupId")
        if document.metadata.get("documentType") != "setup" or not setup_id:
            continue
        if setup_id in documents:
            raise ValueError(f"documento de setup duplicado: {setup_id}")
        documents[setup_id] = document

    registry_entries = registry.get("setups")
    if not isinstance(registry_entries, list) or not registry_entries:
        raise ValueError("registry/setups.json inválido")
    registry_ids = {entry["setupId"] for entry in registry_entries}
    unknown_promotions = set(promotions) - registry_ids
    unknown_exceptions = set(source_exceptions) - registry_ids
    unknown_issues = set(known_issues) - registry_ids
    if unknown_promotions or unknown_exceptions or unknown_issues:
        raise ValueError("governança referencia setupId desconhecido")

    entries: list[dict[str, Any]] = []
    latest_date = ""
    for registry_entry in sorted(registry_entries, key=lambda item: item["setupId"]):
        setup_id = registry_entry["setupId"]
        catalog_name = registry_entry["catalogName"]
        document = documents.get(setup_id)
        catalog_entry = catalog_by_name.get(catalog_name)
        if document is None or catalog_entry is None:
            raise ValueError(f"classificação sem documento ou catálogo: {setup_id}")
        metadata = document.metadata
        editorial_status = metadata.get("status")
        if editorial_status not in EDITORIAL_STATUSES:
            raise ValueError(f"status editorial inválido: {setup_id}")
        sources = metadata.get("sources", [])
        official_source = any(source.get("sourceType") == "official-documentation" for source in sources)
        script_source = any(
            source.get("sourceType") == "setup-mno"
            and str(source.get("location", "")).endswith(".sh")
            for source in sources
        )
        has_exception = setup_id in source_exceptions
        if official_source:
            source_classification = "official-and-internal"
        elif has_exception:
            source_classification = "exception-approved"
        else:
            source_classification = "internal-only"

        promotion = evidence_for_promotion(promotions.get(setup_id))
        maturity = promotion.get("maturity", governance["defaultMaturity"])
        if maturity not in MATURITY_LEVELS:
            raise ValueError(f"maturidade inválida para {setup_id}: {maturity}")
        maturity_index = MATURITY_LEVELS.index(maturity)
        if maturity_index >= MATURITY_LEVELS.index("source-reviewed"):
            if editorial_status not in {"reviewed", "homologated"}:
                raise ValueError(f"{setup_id}: promoção exige revisão editorial")
            if not (official_source or has_exception):
                raise ValueError(f"{setup_id}: promoção exige fonte oficial ou exceção")
        if maturity_index >= MATURITY_LEVELS.index("script-reviewed") and not script_source:
            raise ValueError(f"{setup_id}: promoção exige fonte do instalador real")

        operational = promotion.get("operationalEvidence")
        has_operational = isinstance(operational, dict) and bool(operational)
        if maturity_index >= MATURITY_LEVELS.index("operational-reviewed"):
            if not has_operational:
                raise ValueError(f"{setup_id}: promoção exige evidência operacional")
            verified_at = operational.get("verifiedAt")
            try:
                dt.date.fromisoformat(verified_at)
            except (TypeError, ValueError) as exc:
                raise ValueError(f"{setup_id}: verifiedAt operacional inválido") from exc
            architectures = operational.get("architectures")
            checks = operational.get("checks")
            if set(architectures or []) != set(registry_entry["architectures"]):
                raise ValueError(f"{setup_id}: evidência operacional não cobre as arquiteturas")
            if not isinstance(checks, list) or not checks or not all(isinstance(check, str) and check.strip() for check in checks):
                raise ValueError(f"{setup_id}: checks operacionais ausentes")

        homologation = metadata.get("homologation", {})
        has_homologation = bool(
            homologation.get("verifiedAt")
            and homologation.get("verifiedPorts")
            and homologation.get("verifiedImages")
        )
        if maturity == "homologated" and (editorial_status != "homologated" or not has_homologation):
            raise ValueError(f"{setup_id}: homologação exige status e evidências completas")

        issues = set(known_issues.get(setup_id, set()))
        if source_classification == "internal-only":
            issues.add("official-source-missing")
        if catalog_entry.get("ram") is None:
            issues.add("capacity-missing")
        if catalog_architectures(catalog_entry.get("arch")) != set(registry_entry["architectures"]):
            issues.add("architecture-inconsistent")
        if CJK_RE.search(str(catalog_entry.get("desc", ""))):
            issues.add("catalog-description-invalid")
        if maturity != "structural" and issues:
            raise ValueError(f"{setup_id}: promoção bloqueada por pendências: {', '.join(sorted(issues))}")

        entries.append(
            {
                "setupId": setup_id,
                "catalogName": catalog_name,
                "editorialStatus": editorial_status,
                "maturity": maturity,
                "sourceClassification": source_classification,
                "scriptSourceDeclared": script_source,
                "operationalEvidence": has_operational,
                "homologationEvidence": has_homologation,
                "issues": sorted(issues),
            }
        )
        latest_date = max(latest_date, str(metadata.get("updatedAt", "")))

    if set(documents) != registry_ids:
        raise ValueError("documentos e registro de setups divergem")
    editorial_counts = Counter(entry["editorialStatus"] for entry in entries)
    maturity_counts = Counter(entry["maturity"] for entry in entries)
    for value in EDITORIAL_STATUSES:
        editorial_counts.setdefault(value, 0)
    for value in MATURITY_LEVELS:
        maturity_counts.setdefault(value, 0)
    issue_entries = sum(bool(entry["issues"]) for entry in entries)
    issue_count = sum(len(entry["issues"]) for entry in entries)
    return {
        "schemaVersion": SCHEMA_VERSION,
        "setupVersion": registry["setupVersion"],
        "knowledgeVersion": knowledge_version,
        "generatedAt": latest_date + "T00:00:00Z",
        "summary": {
            "setupEntries": len(entries),
            "editorialStatuses": dict(sorted(editorial_counts.items())),
            "maturityLevels": dict(sorted(maturity_counts.items())),
            "officialSourceEntries": sum(entry["sourceClassification"] == "official-and-internal" for entry in entries),
            "officialSourceExceptions": sum(entry["sourceClassification"] == "exception-approved" for entry in entries),
            "internalOnlySourceEntries": sum(entry["sourceClassification"] == "internal-only" for entry in entries),
            "operationalEvidenceEntries": sum(entry["operationalEvidence"] for entry in entries),
            "homologatedEntries": sum(entry["maturity"] == "homologated" for entry in entries),
            "issueEntries": issue_entries,
            "unresolvedIssueCount": issue_count,
        },
        "entries": entries,
    }


def evaluate_baseline(report: dict[str, Any], baseline: dict[str, Any]) -> list[str]:
    if baseline.get("schemaVersion") != SCHEMA_VERSION:
        return ["quality-baseline.json possui schemaVersion incompatível"]
    summary = report["summary"]
    maturity = summary["maturityLevels"]
    source_or_higher = sum(maturity[level] for level in MATURITY_LEVELS[1:])
    script_or_higher = sum(maturity[level] for level in MATURITY_LEVELS[2:])
    operational_or_higher = sum(maturity[level] for level in MATURITY_LEVELS[3:])
    comparisons = (
        (summary["setupEntries"], baseline.get("minimumSetupEntries"), "quantidade de setups classificados regrediu", ">="),
        (summary["officialSourceEntries"], baseline.get("minimumOfficialSourceEntries"), "cobertura de fontes oficiais regrediu", ">="),
        (source_or_higher, baseline.get("minimumSourceReviewedEntries"), "maturidade source-reviewed regrediu", ">="),
        (script_or_higher, baseline.get("minimumScriptReviewedEntries"), "maturidade script-reviewed regrediu", ">="),
        (operational_or_higher, baseline.get("minimumOperationalReviewedEntries"), "maturidade operacional regrediu", ">="),
        (summary["homologatedEntries"], baseline.get("minimumHomologatedEntries"), "homologações regrediram", ">="),
        (summary["unresolvedIssueCount"], baseline.get("maximumUnresolvedIssueCount"), "a quantidade de pendências aumentou", "<="),
    )
    errors: list[str] = []
    for actual, expected, message, operator in comparisons:
        if not isinstance(expected, int):
            errors.append("quality-baseline.json possui campo ausente ou inválido")
        elif (operator == ">=" and actual < expected) or (operator == "<=" and actual > expected):
            errors.append(message)
    return errors


def canonical_json(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")


def atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink():
        raise ValueError(f"destino não pode ser symlink: {path}")
    descriptor, name = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=path.parent)
    temporary = Path(name)
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


def main() -> int:
    default_root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=default_root)
    parser.add_argument("--catalog", type=Path, default=default_root.parent / "setupmno-control" / "catalog.json")
    parser.add_argument("--baseline", type=Path, default=default_root / "quality-baseline.json")
    parser.add_argument("--write-report", type=Path)
    parser.add_argument("--enforce-baseline", action="store_true")
    arguments = parser.parse_args()
    try:
        report = build_report(arguments.root, arguments.catalog)
        baseline = load_json(arguments.baseline)
        errors = evaluate_baseline(report, baseline)
        report["baseline"] = {
            "release": baseline.get("baselineRelease"),
            "passed": not errors,
            "errors": errors,
        }
        if arguments.write_report:
            atomic_write(arguments.write_report, canonical_json({key: value for key, value in report.items() if key != "baseline"}))
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(json.dumps({"status": "invalid", "error": str(error)}, ensure_ascii=False))
        return 2
    print(json.dumps(report, ensure_ascii=False, sort_keys=True))
    if arguments.enforce_baseline and errors:
        return 4
    return 0


if __name__ == "__main__":
    sys.exit(main())
