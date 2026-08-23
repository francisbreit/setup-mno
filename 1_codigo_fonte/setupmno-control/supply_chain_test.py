#!/usr/bin/env python3
from __future__ import annotations

import json
import tempfile
import unittest
from argparse import Namespace
from pathlib import Path

import supply_chain


class SupplyChainTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        (self.root / "x86/SetupLowCodeMno").mkdir(parents=True)
        (self.root / "arm/SetupLowCodeMno").mkdir(parents=True)
        self.artifact = self.root / "catalog.json"
        self.artifact.write_text("[]\n", encoding="utf-8")
        for arch in ("x86", "arm"):
            (self.root / arch / "SetupLowCodeMno/example.sh").write_text(
                'APP_IMAGE="example/app:1.2.3"\n'
                'FALLBACK_IMAGE="${FALLBACK_IMAGE:-example/fallback@sha256:' + "a" * 64 + '}"\n'
                'image: ${UNRESOLVED_IMAGE}\n',
                encoding="utf-8",
            )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def generate(self, architecture: str = "amd64") -> Path:
        target = self.root / f"result-{architecture}"
        supply_chain.generate(Namespace(
            source_root=self.root,
            target=target,
            architecture=architecture,
            setup_version="7.30.0",
            artifact=[("catalog.json", str(self.artifact))],
        ))
        return target

    def test_deterministic_generation_and_validation(self) -> None:
        first = self.generate()
        before = {path.name: path.read_bytes() for path in first.iterdir()}
        supply_chain.generate(Namespace(
            source_root=self.root,
            target=first,
            architecture="amd64",
            setup_version="7.30.0",
            artifact=[("catalog.json", str(self.artifact))],
        ))
        after = {path.name: path.read_bytes() for path in first.iterdir()}
        self.assertEqual(before, after)
        manifest = supply_chain.validate_directory(first, "7.30.0", "amd64")
        self.assertEqual(manifest["inventory"]["digestPinnedImages"], 1)
        self.assertEqual(manifest["inventory"]["imageReferences"], 2)
        self.assertEqual(manifest["inventory"]["unresolvedExpressions"], 1)

    def test_tamper_is_rejected(self) -> None:
        target = self.generate()
        inventory_path = target / "image-inventory.json"
        inventory = json.loads(inventory_path.read_text(encoding="utf-8"))
        inventory["counts"]["references"] += 1
        inventory_path.write_text(json.dumps(inventory), encoding="utf-8")
        with self.assertRaises(supply_chain.SupplyChainError):
            supply_chain.validate_directory(target)

    def test_symlink_is_rejected(self) -> None:
        target = self.generate("arm64")
        sbom = target / "sbom.cdx.json"
        backup = target / "sbom.backup"
        sbom.rename(backup)
        sbom.symlink_to(backup.name)
        with self.assertRaises(supply_chain.SupplyChainError):
            supply_chain.validate_directory(target)


if __name__ == "__main__":
    unittest.main()
