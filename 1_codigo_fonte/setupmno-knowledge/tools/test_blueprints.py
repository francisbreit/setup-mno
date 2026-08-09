#!/usr/bin/python3
"""Testes da fábrica canônica de Blueprints MNO."""

from __future__ import annotations

import copy
import hashlib
import io
import json
import tempfile
import unittest
import zipfile
from pathlib import Path

from blueprint_factory import (
    BLUEPRINT_FACTORY_VERSION,
    SECRET_PATTERNS,
    build_editorial_projection,
    build_blueprint_package,
    collect_source_files,
    load_blueprints,
    validate_editorial_evidence_files,
    validate_manifest,
)


ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT.parent / "setupmno-control" / "catalog.json"
SETUP_VERSION = "7.7.47"


class BlueprintFactoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
        cls.catalog_by_name = {entry["name"]: entry for entry in cls.catalog}

    def test_reviewed_beta_guides_pass_factory(self) -> None:
        records = load_blueprints(ROOT, CATALOG, SETUP_VERSION)
        self.assertEqual(len(records), 5)
        self.assertTrue(all(record.manifest["status"] == "reviewed" for record in records))
        self.assertTrue(all(not record.manifest["fictitious"] for record in records))
        self.assertTrue(all(not record.manifest["deployable"] for record in records))
        self.assertTrue(all(record.manifest["schemaVersion"] == 2 for record in records))
        self.assertTrue(
            all(record.manifest["editorial"]["currentStage"] == "reviewed" for record in records)
        )

    def test_bundles_are_reproducible_and_regular(self) -> None:
        first_files, first_summary = build_blueprint_package(ROOT, CATALOG, SETUP_VERSION)
        second_files, second_summary = build_blueprint_package(ROOT, CATALOG, SETUP_VERSION)
        self.assertEqual(first_files, second_files)
        self.assertEqual(first_summary, second_summary)
        self.assertEqual(first_summary["blueprintEntries"], 5)
        self.assertEqual(first_summary["blueprintBundleEntries"], 5)
        self.assertEqual(first_summary["blueprintFactoryVersion"], BLUEPRINT_FACTORY_VERSION)
        index = json.loads(first_files["blueprints/index.json"])
        self.assertTrue(
            all(
                entry["resourceProfile"]["recommendedRamGB"]
                >= entry["resourceProfile"]["minimumRamGB"]
                for entry in index["entries"]
            )
        )
        for entry in index["entries"]:
            editorial = entry["editorial"]
            self.assertEqual(editorial["passedGates"], 9)
            self.assertEqual(editorial["totalGates"], 11)
            self.assertFalse(editorial["promotionReady"])
            self.assertEqual(editorial["versionSeal"]["algorithm"], "sha256")
            self.assertEqual(len(editorial["versionSeal"]["manifestSHA256"]), 64)
            self.assertEqual(len(editorial["versionSeal"]["payloadSHA256"]), 64)
            self.assertNotIn('"path"', json.dumps(editorial))
        bundles = {
            path: data
            for path, data in first_files.items()
            if path.startswith("blueprints/bundles/")
        }
        self.assertEqual(len(bundles), 5)
        for path, data in bundles.items():
            with self.subTest(path=path), zipfile.ZipFile(io.BytesIO(data)) as archive:
                self.assertGreaterEqual(len(archive.infolist()), 3)
                self.assertTrue(
                    any(info.filename.endswith("/knowledge.md") for info in archive.infolist())
                )
                for info in archive.infolist():
                    self.assertEqual(info.date_time, (1980, 1, 1, 0, 0, 0))
                    self.assertFalse(info.is_dir())
                    self.assertNotIn("..", Path(info.filename).parts)
                    self.assertEqual((info.external_attr >> 16) & 0o777, 0o644)

    def test_pending_media_does_not_invent_links(self) -> None:
        for record in load_blueprints(ROOT, CATALOG, SETUP_VERSION):
            for media in record.manifest["media"]:
                with self.subTest(blueprint=record.manifest["blueprintId"]):
                    self.assertEqual(media["status"], "pending")
                    self.assertIsNone(media["url"])

    def test_external_url_in_fictitious_document_is_blocked(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            readme = Path(temporary) / "README.md"
            readme.write_text(
                "# Exemplo\n\nConsulte https://example.com/documentacao\n",
                encoding="utf-8",
            )
            _, errors = collect_source_files(Path(temporary), fictitious=True)
        self.assertTrue(any("domínio reservado" in error for error in errors), errors)

    def test_unknown_catalog_component_is_blocked(self) -> None:
        manifest = copy.deepcopy(
            load_blueprints(ROOT, CATALOG, SETUP_VERSION)[0].manifest
        )
        manifest["components"][0]["catalogName"] = "SETUP QUE NÃO EXISTE"
        errors = validate_manifest(
            manifest,
            manifest["blueprintId"],
            self.catalog_by_name,
            SETUP_VERSION,
        )
        self.assertTrue(any("catálogo canônico" in error for error in errors), errors)

    def test_incompatible_required_architecture_is_blocked(self) -> None:
        manifest = copy.deepcopy(
            load_blueprints(ROOT, CATALOG, SETUP_VERSION)[0].manifest
        )
        catalog = copy.deepcopy(self.catalog_by_name)
        component_name = manifest["components"][0]["catalogName"]
        catalog[component_name]["arch"] = "x86"
        errors = validate_manifest(
            manifest,
            manifest["blueprintId"],
            catalog,
            SETUP_VERSION,
        )
        self.assertTrue(any("incompatível" in error for error in errors), errors)

    def test_secret_pattern_is_blocked(self) -> None:
        fake_secret = "api_key=" + "EXEMPLOPROIBIDO" * 2
        self.assertIsNotNone(
            SECRET_PATTERNS["atribuição de segredo"].search(fake_secret)
        )

    def test_reviewed_status_requires_approved_review(self) -> None:
        manifest = copy.deepcopy(
            load_blueprints(ROOT, CATALOG, SETUP_VERSION)[0].manifest
        )
        manifest["status"] = "reviewed"
        manifest["fictitious"] = False
        manifest["editorial"]["currentStage"] = "reviewed"
        manifest["editorial"]["history"] = [
            {
                "stage": "draft",
                "changedAt": "2026-07-29",
                "actor": "Editor Setup MNO",
                "note": "Rascunho submetido ao fluxo editorial.",
            },
            {
                "stage": "reviewed",
                "changedAt": "2026-07-30",
                "actor": "Revisor Setup MNO",
                "note": "Revisão estrutural concluída sem promoção.",
            },
        ]
        manifest["editorial"]["review"] = {
            "decision": "pending",
            "reviewedAt": None,
            "reviewedBy": None,
            "notes": "Revisão humana ainda não concluída.",
        }
        errors = validate_manifest(
            manifest,
            manifest["blueprintId"],
            self.catalog_by_name,
            SETUP_VERSION,
        )
        self.assertTrue(any("revisão aprovada" in error for error in errors), errors)

    def test_homologated_status_cannot_skip_reviewed_transition(self) -> None:
        manifest = copy.deepcopy(
            load_blueprints(ROOT, CATALOG, SETUP_VERSION)[0].manifest
        )
        manifest["status"] = "homologated"
        manifest["fictitious"] = False
        manifest["deployable"] = True
        manifest["validation"]["homologatedAt"] = "2026-07-31"
        manifest["editorial"]["currentStage"] = "homologated"
        manifest["editorial"]["history"] = [
            {
                "stage": "draft",
                "changedAt": "2026-07-29",
                "actor": "Editor Setup MNO",
                "note": "Rascunho submetido ao fluxo editorial.",
            },
            {
                "stage": "homologated",
                "changedAt": "2026-07-31",
                "actor": "Homologador Setup MNO",
                "note": "Tentativa inválida de pular a revisão.",
            },
        ]
        manifest["editorial"]["review"] = {
            "decision": "approved",
            "reviewedAt": "2026-07-30",
            "reviewedBy": "Revisor Setup MNO",
            "notes": "Revisão aprovada para testar o gate de transição.",
        }
        errors = validate_manifest(
            manifest,
            manifest["blueprintId"],
            self.catalog_by_name,
            SETUP_VERSION,
        )
        self.assertTrue(any("transição permitida" in error for error in errors), errors)

    def test_homologated_status_requires_isolated_evidence(self) -> None:
        manifest = copy.deepcopy(
            load_blueprints(ROOT, CATALOG, SETUP_VERSION)[0].manifest
        )
        manifest["status"] = "homologated"
        manifest["fictitious"] = False
        manifest["deployable"] = True
        manifest["validation"]["homologatedAt"] = "2026-07-31"
        manifest["editorial"]["currentStage"] = "homologated"
        manifest["editorial"]["history"] = [
            {
                "stage": "draft",
                "changedAt": "2026-07-29",
                "actor": "Editor Setup MNO",
                "note": "Rascunho submetido ao fluxo editorial.",
            },
            {
                "stage": "reviewed",
                "changedAt": "2026-07-30",
                "actor": "Revisor Setup MNO",
                "note": "Revisão editorial aprovada para homologação.",
            },
            {
                "stage": "homologated",
                "changedAt": "2026-07-31",
                "actor": "Homologador Setup MNO",
                "note": "Promoção solicitada sem evidências suficientes.",
            },
        ]
        manifest["editorial"]["review"] = {
            "decision": "approved",
            "reviewedAt": "2026-07-30",
            "reviewedBy": "Revisor Setup MNO",
            "notes": "Revisão aprovada para testar evidências obrigatórias.",
        }
        errors = validate_manifest(
            manifest,
            manifest["blueprintId"],
            self.catalog_by_name,
            SETUP_VERSION,
        )
        self.assertTrue(any("ambiente isolado" in error for error in errors), errors)
        self.assertTrue(any("relatório" in error for error in errors), errors)

    def test_forged_evidence_hash_is_blocked(self) -> None:
        editorial = {
            "homologation": {
                "evidence": [
                    {
                        "path": "evidence/test-report.md",
                        "sha256": "0" * 64,
                    }
                ]
            }
        }
        errors = validate_editorial_evidence_files(
            editorial,
            {"evidence/test-report.md": b"evidencia real\n"},
        )
        self.assertTrue(any("hash da evidência diverge" in error for error in errors), errors)

    def test_complete_homologated_flow_passes_with_isolated_evidence(self) -> None:
        manifest = copy.deepcopy(
            load_blueprints(ROOT, CATALOG, SETUP_VERSION)[0].manifest
        )
        manifest["status"] = "homologated"
        manifest["fictitious"] = False
        manifest["deployable"] = True
        manifest["validation"]["homologatedAt"] = "2026-07-31"
        manifest["editorial"] = {
            "currentStage": "homologated",
            "history": [
                {
                    "stage": "draft",
                    "changedAt": "2026-07-29",
                    "actor": "Editor Setup MNO",
                    "note": "Rascunho submetido ao fluxo editorial canônico.",
                },
                {
                    "stage": "reviewed",
                    "changedAt": "2026-07-30",
                    "actor": "Revisor Setup MNO",
                    "note": "Revisão estrutural e de segurança aprovada.",
                },
                {
                    "stage": "homologated",
                    "changedAt": "2026-07-31",
                    "actor": "Homologador Setup MNO",
                    "note": "Testes isolados concluídos nas duas arquiteturas.",
                },
            ],
            "review": {
                "decision": "approved",
                "reviewedAt": "2026-07-30",
                "reviewedBy": "Revisor Setup MNO",
                "notes": "Contrato, segurança e plano de rollback aprovados.",
            },
            "homologation": {
                "environment": "isolated-temporary",
                "testedAt": "2026-07-31",
                "architectures": ["amd64", "arm64"],
                "evidence": [],
            },
        }
        evidence_files = {
            "evidence/test-amd64.md": b"smoke test isolado amd64: aprovado\n",
            "evidence/test-arm64.md": b"smoke test isolado arm64: aprovado\n",
            "evidence/security.md": b"revisao de seguranca: aprovada\n",
            "evidence/rollback.md": b"rollback isolado: aprovado\n",
        }
        evidence_specs = [
            ("test-amd64", "test-report", "Relatório de teste amd64", "evidence/test-amd64.md", "amd64"),
            ("test-arm64", "test-report", "Relatório de teste arm64", "evidence/test-arm64.md", "arm64"),
            ("security-review", "security-review", "Revisão de segurança", "evidence/security.md", "all"),
            ("rollback-test", "rollback-test", "Teste isolado de rollback", "evidence/rollback.md", "all"),
        ]
        for evidence_id, evidence_type, title, path, architecture in evidence_specs:
            manifest["editorial"]["homologation"]["evidence"].append(
                {
                    "evidenceId": evidence_id,
                    "type": evidence_type,
                    "title": title,
                    "path": path,
                    "sha256": hashlib.sha256(evidence_files[path]).hexdigest(),
                    "verifiedAt": "2026-07-31",
                    "architecture": architecture,
                }
            )

        errors = validate_manifest(
            manifest,
            manifest["blueprintId"],
            self.catalog_by_name,
            SETUP_VERSION,
        )
        errors.extend(validate_editorial_evidence_files(manifest["editorial"], evidence_files))
        self.assertEqual(errors, [])
        projection = build_editorial_projection(manifest, "a" * 64)
        self.assertEqual(projection["passedGates"], 11)
        self.assertEqual(projection["totalGates"], 11)
        self.assertTrue(projection["promotionReady"])
        self.assertNotIn('"path"', json.dumps(projection))


if __name__ == "__main__":
    unittest.main()
