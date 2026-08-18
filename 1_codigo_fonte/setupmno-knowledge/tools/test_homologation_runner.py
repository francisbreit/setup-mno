#!/usr/bin/python3
"""Regressões do fluxo de evidência candidata do Homologation Runner."""

from __future__ import annotations

import json
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path

from generate_homologation_package import generate


TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parent
RUNNER_NAME = "homologation_runner.py"
CORE_CHECKS = ("deploy", "convergence", "health", "persistence", "restart", "cleanup")


class HomologationRunnerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="setupmno-runner-test-")
        self.base = Path(self.temporary.name)
        self.package = self.base / "package"
        setup_version = json.loads(
            (ROOT / "registry" / "setups.json").read_text(encoding="utf-8")
        )["setupVersion"]
        generate(ROOT, self.package, setup_version)
        self.runner = self.package / RUNNER_NAME

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def run_runner(self, *arguments: str, expected: int = 0) -> subprocess.CompletedProcess[str]:
        result = subprocess.run(
            [sys.executable, str(self.runner), "--package-dir", str(self.package), *arguments],
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        self.assertEqual(result.returncode, expected, result.stderr)
        return result

    def create_operational_session(self) -> Path:
        result = self.run_runner(
            "init",
            "--setup-id", "navidrome",
            "--architecture", "amd64",
            "--platform", "linux-vps",
            "--output-dir", str(self.base / "runs"),
            "--created-at", "2026-08-18T12:00:00Z",
            "--skip-docker-preflight",
        )
        session = Path(result.stdout.strip())
        self.assertTrue(session.is_file())
        for check in CORE_CHECKS:
            self.run_runner(
                "record",
                "--session", str(session),
                "--check", check,
                "--status", "passed",
                "--evidence", f"Check {check} confirmado no laboratório isolado.",
            )
        return session

    def test_candidate_is_pending_and_never_grants_seal(self) -> None:
        session = self.create_operational_session()
        output = self.base / "candidate.tar.gz"
        result = self.run_runner(
            "finalize",
            "--session", str(session),
            "--image", "example/navidrome@sha256:" + "a" * 64,
            "--tester", "Operador QA",
            "--output", str(output),
        )
        summary = json.loads(result.stdout)
        self.assertFalse(summary["officialSeal"])
        self.assertEqual(summary["status"], "pending-maintainer-review")
        verified = json.loads(self.run_runner("verify", "--bundle", str(output)).stdout)
        self.assertEqual(verified["result"], "candidate-operational")
        self.assertFalse(verified["officialSeal"])
        with tarfile.open(output, "r:gz") as archive:
            candidate = json.load(archive.extractfile("candidate.json"))
        self.assertEqual(candidate["submission"]["automaticPromotion"], False)
        self.assertEqual(candidate["submission"]["officialSeal"], False)

    def test_review_outputs_evidence_without_updating_governance(self) -> None:
        session = self.create_operational_session()
        bundle = self.base / "candidate.tar.gz"
        evidence = self.base / "evidence.json"
        self.run_runner(
            "finalize", "--session", str(session),
            "--image", "example/navidrome@sha256:" + "b" * 64,
            "--tester", "Operador QA", "--output", str(bundle),
        )
        result = self.run_runner(
            "review", "--bundle", str(bundle), "--reviewer", "Revisor MNO",
            "--reviewed-at", "2026-08-18", "--output", str(evidence),
        )
        summary = json.loads(result.stdout)
        self.assertFalse(summary["governanceUpdated"])
        self.assertFalse(summary["officialSeal"])
        reviewed = json.loads(evidence.read_text(encoding="utf-8"))
        self.assertEqual(reviewed["review"]["decision"], "approved")

    def test_sensitive_evidence_is_rejected(self) -> None:
        session = self.create_operational_session()
        result = self.run_runner(
            "record", "--session", str(session), "--check", "deploy",
            "--status", "passed", "--evidence", "Contato operador@example.com",
            expected=2,
        )
        self.assertIn("sensível", result.stderr)

    def test_tampered_package_is_rejected(self) -> None:
        registry = self.package / "runner-registry.json"
        registry.write_bytes(registry.read_bytes() + b" ")
        result = self.run_runner("list", expected=2)
        self.assertIn("integridade divergente", result.stderr)

    def test_tampered_bundle_is_rejected(self) -> None:
        session = self.create_operational_session()
        bundle = self.base / "candidate.tar.gz"
        self.run_runner(
            "finalize", "--session", str(session),
            "--image", "example/navidrome@sha256:" + "c" * 64,
            "--tester", "Operador QA", "--output", str(bundle),
        )
        data = bytearray(bundle.read_bytes())
        data[len(data) // 2] ^= 1
        bundle.write_bytes(data)
        result = self.run_runner("verify", "--bundle", str(bundle), expected=2)
        self.assertIn("ERRO:", result.stderr)


if __name__ == "__main__":
    unittest.main()
