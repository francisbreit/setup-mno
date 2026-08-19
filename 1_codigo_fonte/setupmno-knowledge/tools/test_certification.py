#!/usr/bin/python3
"""Regressões da esteira oficial e transacional do selo de homologação."""

from __future__ import annotations

import json
import hashlib
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path

from generate_homologation_package import generate
from lint_knowledge import parse_document


TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parent
SETUP_VERSION = json.loads((ROOT / "registry" / "setups.json").read_text(encoding="utf-8"))["setupVersion"]
CHECKS = ("deploy", "convergence", "health", "persistence", "restart", "update", "backup", "restore", "cleanup")
IMAGE = "deluan/navidrome@sha256:9012939114fbb1bb641b81cf96dec5ded15f0aafefe8d47a511d7cb919658e40"


class CertificationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="setupmno-certification-test-")
        self.base = Path(self.temporary.name)
        self.source = self.base / "source"
        self.root = self.source / "setupmno-knowledge"
        shutil.copytree(ROOT, self.root, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
        (self.source / "setupmno-control").mkdir()
        shutil.copy2(ROOT.parent / "setupmno-control" / "catalog.json", self.source / "setupmno-control" / "catalog.json")
        for architecture in ("x86", "arm"):
            target = self.source / architecture / "SetupLowCodeMno"
            target.mkdir(parents=True)
            shutil.copy2(ROOT.parent / architecture / "SetupLowCodeMno" / "navidrome.sh", target / "navidrome.sh")
        evidence_dir = self.root / "evidence" / "navidrome"
        if evidence_dir.exists():
            shutil.rmtree(evidence_dir)
        governance_path = self.root / "registry" / "governance.json"
        governance = json.loads(governance_path.read_text(encoding="utf-8"))
        governance.get("promotions", {}).pop("navidrome", None)
        governance_path.write_text(json.dumps(governance, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        self.prepare_document()
        self.package = self.base / "runner-package"
        generate(ROOT, self.package, SETUP_VERSION)
        self.packs = [self.create_pack("amd64", "2026-08-19T10:00:00Z"), self.create_pack("arm64", "2026-08-19T10:01:00Z")]

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def prepare_document(self) -> None:
        path = self.root / "setups" / "navidrome" / "overview.md"
        text = path.read_text(encoding="utf-8")
        lines = text.splitlines()
        closing = lines.index("---", 1)
        metadata = json.loads("\n".join(lines[1:closing]))
        metadata["status"] = "homologated"
        metadata["updatedAt"] = "2026-08-19"
        metadata["homologation"] = {
            "verifiedAt": "2026-08-19",
            "verifiedPorts": [4533],
            "verifiedImages": [IMAGE],
        }
        path.write_text(
            "---\n" + json.dumps(metadata, ensure_ascii=False, indent=2) + "\n---\n" + "\n".join(lines[closing + 1:]) + "\n",
            encoding="utf-8",
        )

    def run_runner(self, *arguments: str, expected: int = 0) -> subprocess.CompletedProcess[str]:
        result = subprocess.run(
            [sys.executable, str(self.package / "homologation_runner.py"), "--package-dir", str(self.package), *arguments],
            check=False, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        self.assertEqual(result.returncode, expected, result.stderr)
        return result

    def create_pack(self, architecture: str, created_at: str) -> Path:
        runs = self.base / f"runs-{architecture}"
        session = Path(self.run_runner(
            "init", "--setup-id", "navidrome", "--architecture", architecture,
            "--platform", "linux-vps", "--output-dir", str(runs),
            "--created-at", created_at, "--skip-docker-preflight",
        ).stdout.strip())
        for check in CHECKS:
            self.run_runner(
                "record", "--session", str(session), "--check", check,
                "--status", "passed", "--evidence", f"Check {check} aprovado no laboratório isolado.",
            )
        bundle = self.base / f"{architecture}-candidate.tar.gz"
        decision = self.base / f"{architecture}-decision.json"
        evidence = self.base / f"{architecture}-evidence.json"
        pack = self.base / f"{architecture}-review-pack.tar.gz"
        self.run_runner(
            "finalize", "--session", str(session), "--image", IMAGE,
            "--tester", "Operador QA", "--output", str(bundle),
        )
        reviewed_at = "2026-08-19T11:00:00Z" if architecture == "amd64" else "2026-08-19T11:01:00Z"
        self.run_runner(
            "decide", "--bundle", str(bundle), "--reviewer", "Revisor MNO",
            "--decision", "approved", "--reason-code", "operational-evidence-accepted",
            "--reason", "Evidências completas conferidas pelo mantenedor.",
            "--reviewed-at", reviewed_at, "--decision-output", str(decision),
            "--evidence-output", str(evidence), "--review-pack-output", str(pack),
        )
        return pack

    def run_certifier(self, packs: list[Path] | None = None, *extra: str, expected: int = 0) -> subprocess.CompletedProcess[str]:
        selected = packs if packs is not None else self.packs
        command = [sys.executable, str(TOOLS / "certify_homologation.py")]
        for pack in selected:
            command.extend(["--pack", str(pack)])
        command.extend([
            "--root", str(self.root),
            "--catalog", str(self.source / "setupmno-control" / "catalog.json"),
            "--package-dir", str(self.package),
            "--maintainer", "Francis MNO",
            "--reason", "Cobertura completa aprovada para emissão do selo oficial.",
            "--issued-at", "2026-08-19T12:00:00Z",
            *extra,
        ])
        result = subprocess.run(command, check=False, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(result.returncode, expected, result.stderr)
        return result

    def runtime_release(self) -> Path:
        release = self.base / "release.json"
        manifest_data = (self.package / "manifest.json").read_bytes()
        catalog_data = (self.source / "setupmno-control" / "catalog.json").read_bytes()
        release.write_text(json.dumps({
            "schemaVersion": 1,
            "setupVersion": SETUP_VERSION,
            "catalogSHA256": hashlib.sha256(catalog_data).hexdigest(),
            "homologationPackageManifestSHA256": hashlib.sha256(manifest_data).hexdigest(),
        }), encoding="utf-8")
        return release

    def test_dry_run_does_not_mutate_and_apply_issues_seal(self) -> None:
        governance_path = self.root / "registry" / "governance.json"
        ledger_path = self.root / "registry" / "certification-ledger.json"
        quality_path = self.root / "registry" / "quality-report.json"
        before = {path: path.read_bytes() for path in (governance_path, ledger_path, quality_path)}
        preview = json.loads(self.run_certifier().stdout)
        self.assertEqual(preview["mode"], "dry-run")
        self.assertFalse(preview["officialSeal"])
        self.assertTrue(preview["gates"]["allArchitectures"])
        self.assertTrue(preview["gates"]["allNineChecks"])
        self.assertTrue(preview["gates"]["currentArtifacts"])
        self.assertTrue(preview["gates"]["documentHomologated"])
        self.assertFalse(preview["gates"]["knownIssues"])
        self.assertTrue(preview["gates"]["ledgerConsistent"])
        self.assertEqual(before, {path: path.read_bytes() for path in before})
        self.assertFalse((self.root / "certifications").exists())
        applied = json.loads(self.run_certifier(None, "--apply", "--confirm", preview["confirmationToken"]).stdout)
        self.assertTrue(applied["officialSeal"])
        self.assertTrue(applied["governanceUpdated"])
        seal = json.loads((self.root / applied["sealPath"]).read_text(encoding="utf-8"))
        self.assertTrue(seal["officialSeal"])
        self.assertFalse(seal["automaticPromotion"])
        self.assertEqual(seal["architectures"], ["amd64", "arm64"])
        governance = json.loads(governance_path.read_text(encoding="utf-8"))
        self.assertEqual(governance["promotions"]["navidrome"]["maturity"], "homologated")
        report = json.loads(quality_path.read_text(encoding="utf-8"))
        entry = next(item for item in report["entries"] if item["setupId"] == "navidrome")
        self.assertEqual(entry["maturity"], "homologated")
        repeated = self.run_certifier(None, "--apply", "--confirm", preview["confirmationToken"], expected=2)
        self.assertIn("já existe", repeated.stderr)

    def test_missing_architecture_is_blocked(self) -> None:
        result = self.run_certifier([self.packs[0]], expected=2)
        self.assertIn("cobertura arquitetural incompleta", result.stderr)
        self.assertFalse((self.root / "certifications").exists())

    def test_final_gate_failure_rolls_back_every_file(self) -> None:
        baseline_path = self.root / "quality-baseline.json"
        baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
        baseline["minimumHomologatedEntries"] = 2
        baseline_path.write_text(json.dumps(baseline, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        watched = [
            self.root / "registry" / "governance.json",
            self.root / "registry" / "certification-ledger.json",
            self.root / "registry" / "quality-report.json",
        ]
        before = {path: path.read_bytes() for path in watched}
        preview = json.loads(self.run_certifier().stdout)
        result = self.run_certifier(None, "--apply", "--confirm", preview["confirmationToken"], expected=2)
        self.assertIn("exit status 4", result.stderr)
        self.assertEqual(before, {path: path.read_bytes() for path in watched})
        self.assertFalse((self.root / "certifications").exists())
        self.assertFalse((self.root / "evidence" / "navidrome").exists())

    def test_runtime_attestation_and_export_release_pack(self) -> None:
        release = self.runtime_release()
        export_dir = self.base / "exports"
        preview = json.loads(self.run_certifier(
            None, "--runtime-release", str(release), "--export-dir", str(export_dir)
        ).stdout)
        applied = json.loads(self.run_certifier(
            None, "--runtime-release", str(release), "--export-dir", str(export_dir),
            "--apply", "--confirm", preview["confirmationToken"],
        ).stdout)
        package = Path(applied["exportPath"])
        self.assertTrue(package.is_file())
        with tarfile.open(package, "r:gz") as archive:
            manifest = json.load(archive.extractfile("manifest.json"))
        self.assertTrue(manifest["officialSeal"])
        self.assertFalse(manifest["automaticPublication"])
        self.assertTrue(manifest["requiresCanonicalImport"])

    def test_runtime_attestation_rejects_tampered_release(self) -> None:
        release = self.runtime_release()
        data = json.loads(release.read_text(encoding="utf-8"))
        data["catalogSHA256"] = "0" * 64
        release.write_text(json.dumps(data), encoding="utf-8")
        result = self.run_certifier(None, "--runtime-release", str(release), expected=2)
        self.assertIn("atestação runtime", result.stderr)

    def test_guided_document_preparation_requires_token(self) -> None:
        path = self.root / "setups" / "navidrome" / "overview.md"
        lines = path.read_text(encoding="utf-8").splitlines()
        closing = lines.index("---", 1)
        metadata = json.loads("\n".join(lines[1:closing]))
        metadata["status"] = "reviewed"
        path.write_text(
            "---\n" + json.dumps(metadata, ensure_ascii=False, indent=2) +
            "\n---\n" + "\n".join(lines[closing + 1:]) + "\n",
            encoding="utf-8",
        )
        command = [sys.executable, str(TOOLS / "prepare_homologation_document.py")]
        for pack in self.packs:
            command.extend(["--pack", str(pack)])
        command.extend(["--root", str(self.root), "--package-dir", str(self.package)])
        preview_result = subprocess.run(command, check=False, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(preview_result.returncode, 0, preview_result.stderr)
        preview = json.loads(preview_result.stdout)
        self.assertFalse(preview["documentPrepared"])
        wrong = subprocess.run(command + ["--apply", "--confirm", "ERRADO"], check=False, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(wrong.returncode, 2)
        applied_result = subprocess.run(
            command + ["--apply", "--confirm", preview["confirmationToken"]],
            check=False, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        self.assertEqual(applied_result.returncode, 0, applied_result.stderr)
        self.assertTrue(json.loads(applied_result.stdout)["documentPrepared"])
        self.assertEqual(parse_document(path).metadata["status"], "homologated")


if __name__ == "__main__":
    unittest.main()
