#!/usr/bin/python3
"""Testes da fábrica canônica de conhecimento do Assistente MNO."""

from __future__ import annotations

import copy
import hashlib
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
    validate_registry,
)
from generate_package import (
    MAX_CHUNK_CHARACTERS,
    RETRIEVAL_VERSION,
    split_section,
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
        self.assertEqual(report["documents"], 34)
        self.assertEqual(report["setups"], 20)
        self.assertEqual(report["types"]["blueprint"], 5)

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

    def test_ambiguous_setup_alias_is_blocked(self) -> None:
        registry = copy.deepcopy(load_json(ROOT / "registry" / "setups.json"))
        catalog = load_json(CATALOG)
        registry["setups"][1]["aliases"][0] = registry["setups"][0]["aliases"][0]
        errors = validate_registry(
            registry,
            {entry["name"] for entry in catalog},
            SOURCE_ROOT,
        )
        self.assertTrue(
            any("alias ambíguo" in error for error in errors),
            errors,
        )

    def test_chunking_is_bounded_and_deterministic(self) -> None:
        paragraph = "palavra " * 180
        content = "\n\n".join([paragraph.strip(), paragraph.strip()])
        first = split_section(content)
        second = split_section(content)
        self.assertEqual(first, second)
        self.assertGreater(len(first), 1)
        self.assertTrue(all(len(chunk) <= MAX_CHUNK_CHARACTERS for chunk in first))

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
                        "3.3.1",
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
                    index = json.load(package.extractfile("index.json"))
                    legacy_index = json.load(package.extractfile("index-v1.json"))
                    self.assertEqual(index["schemaVersion"], 2)
                    self.assertEqual(index["retrievalVersion"], RETRIEVAL_VERSION)
                    self.assertEqual(index["synonyms"]["amd64"], ["x86", "x86_64"])
                    self.assertEqual(index["synonyms"]["arm64"], ["arm", "aarch64"])
                    self.assertEqual(index["chunkCount"], len(index["chunks"]))
                    self.assertGreater(index["chunkCount"], 29)
                    self.assertEqual(legacy_index["schemaVersion"], 1)
                    self.assertEqual(len(legacy_index["entries"]), 34)
                    blueprint_index = json.load(
                        package.extractfile("blueprints/index.json")
                    )
                    self.assertEqual(blueprint_index["schemaVersion"], 1)
                    self.assertEqual(blueprint_index["blueprintCount"], 5)
                    self.assertEqual(blueprint_index["statuses"], {"example": 5})
                    self.assertTrue(
                        all(
                            entry["fictitious"] and not entry["deployable"]
                            for entry in blueprint_index["entries"]
                        )
                    )
                    blueprint_documents = [
                        entry
                        for entry in legacy_index["entries"]
                        if entry["documentType"] == "blueprint"
                    ]
                    self.assertEqual(len(blueprint_documents), 5)
                    self.assertTrue(
                        all(
                            entry["fictitious"]
                            and not entry["deployable"]
                            and entry["status"] == "reviewed"
                            and entry["blueprintId"]
                            for entry in blueprint_documents
                        )
                    )
                    chunk_ids: set[str] = set()
                    for chunk in index["chunks"]:
                        self.assertNotIn(chunk["chunkId"], chunk_ids)
                        chunk_ids.add(chunk["chunkId"])
                        self.assertLessEqual(
                            len(chunk["content"]),
                            MAX_CHUNK_CHARACTERS,
                        )
                        self.assertEqual(
                            chunk["contentSHA256"],
                            hashlib.sha256(
                                chunk["content"].encode("utf-8")
                            ).hexdigest(),
                        )
                        self.assertEqual(
                            set(chunk["fieldLengths"]),
                            {"aliases", "content", "heading", "tags", "title"},
                        )
                        self.assertEqual(
                            set(chunk["fieldTermFrequencies"]),
                            {"aliases", "content", "heading", "tags", "title"},
                        )
            self.assertEqual(archives[0], archives[1])
            self.assertEqual(manifests[0], manifests[1])
            self.assertEqual(manifests[0]["documentEntries"], 34)
            self.assertEqual(manifests[0]["setupEntries"], 20)
            self.assertEqual(manifests[0]["infrastructureEntries"], 9)
            self.assertEqual(manifests[0]["blueprintSchemaVersion"], 1)
            self.assertEqual(manifests[0]["blueprintFactoryVersion"], "1.1.0")
            self.assertEqual(manifests[0]["blueprintEntries"], 5)
            self.assertEqual(manifests[0]["blueprintBundleEntries"], 5)
            self.assertEqual(manifests[0]["blueprintKnowledgeEntries"], 5)
            self.assertEqual(manifests[0]["blueprintFixtureEntries"], 5)
            self.assertEqual(manifests[0]["indexSchemaVersion"], 2)
            self.assertEqual(
                manifests[0]["retrievalVersion"],
                RETRIEVAL_VERSION,
            )
            self.assertGreater(manifests[0]["chunkEntries"], 29)


if __name__ == "__main__":
    unittest.main()
