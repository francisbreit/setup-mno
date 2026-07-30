#!/usr/bin/python3
"""Testes da fábrica canônica de conhecimento do Assistente MNO."""

from __future__ import annotations

import json
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path

from lint_knowledge import (
    KnowledgeDocument,
    SECRET_PATTERNS,
    load_json,
    parse_document,
    validate_document,
)


ROOT = Path(__file__).resolve().parent.parent
SOURCE_ROOT = ROOT.parent
CATALOG = SOURCE_ROOT / "setupmno-control" / "catalog.json"
LINTER = ROOT / "tools" / "lint_knowledge.py"
GENERATOR = ROOT / "tools" / "generate_package.py"


def run_linter(*arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            "-B",
            str(LINTER),
            "--root",
            str(ROOT),
            "--catalog",
            str(CATALOG),
            *arguments,
        ],
        check=False,
        capture_output=True,
        text=True,
    )


class KnowledgeFactoryTests(unittest.TestCase):
    def test_complete_base_passes_linter(self) -> None:
        result = run_linter()
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["documents"], 29)
        self.assertEqual(report["setups"], 20)

    def test_all_pilot_setups_resolve_on_both_architectures(self) -> None:
        registry = load_json(ROOT / "registry" / "setups.json")
        for entry in registry["setups"]:
            for architecture in entry["architectures"]:
                with self.subTest(
                    setup_id=entry["setupId"],
                    architecture=architecture,
                ):
                    result = run_linter(
                        "resolve",
                        "--setup-id",
                        entry["setupId"],
                        "--setup-version",
                        registry["setupVersion"],
                        "--architecture",
                        architecture,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    resolved = json.loads(result.stdout)
                    self.assertGreater(len(resolved["documents"]), 0)

    def test_incompatible_version_does_not_resolve(self) -> None:
        result = run_linter(
            "resolve",
            "--setup-id",
            "n8n-main",
            "--setup-version",
            "4.93.3",
            "--architecture",
            "amd64",
        )
        self.assertEqual(result.returncode, 3)
        self.assertEqual(json.loads(result.stdout)["documents"], [])

    def test_content_tampering_breaks_hash(self) -> None:
        taxonomy = load_json(ROOT / "schema" / "taxonomy.json")
        registry = load_json(ROOT / "registry" / "setups.json")
        catalog = load_json(CATALOG)
        registry_by_id = {
            entry["setupId"]: entry
            for entry in registry["setups"]
        }
        catalog_names = {entry["name"] for entry in catalog}
        original = parse_document(ROOT / "setups" / "n8n-main" / "overview.md")
        tampered = KnowledgeDocument(
            path=original.path,
            metadata=original.metadata,
            body=original.body + "\n\nConteúdo adulterado.",
        )
        errors = validate_document(
            tampered,
            taxonomy,
            registry_by_id,
            catalog_names,
            SOURCE_ROOT,
        )
        self.assertTrue(
            any("contentSHA256 divergente" in error for error in errors),
            errors,
        )

    def test_secret_pattern_is_blocked(self) -> None:
        fake_key = "sk-" + "TESTONLY" * 3
        self.assertIsNotNone(SECRET_PATTERNS["chave OpenAI"].search(fake_key))

    def test_deprecated_is_not_a_normal_retrieval_status(self) -> None:
        taxonomy = load_json(ROOT / "schema" / "taxonomy.json")
        self.assertNotIn("deprecated", taxonomy["normalRetrievalStatuses"])
        self.assertNotIn("draft", taxonomy["normalRetrievalStatuses"])

    def test_generated_package_is_reproducible_and_regular(self) -> None:
        registry = load_json(ROOT / "registry" / "setups.json")
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            archives: list[bytes] = []
            manifests: list[dict[str, object]] = []
            for output in (first, second):
                result = subprocess.run(
                    [
                        sys.executable,
                        "-B",
                        str(GENERATOR),
                        "--root",
                        str(ROOT),
                        "--catalog",
                        str(CATALOG),
                        "--output",
                        output,
                        "--setup-version",
                        registry["setupVersion"],
                        "--control-version",
                        "1.2.0",
                    ],
                    check=False,
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                archives.append(
                    (Path(output) / "knowledge-package.tar.gz").read_bytes()
                )
                manifests.append(
                    load_json(Path(output) / "manifest.json")
                )
                with tarfile.open(
                    Path(output) / "knowledge-package.tar.gz",
                    mode="r:gz",
                ) as package:
                    self.assertTrue(package.getmembers())
                    self.assertTrue(all(member.isfile() for member in package.getmembers()))
            self.assertEqual(archives[0], archives[1])
            self.assertEqual(manifests[0], manifests[1])
            self.assertEqual(manifests[0]["documentEntries"], 29)
            self.assertEqual(manifests[0]["setupEntries"], 20)
            self.assertEqual(manifests[0]["infrastructureEntries"], 9)


if __name__ == "__main__":
    unittest.main()
