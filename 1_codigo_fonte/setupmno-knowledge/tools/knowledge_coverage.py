#!/usr/bin/python3
"""Mede a cobertura canônica do catálogo sem considerar rascunho como conhecimento."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from lint_knowledge import load_json, parse_document


def build_report(catalog_path: Path, registry_path: Path, root: Path) -> dict[str, Any]:
    catalog = load_json(catalog_path)
    registry = load_json(registry_path)
    if not isinstance(catalog, list) or not catalog:
        raise ValueError("o catálogo deve ser uma lista não vazia")
    if not isinstance(registry, dict) or not isinstance(registry.get("setups"), list):
        raise ValueError("o registro de setups é inválido")

    catalog_names: list[str] = []
    for index, entry in enumerate(catalog):
        name = entry.get("name") if isinstance(entry, dict) else None
        if not isinstance(name, str) or not name.strip():
            raise ValueError(f"catalog[{index}].name é inválido")
        catalog_names.append(name.strip())
    if len(set(catalog_names)) != len(catalog_names):
        raise ValueError("o catálogo possui nomes duplicados")

    registry_by_name: dict[str, dict[str, Any]] = {}
    registry_by_id: dict[str, dict[str, Any]] = {}
    duplicate_registry_names: list[str] = []
    duplicate_registry_ids: list[str] = []
    for index, entry in enumerate(registry["setups"]):
        if not isinstance(entry, dict):
            raise ValueError(f"registry.setups[{index}] é inválido")
        catalog_name = entry.get("catalogName")
        setup_id = entry.get("setupId")
        if not isinstance(catalog_name, str) or not catalog_name.strip():
            raise ValueError(f"registry.setups[{index}].catalogName é inválido")
        if not isinstance(setup_id, str) or not setup_id.strip():
            raise ValueError(f"registry.setups[{index}].setupId é inválido")
        if catalog_name in registry_by_name:
            duplicate_registry_names.append(catalog_name)
        if setup_id in registry_by_id:
            duplicate_registry_ids.append(setup_id)
        registry_by_name[catalog_name] = entry
        registry_by_id[setup_id] = entry

    documents_by_id: dict[str, str] = {}
    duplicate_document_ids: list[str] = []
    unreviewed_documents: list[str] = []
    for path in sorted((root / "setups").glob("*/overview.md")):
        document = parse_document(path)
        setup_id = document.metadata.get("setupId")
        if not isinstance(setup_id, str) or not setup_id:
            continue
        if document.metadata.get("documentType") != "setup":
            continue
        if document.metadata.get("status") not in {"reviewed", "homologated"}:
            unreviewed_documents.append(setup_id)
            continue
        if setup_id in documents_by_id:
            duplicate_document_ids.append(setup_id)
        documents_by_id[setup_id] = str(path.relative_to(root))

    catalog_set = set(catalog_names)
    covered_names = sorted(
        name
        for name, entry in registry_by_name.items()
        if name in catalog_set and entry["setupId"] in documents_by_id
    )
    missing_names = sorted(catalog_set - set(covered_names))
    unknown_registry_names = sorted(set(registry_by_name) - catalog_set)
    missing_documents = sorted(set(registry_by_id) - set(documents_by_id))
    orphan_documents = sorted(set(documents_by_id) - set(registry_by_id))
    inconsistencies = (
        duplicate_registry_names
        + duplicate_registry_ids
        + duplicate_document_ids
        + unknown_registry_names
        + missing_documents
        + orphan_documents
        + unreviewed_documents
    )
    coverage = round((len(covered_names) / len(catalog_names)) * 100, 2)
    complete = not missing_names and not inconsistencies
    return {
        "schemaVersion": 1,
        "status": "complete" if complete else "incomplete",
        "setupVersion": registry.get("setupVersion"),
        "catalogEntries": len(catalog_names),
        "coveredEntries": len(covered_names),
        "missingEntries": len(missing_names),
        "coveragePercent": coverage,
        "coveredCatalogNames": covered_names,
        "missingCatalogNames": missing_names,
        "integrity": {
            "duplicateRegistryNames": sorted(set(duplicate_registry_names)),
            "duplicateRegistryIds": sorted(set(duplicate_registry_ids)),
            "duplicateDocumentIds": sorted(set(duplicate_document_ids)),
            "unknownRegistryNames": unknown_registry_names,
            "missingDocuments": missing_documents,
            "orphanDocuments": orphan_documents,
            "unreviewedDocuments": sorted(set(unreviewed_documents)),
        },
    }


def evaluate_baseline(report: dict[str, Any], baseline: dict[str, Any]) -> list[str]:
    if baseline.get("schemaVersion") != 1:
        return ["coverage-baseline.json possui schemaVersion incompatível"]
    required = {
        "minimumCoveredEntries": int,
        "maximumMissingEntries": int,
        "minimumCoveragePercent": (int, float),
    }
    errors: list[str] = []
    for field, expected_type in required.items():
        if not isinstance(baseline.get(field), expected_type):
            errors.append(f"coverage-baseline.json possui {field} inválido")
    if errors:
        return errors
    if report["coveredEntries"] < baseline["minimumCoveredEntries"]:
        errors.append("a quantidade de entradas cobertas regrediu")
    if report["missingEntries"] > baseline["maximumMissingEntries"]:
        errors.append("uma nova entrada foi adicionada sem conhecimento canônico")
    if report["coveragePercent"] < baseline["minimumCoveragePercent"]:
        errors.append("o percentual de cobertura regrediu")
    return errors


def main() -> int:
    default_root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=default_root)
    parser.add_argument(
        "--catalog",
        type=Path,
        default=default_root.parent / "setupmno-control" / "catalog.json",
    )
    parser.add_argument(
        "--registry",
        type=Path,
        default=default_root / "registry" / "setups.json",
    )
    parser.add_argument(
        "--baseline",
        type=Path,
        default=default_root / "coverage-baseline.json",
    )
    parser.add_argument(
        "--enforce-baseline",
        action="store_true",
        help="bloqueia regressão ou nova entrada sem conhecimento",
    )
    parser.add_argument(
        "--require-complete",
        action="store_true",
        help="retorna código 3 enquanto alguma entrada do catálogo estiver sem documento",
    )
    arguments = parser.parse_args()
    try:
        report = build_report(arguments.catalog, arguments.registry, arguments.root)
        baseline = load_json(arguments.baseline)
        baseline_errors = evaluate_baseline(report, baseline)
        report["baseline"] = {
            "release": baseline.get("baselineRelease"),
            "passed": not baseline_errors,
            "errors": baseline_errors,
        }
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(json.dumps({"status": "invalid", "error": str(error)}, ensure_ascii=False))
        return 2
    print(json.dumps(report, ensure_ascii=False, sort_keys=True))
    if arguments.require_complete and report["status"] != "complete":
        return 3
    if arguments.enforce_baseline and report["baseline"]["errors"]:
        return 4
    return 0


if __name__ == "__main__":
    sys.exit(main())
