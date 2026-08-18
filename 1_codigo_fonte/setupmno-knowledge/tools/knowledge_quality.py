#!/usr/bin/python3
"""Classifica maturidade editorial e bloqueia promoções sem evidência."""

from __future__ import annotations

import argparse
from collections import Counter
import datetime as dt
import hashlib
import json
import os
import re
import sys
import tempfile
from pathlib import Path
from typing import Any

from lint_knowledge import load_json, parse_document


SCHEMA_VERSION = 2
EVIDENCE_SCHEMA_VERSION = 1
MATURITY_LEVELS = (
    "structural",
    "source-reviewed",
    "script-reviewed",
    "operational-reviewed",
    "homologated",
)
EDITORIAL_STATUSES = {"draft", "reviewed", "homologated", "outdated", "deprecated"}
INSTALLATION_STATUSES = ("maintainer-homologated",)
INTEGRATION_MATURITY_LEVELS = ("not-mapped", "suggested", "documented", "validated")
SEMVER_RE = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
CJK_RE = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff]")
EVIDENCE_ID_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
SHA256_RE = re.compile(r"^[a-f0-9]{64}$")
SENSITIVE_FIELD_RE = re.compile(
    r"(?:password|passwd|senha|token|secret|credential|authorization|hostname|ipaddress)",
    re.IGNORECASE,
)
SENSITIVE_VALUE_PATTERNS = (
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"\bBearer\s+[A-Za-z0-9._~+/-]{12,}", re.IGNORECASE),
    re.compile(r"\b(?:sk|cfut)_[A-Za-z0-9_-]{12,}\b"),
    re.compile(r"\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b"),
)
EVIDENCE_CHECKS = (
    "deploy",
    "convergence",
    "health",
    "persistence",
    "restart",
    "update",
    "backup",
    "restore",
    "cleanup",
)
OPERATIONAL_CHECKS = (
    "deploy",
    "convergence",
    "health",
    "persistence",
    "restart",
    "cleanup",
)
HOMOLOGATION_CHECKS = EVIDENCE_CHECKS
EVIDENCE_STATUSES = {"passed", "not-tested", "not-applicable"}


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


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse_utc_datetime(value: Any, label: str) -> dt.datetime:
    if not isinstance(value, str) or not value.endswith("Z"):
        raise ValueError(f"{label} deve usar data e hora UTC terminada em Z")
    try:
        parsed = dt.datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError as exc:
        raise ValueError(f"{label} inválido") from exc
    return parsed


def reject_sensitive_evidence(value: Any, context: str = "evidência") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if SENSITIVE_FIELD_RE.search(str(key)):
                raise ValueError(f"{context}: campo sensível proibido: {key}")
            reject_sensitive_evidence(child, context)
        return
    if isinstance(value, list):
        for child in value:
            reject_sensitive_evidence(child, context)
        return
    if isinstance(value, str):
        for pattern in SENSITIVE_VALUE_PATTERNS:
            if pattern.search(value):
                raise ValueError(f"{context}: conteúdo sensível proibido")


def require_exact_keys(value: Any, keys: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != keys:
        raise ValueError(f"{label} possui campos ausentes ou desconhecidos")
    return value


def load_operational_evidence(
    root: Path,
    setup_id: str,
    registry_entry: dict[str, Any],
    promotion: dict[str, Any],
) -> list[dict[str, Any]]:
    allowed_promotion_keys = {"maturity", "architectureScope", "evidenceRefs"}
    if set(promotion) - allowed_promotion_keys:
        raise ValueError(f"{setup_id}: promoção contém campos não suportados")
    references = promotion.get("evidenceRefs", [])
    if not isinstance(references, list):
        raise ValueError(f"{setup_id}: evidenceRefs deve ser uma lista")
    records: list[dict[str, Any]] = []
    seen_ids: set[str] = set()
    seen_paths: set[str] = set()
    seen_architectures: set[str] = set()
    for reference in references:
        reference = require_exact_keys(reference, {"path", "sha256"}, f"{setup_id}: evidenceRef")
        relative = reference.get("path")
        expected_hash = reference.get("sha256")
        if not isinstance(relative, str) or not SHA256_RE.fullmatch(str(expected_hash)):
            raise ValueError(f"{setup_id}: referência de evidência inválida")
        parts = Path(relative).parts
        if (
            len(parts) != 4
            or parts[0] != "evidence"
            or parts[1] != setup_id
            or parts[2] not in {"amd64", "arm64"}
            or not parts[3].endswith(".json")
            or ".." in parts
            or relative in seen_paths
        ):
            raise ValueError(f"{setup_id}: caminho de evidência inválido: {relative}")
        seen_paths.add(relative)
        path = root / relative
        evidence_parents = [
            root / Path(*parts[:index])
            for index in range(1, len(parts))
        ]
        if (
            any(parent.is_symlink() for parent in evidence_parents)
            or path.is_symlink()
            or not path.is_file()
            or path.stat().st_size > 65536
        ):
            raise ValueError(f"{setup_id}: evidência ausente, não regular ou muito grande: {relative}")
        if sha256_file(path) != expected_hash:
            raise ValueError(f"{setup_id}: SHA-256 da evidência diverge: {relative}")
        record = load_json(path)
        required = {
            "schemaVersion", "evidenceId", "setupId", "setupVersion", "architecture",
            "verifiedAt", "environment", "artifact", "images", "checks", "result",
            "sanitized", "review",
        }
        record = require_exact_keys(record, required, f"{setup_id}: evidência")
        if record.get("schemaVersion") != EVIDENCE_SCHEMA_VERSION:
            raise ValueError(f"{setup_id}: schema de evidência incompatível")
        evidence_id = record.get("evidenceId")
        architecture = record.get("architecture")
        if (
            not isinstance(evidence_id, str)
            or not EVIDENCE_ID_RE.fullmatch(evidence_id)
            or evidence_id in seen_ids
            or record.get("setupId") != setup_id
            or architecture != parts[2]
            or architecture not in registry_entry["architectures"]
            or architecture in seen_architectures
            or not SEMVER_RE.fullmatch(str(record.get("setupVersion", "")))
        ):
            raise ValueError(f"{setup_id}: identidade da evidência inválida")
        seen_ids.add(evidence_id)
        seen_architectures.add(architecture)
        verified_at = parse_utc_datetime(record.get("verifiedAt"), f"{setup_id}: verifiedAt")

        environment = require_exact_keys(
            record.get("environment"), {"platform", "orchestrator", "isolation"},
            f"{setup_id}: environment",
        )
        if (
            environment.get("platform") not in {"linux-vps", "wsl2-docker-desktop", "linux-emulated"}
            or environment.get("orchestrator") != "docker-swarm"
            or environment.get("isolation") != "setupmno-hml"
        ):
            raise ValueError(f"{setup_id}: ambiente de evidência inválido")

        artifact = require_exact_keys(
            record.get("artifact"), {"path", "sha256"}, f"{setup_id}: artifact",
        )
        expected_prefix = "x86" if architecture == "amd64" else "arm"
        expected_script = f"{expected_prefix}/SetupLowCodeMno/{registry_entry['script']}"
        source_script = root.parent / expected_script
        if (
            artifact.get("path") != expected_script
            or not SHA256_RE.fullmatch(str(artifact.get("sha256", "")))
            or not source_script.is_file()
            or source_script.is_symlink()
            or sha256_file(source_script) != artifact.get("sha256")
        ):
            raise ValueError(f"{setup_id}: instalador divergiu da evidência {evidence_id}")

        images = record.get("images")
        if (
            not isinstance(images, list)
            or not images
            or len(images) != len(set(images))
            or not all(
                isinstance(image, str)
                and re.fullmatch(r"\S+@sha256:[a-f0-9]{64}", image)
                for image in images
            )
        ):
            raise ValueError(f"{setup_id}: imagens da evidência devem usar digest")

        checks = require_exact_keys(record.get("checks"), set(EVIDENCE_CHECKS), f"{setup_id}: checks")
        for check_name, check in checks.items():
            check = require_exact_keys(check, {"status", "evidence"}, f"{setup_id}: check {check_name}")
            if (
                check.get("status") not in EVIDENCE_STATUSES
                or not isinstance(check.get("evidence"), str)
                or not 1 <= len(check["evidence"].strip()) <= 240
            ):
                raise ValueError(f"{setup_id}: check operacional inválido: {check_name}")
        if any(checks[name]["status"] != "passed" for name in OPERATIONAL_CHECKS):
            raise ValueError(f"{setup_id}: evidência não passou todos os checks operacionais")

        review = require_exact_keys(
            record.get("review"), {"decision", "reviewedBy", "reviewedAt"},
            f"{setup_id}: review",
        )
        try:
            reviewed_at = dt.date.fromisoformat(review.get("reviewedAt"))
        except (TypeError, ValueError) as exc:
            raise ValueError(f"{setup_id}: data de revisão da evidência inválida") from exc
        if (
            record.get("result") != "passed"
            or record.get("sanitized") is not True
            or review.get("decision") != "approved"
            or not isinstance(review.get("reviewedBy"), str)
            or not review["reviewedBy"].strip()
            or reviewed_at < verified_at.date()
        ):
            raise ValueError(f"{setup_id}: aprovação da evidência inválida")
        reject_sensitive_evidence(record, f"{setup_id}: evidência")
        records.append({**record, "sha256": expected_hash, "path": relative})
    return records


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
    assurance = governance.get("installationAssurance")
    if not isinstance(assurance, dict) or assurance.get("status") != "maintainer-homologated":
        raise ValueError("governança deve registrar a homologação dos instaladores pelo mantenedor")
    if not isinstance(assurance.get("attestedBy"), str) or not assurance["attestedBy"].strip():
        raise ValueError("governança deve identificar o responsável pela homologação dos instaladores")
    try:
        dt.date.fromisoformat(assurance.get("attestedAt"))
    except (TypeError, ValueError) as exc:
        raise ValueError("data da homologação dos instaladores é inválida") from exc
    default_integration_maturity = governance.get("defaultIntegrationMaturity")
    if default_integration_maturity not in INTEGRATION_MATURITY_LEVELS:
        raise ValueError("maturidade padrão de integrações é inválida")
    integration_promotions = governance.get("integrationPromotions", {})
    if not isinstance(integration_promotions, dict):
        raise ValueError("governance.integrationPromotions deve ser um objeto")
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
    unknown_integration_promotions = set(integration_promotions) - registry_ids
    unknown_exceptions = set(source_exceptions) - registry_ids
    unknown_issues = set(known_issues) - registry_ids
    if unknown_promotions or unknown_integration_promotions or unknown_exceptions or unknown_issues:
        raise ValueError("governança referencia setupId desconhecido")

    entries: list[dict[str, Any]] = []
    referenced_evidence_paths: set[str] = set()
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

        evidence_records = load_operational_evidence(
            root, setup_id, registry_entry, promotion
        )
        referenced_evidence_paths.update(record["path"] for record in evidence_records)
        operational_architectures = sorted(
            {record["architecture"] for record in evidence_records}
        )
        declared_architectures = set(registry_entry["architectures"])
        evidence_architectures = set(operational_architectures)
        if not evidence_architectures:
            operational_coverage = "none"
        elif evidence_architectures == declared_architectures:
            operational_coverage = "complete"
        else:
            operational_coverage = "partial"
        has_operational = bool(evidence_records)
        if maturity_index >= MATURITY_LEVELS.index("operational-reviewed"):
            if not has_operational:
                raise ValueError(f"{setup_id}: promoção exige evidência operacional")
            scope = promotion.get("architectureScope", "complete")
            if scope not in {"complete", "partial"}:
                raise ValueError(f"{setup_id}: architectureScope inválido")
            if operational_coverage != "complete" and scope != "partial":
                raise ValueError(
                    f"{setup_id}: promoção operacional não cobre todas as arquiteturas"
                )
        elif promotion.get("architectureScope") is not None:
            raise ValueError(f"{setup_id}: architectureScope exige promoção operacional")

        homologation = metadata.get("homologation", {})
        document_homologation = bool(
            homologation.get("verifiedAt")
            and homologation.get("verifiedPorts")
            and homologation.get("verifiedImages")
        )
        has_homologation = bool(
            operational_coverage == "complete"
            and evidence_records
            and all(
                all(record["checks"][name]["status"] == "passed" for name in HOMOLOGATION_CHECKS)
                for record in evidence_records
            )
            and document_homologation
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

        integration_maturity = integration_promotions.get(
            setup_id, default_integration_maturity
        )
        if integration_maturity not in INTEGRATION_MATURITY_LEVELS:
            raise ValueError(f"maturidade de integração inválida para {setup_id}")

        entries.append(
            {
                "setupId": setup_id,
                "catalogName": catalog_name,
                "editorialStatus": editorial_status,
                "maturity": maturity,
                "sourceClassification": source_classification,
                "scriptSourceDeclared": script_source,
                "operationalEvidence": has_operational,
                "operationalCoverage": operational_coverage,
                "operationalArchitectures": operational_architectures,
                "operationalEvidenceIds": sorted(
                    record["evidenceId"] for record in evidence_records
                ),
                "lastOperationalVerification": max(
                    (record["verifiedAt"] for record in evidence_records),
                    default="",
                ),
                "homologationEvidence": has_homologation,
                "installationStatus": assurance["status"],
                "testedArchitectures": sorted(registry_entry["architectures"]),
                "integrationMaturity": integration_maturity,
                "issues": sorted(issues),
            }
        )
        latest_date = max(latest_date, str(metadata.get("updatedAt", "")))

    if set(documents) != registry_ids:
        raise ValueError("documentos e registro de setups divergem")
    actual_evidence_paths = {
        path.relative_to(root).as_posix()
        for path in (root / "evidence").glob("*/*/*.json")
        if path.is_file()
    }
    if actual_evidence_paths != referenced_evidence_paths:
        missing = sorted(referenced_evidence_paths - actual_evidence_paths)
        orphaned = sorted(actual_evidence_paths - referenced_evidence_paths)
        raise ValueError(
            "inventário de evidências diverge da governança"
            f"; ausentes={missing}; órfãs={orphaned}"
        )
    editorial_counts = Counter(entry["editorialStatus"] for entry in entries)
    maturity_counts = Counter(entry["maturity"] for entry in entries)
    installation_counts = Counter(entry["installationStatus"] for entry in entries)
    integration_counts = Counter(entry["integrationMaturity"] for entry in entries)
    for value in EDITORIAL_STATUSES:
        editorial_counts.setdefault(value, 0)
    for value in MATURITY_LEVELS:
        maturity_counts.setdefault(value, 0)
    for value in INSTALLATION_STATUSES:
        installation_counts.setdefault(value, 0)
    for value in INTEGRATION_MATURITY_LEVELS:
        integration_counts.setdefault(value, 0)
    issue_entries = sum(bool(entry["issues"]) for entry in entries)
    issue_count = sum(len(entry["issues"]) for entry in entries)
    return {
        "schemaVersion": SCHEMA_VERSION,
        "evidenceSchemaVersion": EVIDENCE_SCHEMA_VERSION,
        "setupVersion": registry["setupVersion"],
        "knowledgeVersion": knowledge_version,
        "generatedAt": latest_date + "T00:00:00Z",
        "summary": {
            "setupEntries": len(entries),
            "installationStatuses": dict(sorted(installation_counts.items())),
            "integrationMaturityLevels": dict(sorted(integration_counts.items())),
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
