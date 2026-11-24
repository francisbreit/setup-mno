#!/usr/bin/env python3
"""Normaliza saídas efêmeras do SRE-3 sem preservar identidades ou achados brutos."""

from __future__ import annotations

import argparse
import json
import os
import re
import stat
from datetime import datetime, timedelta, timezone
from pathlib import Path

SCHEMA_VERSION = 1
ENGINE_VERSION = "1.0.0"
MAX_RAW_BYTES = 16 * 1024 * 1024
ALLOWED_STATUS = {"completed", "partial", "failed", "skipped"}


def regular_file(path: Path, maximum: int = MAX_RAW_BYTES) -> bool:
    try:
        info = path.lstat()
    except OSError:
        return False
    return stat.S_ISREG(info.st_mode) and not path.is_symlink() and 0 < info.st_size <= maximum


def load_json(path: Path, maximum: int = MAX_RAW_BYTES):
    if not regular_file(path, maximum):
        raise ValueError(f"arquivo inválido: {path.name}")
    with path.open("r", encoding="utf-8", errors="strict") as stream:
        return json.load(stream)


def safe_status(raw: object, engine_id: str) -> str:
    if not isinstance(raw, dict):
        return "failed"
    value = raw.get(engine_id, "failed")
    return value if value in ALLOWED_STATUS else "failed"


def trivy_counts(directory: Path) -> tuple[dict[str, int], int]:
    counts = {"images": 0, "unknown": 0, "low": 0, "medium": 0, "high": 0, "critical": 0}
    invalid = 0
    if not directory.is_dir() or directory.is_symlink():
        return counts, 1
    for path in sorted(directory.glob("result-*.json"))[:32]:
        try:
            payload = load_json(path)
            if not isinstance(payload, dict) or not isinstance(payload.get("Results", []), list):
                raise ValueError("estrutura Trivy inválida")
            counts["images"] += 1
            for result in payload.get("Results", []):
                if not isinstance(result, dict):
                    continue
                vulnerabilities = result.get("Vulnerabilities") or []
                if not isinstance(vulnerabilities, list):
                    continue
                for item in vulnerabilities:
                    if not isinstance(item, dict):
                        continue
                    severity = str(item.get("Severity", "UNKNOWN")).strip().lower()
                    if severity not in counts:
                        severity = "unknown"
                    counts[severity] += 1
        except (OSError, UnicodeError, ValueError, json.JSONDecodeError):
            invalid += 1
    return counts, invalid


def lynis_counts(path: Path) -> dict[str, int]:
    counts = {"warnings": 0, "suggestions": 0, "tests": 0, "hardeningIndex": 0}
    if not regular_file(path):
        return counts
    with path.open("r", encoding="utf-8", errors="replace") as stream:
        for raw_line in stream:
            line = raw_line.strip()
            if line.startswith("warning[]="):
                counts["warnings"] += 1
            elif line.startswith("suggestion[]="):
                counts["suggestions"] += 1
            elif line.startswith("tests_executed="):
                value = line.partition("=")[2]
                counts["tests"] = min(
                    sum(1 for test_id in value.split("|") if test_id),
                    1_000_000,
                )
            elif line.startswith("hardening_index="):
                value = line.partition("=")[2]
                if value.isdigit():
                    counts["hardeningIndex"] = min(int(value), 100)
    return counts


def docker_bench_counts(path: Path) -> dict[str, int]:
    counts = {"pass": 0, "warn": 0, "info": 0, "note": 0}
    if not regular_file(path):
        return counts
    pattern = re.compile(r"\[(PASS|WARN|INFO|NOTE)\]")
    with path.open("r", encoding="utf-8", errors="replace") as stream:
        for raw_line in stream:
            match = pattern.search(raw_line)
            if match:
                counts[match.group(1).lower()] += 1
    return counts


def engine_entry(engine_id: str, version: str, status: str, coverage: str,
                 counts: dict[str, int], limitations: list[str]) -> dict:
    return {
        "id": engine_id,
        "version": version,
        "status": status,
        "coverage": coverage,
        "counts": counts,
        "limitations": limitations[:8],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tools", required=True)
    parser.add_argument("--execution-status", required=True)
    parser.add_argument("--trivy-dir", required=True)
    parser.add_argument("--lynis-report", required=True)
    parser.add_argument("--docker-bench-log", required=True)
    parser.add_argument("--environment", choices=("wsl2", "vps", "unknown"), required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--generated-at")
    args = parser.parse_args()

    tools = load_json(Path(args.tools), 64 * 1024)
    if tools.get("schemaVersion") != 1 or tools.get("engineVersion") != ENGINE_VERSION:
        raise SystemExit("registro de motores incompatível")
    statuses = load_json(Path(args.execution_status), 8 * 1024)
    trivy, invalid_trivy = trivy_counts(Path(args.trivy_dir))
    lynis = lynis_counts(Path(args.lynis_report))
    docker_bench = docker_bench_counts(Path(args.docker_bench_log))

    trivy_status = safe_status(statuses, "trivy")
    if invalid_trivy and trivy_status == "completed":
        trivy_status = "partial"
    engines = [
        engine_entry(
            "trivy", tools["tools"]["trivy"]["version"], trivy_status,
            "Imagens locais de serviços, sem nomes ou referências no resultado.", trivy,
            (["Uma ou mais respostas JSON foram recusadas."] if invalid_trivy else []) +
            (["Cobertura limitada às primeiras imagens únicas configuradas."] if trivy_status == "partial" else []),
        ),
        engine_entry(
            "lynis", tools["tools"]["lynis"]["version"], safe_status(statuses, "lynis"),
            "Configuração do host Linux no instante da auditoria.", lynis,
            (["Execução por root-dir dentro do Terminal Seguro possui cobertura parcial do host."]
             if safe_status(statuses, "lynis") == "partial" else []) +
            (["No WSL2, controles dependentes de boot, kernel ou systemd não representam uma VPS."]
             if args.environment == "wsl2" else []),
        ),
        engine_entry(
            "docker-bench", tools["tools"]["dockerBench"]["version"], safe_status(statuses, "docker-bench"),
            "Controles automatizados do CIS Docker Benchmark cobertos pelo Docker Bench.", docker_bench,
            ["Um aviso exige revisão humana e não prova vulnerabilidade explorável."] +
            (["No Terminal Seguro, rede e namespaces perigosos permanecem restritos; a cobertura é parcial."]
             if safe_status(statuses, "docker-bench") == "partial" else []),
        ),
    ]
    complete = all(item["status"] == "completed" for item in engines)
    attention = (
        trivy["critical"] > 0 or trivy["high"] > 0 or
        lynis["warnings"] > 0 or docker_bench["warn"] > 0
    )
    overall = "incomplete" if not complete else ("attention" if attention else "no-critical-signals")

    facts: list[dict[str, str]] = []
    if trivy_status in {"completed", "partial"}:
        severity = "critical" if trivy["critical"] else ("warning" if trivy["high"] else "info")
        facts.append({
            "severity": severity,
            "code": "trivy-vulnerability-counts",
            "observation": "O Trivy contou vulnerabilidades nas imagens cobertas sem expor alvos ou CVEs.",
            "evidence": f"images={trivy['images']},critical={trivy['critical']},high={trivy['high']}",
        })
    if safe_status(statuses, "lynis") in {"completed", "partial"}:
        facts.append({
            "severity": "warning" if lynis["warnings"] else "info",
            "code": "lynis-host-counts",
            "observation": "O Lynis produziu contagens sanitizadas da auditoria do host.",
            "evidence": f"warnings={lynis['warnings']},suggestions={lynis['suggestions']},hardeningIndex={lynis['hardeningIndex']}",
        })
    if safe_status(statuses, "docker-bench") in {"completed", "partial"}:
        facts.append({
            "severity": "warning" if docker_bench["warn"] else "info",
            "code": "docker-bench-counts",
            "observation": "O Docker Bench produziu contagens sanitizadas dos controles executados.",
            "evidence": f"pass={docker_bench['pass']},warn={docker_bench['warn']},info={docker_bench['info']}",
        })
    if not complete:
        facts.append({
            "severity": "warning", "code": "audit-coverage-incomplete",
            "observation": "A auditoria determinística não concluiu toda a cobertura planejada.",
            "evidence": "completedEngines=" + str(sum(item["status"] == "completed" for item in engines)),
        })

    if args.generated_at:
        generated = datetime.fromisoformat(args.generated_at.replace("Z", "+00:00")).astimezone(timezone.utc)
    else:
        generated = datetime.now(timezone.utc)
    expires = generated + timedelta(hours=int(tools["limits"]["freshnessHours"]))
    iso = lambda value: value.replace(microsecond=0).isoformat().replace("+00:00", "Z")
    result = {
        "schemaVersion": SCHEMA_VERSION,
        "engineVersion": ENGINE_VERSION,
        "maturity": "beta",
        "generatedAt": iso(generated),
        "expiresAt": iso(expires),
        "execution": "human-confirmed-terminal",
        "readOnly": True,
        "complete": complete,
        "overallStatus": overall,
        "hostType": args.environment,
        "privacy": {
            "sanitized": True,
            "rawFindingsIncluded": False,
            "targetsIncluded": False,
            "identifiersIncluded": False,
        },
        "engines": engines,
        "observedFacts": facts,
        "limitations": [
            "Resultado pontual com validade de 24 horas; não substitui monitoramento contínuo.",
            "Contagens exigem revisão humana e não afirmam que o servidor está seguro.",
            "Achados brutos, nomes de imagens, CVEs, paths, IPs, hostnames e credenciais não são persistidos.",
            "Falha, cobertura parcial ou ferramenta ausente permanecem visíveis como auditoria incompleta.",
        ],
    }
    output = Path(args.output)
    output.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    temporary = output.with_name(output.name + f".tmp.{os.getpid()}")
    with temporary.open("x", encoding="utf-8") as stream:
        json.dump(result, stream, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        stream.write("\n")
    os.chmod(temporary, 0o600)
    if temporary.stat().st_size > int(tools["limits"]["resultMaximumBytes"]):
        temporary.unlink(missing_ok=True)
        raise SystemExit("resultado sanitizado excedeu o limite")
    os.replace(temporary, output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
