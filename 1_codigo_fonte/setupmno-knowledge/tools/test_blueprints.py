#!/usr/bin/python3
"""Testes da fábrica canônica de Blueprints MNO."""

from __future__ import annotations

import copy
import io
import json
import tempfile
import unittest
import zipfile
from pathlib import Path

from blueprint_factory import (
    BLUEPRINT_FACTORY_VERSION,
    SECRET_PATTERNS,
    build_blueprint_package,
    collect_source_files,
    load_blueprints,
    validate_manifest,
)


ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT.parent / "setupmno-control" / "catalog.json"
SETUP_VERSION = "6.0.0"


class BlueprintFactoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
        cls.catalog_by_name = {entry["name"]: entry for entry in cls.catalog}

    def test_complete_example_factory_passes(self) -> None:
        records = load_blueprints(ROOT, CATALOG, SETUP_VERSION)
        self.assertEqual(len(records), 5)
        self.assertTrue(all(record.manifest["status"] == "example" for record in records))
        self.assertTrue(all(record.manifest["fictitious"] for record in records))
        self.assertTrue(all(not record.manifest["deployable"] for record in records))

    def test_bundles_are_reproducible_and_regular(self) -> None:
        first_files, first_summary = build_blueprint_package(ROOT, CATALOG, SETUP_VERSION)
        second_files, second_summary = build_blueprint_package(ROOT, CATALOG, SETUP_VERSION)
        self.assertEqual(first_files, second_files)
        self.assertEqual(first_summary, second_summary)
        self.assertEqual(first_summary["blueprintEntries"], 5)
        self.assertEqual(first_summary["blueprintBundleEntries"], 5)
        self.assertEqual(first_summary["blueprintFactoryVersion"], BLUEPRINT_FACTORY_VERSION)
        bundles = {
            path: data
            for path, data in first_files.items()
            if path.startswith("blueprints/bundles/")
        }
        self.assertEqual(len(bundles), 5)
        for path, data in bundles.items():
            with self.subTest(path=path), zipfile.ZipFile(io.BytesIO(data)) as archive:
                self.assertGreaterEqual(len(archive.infolist()), 2)
                for info in archive.infolist():
                    self.assertEqual(info.date_time, (1980, 1, 1, 0, 0, 0))
                    self.assertFalse(info.is_dir())
                    self.assertNotIn("..", Path(info.filename).parts)
                    self.assertEqual((info.external_attr >> 16) & 0o777, 0o644)

    def test_example_links_use_reserved_invalid_domain(self) -> None:
        for record in load_blueprints(ROOT, CATALOG, SETUP_VERSION):
            for media in record.manifest["media"]:
                with self.subTest(blueprint=record.manifest["blueprintId"]):
                    self.assertIn(".invalid/", media["url"])

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


if __name__ == "__main__":
    unittest.main()
