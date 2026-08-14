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
from eval_factory import (
    EVAL_DATASET_VERSION,
    EVAL_GRADER_VERSION,
    EVAL_SCHEMA_VERSION,
    EXPECTED_CASES,
    validate_dataset,
)
from knowledge_coverage import build_report, evaluate_baseline
from knowledge_quality import (
    build_report as build_quality_report,
    evaluate_baseline as evaluate_quality_baseline,
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
    def test_mysql80_consumers_wait_for_authenticated_readiness(self) -> None:
        mysql80_scripts = (
            "bookstack",
            "easyappointments",
            "ghost",
            "glpi",
            "humhub",
            "krayincrm",
            "matomo",
            "mautic4whatsmkt",
            "mautic5padrao",
            "mautic5whatsmkt",
            "mautic6padrao",
            "mautic6whatsmkt",
            "mauticpadrao",
            "mysql",
            "wordpress",
            "yourl",
        )
        discovered = {
            path.stem
            for path in (SOURCE_ROOT / "x86" / "SetupLowCodeMno").glob("*.sh")
            if "image: percona/percona-server:8.0"
            in path.read_text(encoding="utf-8")
        }
        self.assertEqual(discovered, set(mysql80_scripts))

        for script_name in mysql80_scripts:
            with self.subTest(script=script_name):
                x86_script = (
                    SOURCE_ROOT / "x86" / "SetupLowCodeMno" / f"{script_name}.sh"
                ).read_text(encoding="utf-8")
                arm_script = (
                    SOURCE_ROOT / "arm" / "SetupLowCodeMno" / f"{script_name}.sh"
                ).read_text(encoding="utf-8")

                self.assertEqual(x86_script, arm_script)
                self.assertEqual(
                    x86_script.count("setupmno_mysql80_wait_ready() {"),
                    1,
                )
                self.assertIn("docker service inspect mysql_mysql", x86_script)
                self.assertIn(
                    'label=com.docker.swarm.service.name=$service_name',
                    x86_script,
                )
                self.assertIn('-e "SELECT 1"', x86_script)
                self.assertIn("for attempt in $(seq 1 181); do", x86_script)
                self.assertIn(
                    'local progress_mode="${2:-silent}"',
                    x86_script,
                )
                self.assertIn(
                    'printf \'XXX\\n100\\nMySQL 8.0 pronto.',
                    x86_script,
                )
                self.assertIn(
                    'exec 9> >(whiptail --title "INICIALIZANDO MYSQL 8.0"',
                    x86_script,
                )
                self.assertIn(
                    'setupmno_mysql80_wait_ready "$yaml_file" progress >&9',
                    x86_script,
                )
                self.assertIn(
                    "O banco está iniciando. Aguarde; este processo pode levar alguns minutos.",
                    x86_script,
                )
                self.assertEqual(
                    x86_script.count(
                        "setupmno_mysql80_require_ready /root/mysql.yaml"
                    ),
                    1,
                )
                self.assertNotIn(
                    'grep -q "^mysql$")',
                    x86_script,
                )
                self.assertNotIn("docker ps -qf name=mysql", x86_script)
                self.assertNotIn("docker exec -e MYSQL_PWD=", x86_script)

                if script_name != "mysql":
                    self.assertIn(
                        'setupmno_mysql80_create_database "',
                        x86_script,
                    )

    def test_langfuse_waits_for_portainer_and_binds_health_endpoints(self) -> None:
        x86_script = (
            SOURCE_ROOT / "x86" / "SetupLowCodeMno" / "langfuse.sh"
        ).read_text(encoding="utf-8")
        arm_script = (
            SOURCE_ROOT / "arm" / "SetupLowCodeMno" / "langfuse.sh"
        ).read_text(encoding="utf-8")

        self.assertEqual(x86_script, arm_script)
        self.assertEqual(x86_script.count("      - HOSTNAME=0.0.0.0\n"), 2)
        self.assertIn("wait_stack_registered() {", x86_script)
        self.assertIn("for attempt in $(seq 1 25); do", x86_script)
        self.assertIn('if [ "$attempt" -lt 25 ]; then', x86_script)
        self.assertIn(
            'wait_stack_registered "$nome_app" "Langfuse" 75',
            x86_script,
        )

    def test_linkwarden_is_isolated_and_closes_public_registration(self) -> None:
        x86_script = (
            SOURCE_ROOT / "x86" / "SetupLowCodeMno" / "linkwarden.sh"
        ).read_text(encoding="utf-8")
        arm_script = (
            SOURCE_ROOT / "arm" / "SetupLowCodeMno" / "linkwarden.sh"
        ).read_text(encoding="utf-8")

        self.assertEqual(x86_script, arm_script)
        self.assertIn("ghcr.io/linkwarden/linkwarden:v2.14.1@sha256:", x86_script)
        self.assertIn("postgres:16.10-alpine@sha256:", x86_script)
        self.assertIn("getmeili/meilisearch:v1.12.8@sha256:", x86_script)
        self.assertIn('postgres_stack="${nome_app}-postgres"', x86_script)
        self.assertIn('meili_stack="${nome_app}-meilisearch"', x86_script)
        self.assertIn("NEXT_PUBLIC_USER_CONTENT_DOMAIN: https://$url_content", x86_script)
        self.assertIn('hostname:$content,path:"^/api/v1/preserved/view$"', x86_script)
        self.assertIn('hostname:$app,path:"^/api/v1/preserved/view$"', x86_script)
        self.assertIn('NEXT_PUBLIC_DISABLE_REGISTRATION: "false"', x86_script)
        self.assertIn(
            'sed -i \'s/NEXT_PUBLIC_DISABLE_REGISTRATION: "false"/'
            'NEXT_PUBLIC_DISABLE_REGISTRATION: "true"/\'',
            x86_script,
        )
        self.assertIn("(.response.DISABLE_REGISTRATION == true)", x86_script)
        self.assertIn("(.response.USER_CONTENT_DOMAIN == $domain)", x86_script)
        self.assertIn('previous_container="${4:-}"', x86_script)
        self.assertIn('[ "$container_id" != "$previous_container" ]', x86_script)
        self.assertIn(
            'deploy_stack "$app_stack" "$app_yaml" ||\n'
            '        fail_install 44 "ERRO NO LINKWARDEN" "Não foi possível criar a stack principal do Linkwarden."\n'
            '    wait_service "$app_service" 120 healthy ||',
            x86_script,
        )
        self.assertIn(
            'wait_service "$app_service" 120 healthy "$app_container" ||\n'
            '        fail_install 56 "ATUALIZAÇÃO NÃO CONVERGIU"',
            x86_script,
        )
        self.assertIn('wait_secure_config "$app_container" "https://$url_content" 30', x86_script)
        self.assertIn('Configuração segura confirmada pela API do Linkwarden.', x86_script)
        self.assertIn('disableRegistration:', x86_script)
        self.assertNotIn('config_json=$(docker exec "$app_container"', x86_script)
        self.assertIn("read_only: true", x86_script)
        self.assertIn(
            '[[ "$yaml_file" == /root/linkwarden*.yaml ]]',
            x86_script,
        )
        self.assertIn('app_tmp_dir="$base_dir/tmp"', x86_script)
        self.assertIn("- $app_tmp_dir:/tmp", x86_script)
        self.assertIn("target: /dev/shm", x86_script)
        self.assertNotIn("security_opt:", x86_script)
        self.assertIn(
            'export MEILI_MASTER_KEY="\\$\\$(cat /run/secrets/meili_master_key)"',
            x86_script,
        )
        self.assertIn(
            'postgresql://linkwarden:\\$\\${POSTGRES_PASSWORD}',
            x86_script,
        )
        self.assertNotIn("target: /tmp\n        tmpfs:", x86_script)
        self.assertNotIn("\n    ports:\n", x86_script)
        self.assertIn('whiptail --title "LINKWARDEN PRO" --msgbox "$1" 16 84 1>&2', x86_script)
        self.assertIn('[ "$status" -ne 0 ] && return 130', x86_script)

    def test_rustdesk_accepts_cloudflare_dns_only_boolean_false(self) -> None:
        x86_script = (
            ROOT.parent / "x86" / "SetupLowCodeMno" / "rustdesk.sh"
        ).read_text(encoding="utf-8")
        arm_script = (
            ROOT.parent / "arm" / "SetupLowCodeMno" / "rustdesk.sh"
        ).read_text(encoding="utf-8")

        self.assertEqual(x86_script, arm_script)
        self.assertIn(
            "jq -e '.result | has(\"proxied\") and (.proxied == false)'",
            x86_script,
        )
        self.assertNotIn(".result.proxied // true", x86_script)
        self.assertIn("published: 21116", x86_script)
        self.assertIn("protocol: udp", x86_script)

    def test_quality_governance_is_truthful_and_monotonic(self) -> None:
        report = build_quality_report(ROOT, CATALOG)
        summary = report["summary"]
        self.assertEqual(summary["setupEntries"], 157)
        self.assertEqual(
            summary["installationStatuses"]["maintainer-homologated"], 157
        )
        self.assertEqual(summary["integrationMaturityLevels"]["not-mapped"], 157)
        self.assertEqual(summary["maturityLevels"]["structural"], 157)
        self.assertEqual(summary["maturityLevels"]["operational-reviewed"], 0)
        self.assertEqual(summary["homologatedEntries"], 0)
        self.assertEqual(summary["officialSourceEntries"], 137)
        self.assertEqual(summary["officialSourceExceptions"], 1)
        self.assertEqual(summary["internalOnlySourceEntries"], 19)
        self.assertEqual(summary["unresolvedIssueCount"], 29)
        self.assertTrue(
            all(
                entry["installationStatus"] == "maintainer-homologated"
                and entry["testedArchitectures"]
                and entry["integrationMaturity"] == "not-mapped"
                for entry in report["entries"]
            )
        )
        baseline = load_json(ROOT / "quality-baseline.json")
        self.assertEqual(evaluate_quality_baseline(report, baseline), [])

        regressed = copy.deepcopy(report)
        regressed["summary"]["unresolvedIssueCount"] = 30
        errors = evaluate_quality_baseline(regressed, baseline)
        self.assertTrue(any("pendências" in error for error in errors), errors)

    def test_catalog_coverage_is_explicit_and_internally_consistent(self) -> None:
        report = build_report(
            CATALOG,
            ROOT / "registry" / "setups.json",
            ROOT,
        )
        self.assertEqual(report["catalogEntries"], 157)
        self.assertEqual(report["coveredEntries"], 157)
        self.assertEqual(report["missingEntries"], 0)
        self.assertEqual(report["coveragePercent"], 100.0)
        self.assertEqual(report["status"], "complete")
        self.assertTrue(all(not values for values in report["integrity"].values()))
        baseline = load_json(ROOT / "coverage-baseline.json")
        self.assertEqual(evaluate_baseline(report, baseline), [])

        regressed = copy.deepcopy(report)
        regressed["catalogEntries"] = 157
        regressed["missingEntries"] = 122
        regressed["coveragePercent"] = 13.16
        errors = evaluate_baseline(regressed, baseline)
        self.assertTrue(any("nova entrada" in error for error in errors), errors)
        self.assertTrue(any("percentual" in error for error in errors), errors)

    def test_eval_dataset_is_reviewed_and_complete(self) -> None:
        registry = load_json(ROOT / "registry" / "setups.json")
        dataset = load_json(ROOT / "evals" / "dataset.json")
        self.assertEqual(validate_dataset(dataset, registry["setupVersion"]), [])
        self.assertEqual(dataset["schemaVersion"], EVAL_SCHEMA_VERSION)
        self.assertEqual(dataset["datasetVersion"], EVAL_DATASET_VERSION)
        self.assertEqual(dataset["graderVersion"], EVAL_GRADER_VERSION)
        self.assertEqual(dataset["caseCount"], EXPECTED_CASES)
        self.assertEqual(
            sum(case["evaluationType"] == "retrieval" for case in dataset["cases"]),
            869,
        )
        self.assertTrue(
            all("password" not in json.dumps(case).lower() for case in dataset["cases"])
        )

    def test_complete_base_passes_linter(self) -> None:
        result = run_linter()
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["documents"], 176)
        self.assertEqual(report["setups"], 157)
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
                        "4.2.0",
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
                    self.assertEqual(len(legacy_index["entries"]), 176)
                    blueprint_index = json.load(
                        package.extractfile("blueprints/index.json")
                    )
                    eval_dataset = json.load(package.extractfile("evals/dataset.json"))
                    self.assertEqual(eval_dataset["caseCount"], EXPECTED_CASES)
                    self.assertEqual(eval_dataset["setupVersion"], registry["setupVersion"])
                    self.assertEqual(blueprint_index["schemaVersion"], 2)
                    self.assertEqual(blueprint_index["blueprintCount"], 5)
                    self.assertEqual(blueprint_index["statuses"], {"reviewed": 5})
                    self.assertTrue(
                        all(
                            not entry["fictitious"] and not entry["deployable"]
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
                            not entry["fictitious"]
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
            self.assertEqual(manifests[0]["documentEntries"], 176)
            self.assertEqual(manifests[0]["setupEntries"], 157)
            self.assertEqual(manifests[0]["infrastructureEntries"], 14)
            self.assertEqual(manifests[0]["blueprintFactoryVersion"], "2.1.0")
            self.assertEqual(manifests[0]["blueprintSchemaVersion"], 2)
            self.assertEqual(manifests[0]["blueprintEntries"], 5)
            self.assertEqual(manifests[0]["blueprintBundleEntries"], 5)
            self.assertEqual(manifests[0]["blueprintKnowledgeEntries"], 5)
            self.assertEqual(manifests[0]["blueprintFixtureEntries"], 0)
            self.assertEqual(manifests[0]["indexSchemaVersion"], 2)
            self.assertEqual(
                manifests[0]["retrievalVersion"],
                RETRIEVAL_VERSION,
            )
            self.assertGreater(manifests[0]["chunkEntries"], 29)
            self.assertEqual(manifests[0]["evalSchemaVersion"], EVAL_SCHEMA_VERSION)
            self.assertEqual(manifests[0]["evalDatasetVersion"], EVAL_DATASET_VERSION)
            self.assertEqual(manifests[0]["evalGraderVersion"], EVAL_GRADER_VERSION)
            self.assertEqual(manifests[0]["evalCaseEntries"], EXPECTED_CASES)
            self.assertEqual(len(manifests[0]["evalDatasetSHA256"]), 64)


if __name__ == "__main__":
    unittest.main()
