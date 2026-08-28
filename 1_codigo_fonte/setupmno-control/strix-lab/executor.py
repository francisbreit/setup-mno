#!/usr/bin/env python3
"""Executor efêmero SRE-6.

Recebe somente um pacote-fonte local e uma autorização fechada. Evidência bruta
permanece em /tmp dentro do container descartável; apenas contagens sanitizadas
saem pelo marcador SETUPMNO_STRIX_REPORT.
"""
from __future__ import annotations

import argparse
import asyncio
import contextlib
import datetime as dt
import json
import hashlib
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

INPUT = Path("/input")
WORKSPACE = Path("/tmp/setupmno-workspace")
MAX_ARCHIVE_BYTES = 128 * 1024 * 1024
MAX_EXTRACTED_BYTES = 256 * 1024 * 1024
MAX_MEMBERS = 10_000
REPORT_MARKER = "SETUPMNO_STRIX_REPORT:"
SMOKE_MARKER = "SETUPMNO_STRIX_SMOKE:"


def now_utc() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def iso(value: dt.datetime) -> str:
    return value.replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_time(value: str) -> dt.datetime:
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))


def safe_relative(name: str) -> Path:
    pure = PurePosixPath(name.replace("\\", "/"))
    if pure.is_absolute() or ".." in pure.parts or not pure.parts:
        raise ValueError("caminho inseguro no pacote-fonte")
    return Path(*pure.parts)


def extract_archive(source: Path, destination: Path) -> None:
    if source.is_symlink() or not source.is_file() or source.stat().st_size > MAX_ARCHIVE_BYTES:
        raise ValueError("pacote-fonte ausente, inseguro ou grande demais")
    total = 0
    members = 0
    if zipfile.is_zipfile(source):
        with zipfile.ZipFile(source) as archive:
            for item in archive.infolist():
                members += 1
                if members > MAX_MEMBERS:
                    raise ValueError("pacote-fonte possui arquivos demais")
                target = destination / safe_relative(item.filename)
                mode = item.external_attr >> 16
                if (mode & 0o170000) == 0o120000:
                    raise ValueError("links simbólicos não são aceitos")
                if item.is_dir():
                    target.mkdir(parents=True, exist_ok=True)
                    continue
                total += item.file_size
                if total > MAX_EXTRACTED_BYTES:
                    raise ValueError("conteúdo extraído excede o limite")
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(item) as reader, target.open("wb") as writer:
                    shutil.copyfileobj(reader, writer)
    elif tarfile.is_tarfile(source):
        with tarfile.open(source, "r:*") as archive:
            for item in archive.getmembers():
                members += 1
                if members > MAX_MEMBERS:
                    raise ValueError("pacote-fonte possui arquivos demais")
                target = destination / safe_relative(item.name)
                if item.issym() or item.islnk() or item.isdev():
                    raise ValueError("links e dispositivos não são aceitos")
                if item.isdir():
                    target.mkdir(parents=True, exist_ok=True)
                    continue
                if not item.isfile():
                    raise ValueError("tipo de entrada não aceito")
                total += item.size
                if total > MAX_EXTRACTED_BYTES:
                    raise ValueError("conteúdo extraído excede o limite")
                target.parent.mkdir(parents=True, exist_ok=True)
                reader = archive.extractfile(item)
                if reader is None:
                    raise ValueError("entrada inválida no pacote-fonte")
                with reader, target.open("wb") as writer:
                    shutil.copyfileobj(reader, writer)
    else:
        raise ValueError("use somente ZIP ou TAR.GZ")


async def unix_local_smoke() -> dict[str, object]:
    from agents.sandbox.sandboxes.unix_local import UnixLocalSandboxClient

    client = UnixLocalSandboxClient()
    session = await client.create()
    try:
        await session.start()
        result = await session.exec("id", "-u", shell=False, timeout=10)
        return {
            "strixImported": True,
            "unixLocalSession": result.ok(),
            "sessionUID": result.stdout.decode("utf-8", "replace").strip(),
        }
    finally:
        await session.stop()
        await client.delete(session)


def run_smoke() -> int:
    import strix  # noqa: F401

    result = asyncio.run(unix_local_smoke())
    result.update(
        {
            "executorUID": os.getuid(),
            "dockerSocketPresent": Path("/var/run/docker.sock").exists(),
            "sudoPresent": shutil.which("sudo") is not None,
        }
    )
    print(SMOKE_MARKER + json.dumps(result, separators=(",", ":"), sort_keys=True))
    return 0 if result["unixLocalSession"] and os.getuid() != 0 else 1


async def setupmno_backend(*, image, manifest, exposed_ports, bind_mounts=None):
    del image, bind_mounts
    from agents.sandbox.sandboxes.unix_local import (
        UnixLocalSandboxClient,
        UnixLocalSandboxClientOptions,
    )

    client = UnixLocalSandboxClient()
    session = await client.create(
        options=UnixLocalSandboxClientOptions(exposed_ports=tuple(exposed_ports)),
        manifest=manifest,
    )
    await session.start()
    return client, session


def run_strix(target: Path, authorization: dict[str, object], key: str) -> int:
    from strix.runtime.backends import register_backend
    import strix.interface.main as interface_main

    provider = str(authorization["provider"])
    model = str(authorization["model"])
    os.environ.update(
        {
            "HOME": "/tmp/home",
            "STRIX_RUNTIME_BACKEND": "setupmno-unix-local",
            "STRIX_TELEMETRY": "0",
            "STRIX_LLM": f"openrouter/{model}" if provider == "openrouter" else f"openai/{model}",
            "LLM_API_KEY": key,
            "STRIX_REASONING_EFFORT": "medium",
        }
    )
    if provider == "openrouter":
        os.environ["LLM_API_BASE"] = "https://openrouter.ai/api/v1"
    register_backend("setupmno-unix-local", setupmno_backend, supports_bind_mounts=False)
    interface_main.check_docker_installed = lambda: None
    interface_main.pull_docker_image = lambda: None
    limits = authorization["limits"]
    sys.argv = [
        "strix",
        "--target",
        str(target),
        "--non-interactive",
        "--scan-mode",
        "quick",
        "--scope-mode",
        "full",
        "--max-budget",
        str(limits["llmBudgetUSD"]),
        "--max-turns",
        str(authorization["maxTurns"]),
    ]
    try:
        interface_main.main()
    except SystemExit as exc:
        return int(exc.code or 0)
    return 0


def vulnerability_counts(root: Path) -> dict[str, int]:
    counts = {key: 0 for key in ("critical", "high", "medium", "low", "info")}
    candidates = sorted(root.glob("strix_runs/*/vulnerabilities.json"))
    if not candidates:
        return counts
    payload = json.loads(candidates[-1].read_text(encoding="utf-8"))
    if not isinstance(payload, list):
        raise ValueError("índice de achados inválido")
    for item in payload:
        severity = str(item.get("severity", "info")).lower() if isinstance(item, dict) else "info"
        counts[severity if severity in counts else "info"] += 1
    return counts


def read_key() -> str:
    raw = sys.stdin.buffer.readline(4097)
    if len(raw) > 4096:
        raise ValueError("chave de provedor grande demais")
    key = raw.decode("utf-8", "strict").strip()
    if not 8 <= len(key) <= 4096 or any(ord(char) < 32 for char in key):
        raise ValueError("chave de provedor inválida")
    return key


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run_diagnostic() -> int:
    authorization_file = INPUT / "authorization.json"
    archive_file = INPUT / "target.archive"
    subprocess.run(
        [sys.executable, "/opt/setupmno/validate.py", "authorization", str(authorization_file)],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    authorization = json.loads(authorization_file.read_text(encoding="utf-8"))
    current = now_utc()
    if authorization["state"] != "approved" or not (
        parse_time(authorization["issuedAt"]) <= current <= parse_time(authorization["expiresAt"])
    ):
        raise ValueError("autorização ausente, expirada ou revogada")
    if sha256_file(archive_file) != authorization["targetSHA256"]:
        raise ValueError("pacote-fonte diverge da autorização fechada")
    key = read_key()
    Path(os.environ["HOME"]).mkdir(parents=True, exist_ok=True)
    target = WORKSPACE / "target"
    target.mkdir(parents=True, exist_ok=False)
    extract_archive(archive_file, target)
    raw_dir = Path(tempfile.mkdtemp(prefix="setupmno-strix-raw-", dir="/tmp"))
    generated = now_utc()
    status = "failed"
    counts = {key_name: 0 for key_name in ("critical", "high", "medium", "low", "info")}
    limitations = [
        "Diagnóstico BETA somente sobre pacote-fonte local explicitamente autorizado.",
        "Nenhum achado bruto, caminho, arquivo, segredo ou trecho de código sai do executor.",
        "Acesso de saída à internet foi permitido apenas para a LLM e ainda não possui allowlist por destino.",
        "O resultado pontual não substitui revisão humana nem autoriza correção.",
    ]
    try:
        os.chdir(raw_dir)
        with (raw_dir / "engine.stdout").open("w", encoding="utf-8") as engine_stdout, \
             (raw_dir / "engine.stderr").open("w", encoding="utf-8") as engine_stderr, \
             contextlib.redirect_stdout(engine_stdout), \
             contextlib.redirect_stderr(engine_stderr):
            exit_code = run_strix(target, authorization, key)
        counts = vulnerability_counts(raw_dir)
        status = "completed" if exit_code == 0 else "partial"
        if exit_code != 0:
            limitations.append("O Strix terminou parcialmente; revise disponibilidade e limites do provedor.")
    except Exception:
        limitations.append("O executor não concluiu a análise; nenhuma correção foi aplicada.")
    finally:
        os.environ.pop("LLM_API_KEY", None)
        key = ""
        os.chdir("/tmp")
        shutil.rmtree(raw_dir, ignore_errors=True)
        shutil.rmtree(target, ignore_errors=True)
    report = {
        "schemaVersion": 1,
        "contractVersion": "1.1.0",
        "maturity": "beta",
        "authorizationID": authorization["authorizationID"],
        "targetSHA256": authorization["targetSHA256"],
        "generatedAt": iso(generated),
        "expiresAt": iso(generated + dt.timedelta(hours=24)),
        "status": status,
        "counts": counts,
        "limitations": limitations,
        "executor": {
            "userID": os.getuid(),
            "rootless": os.getuid() != 0,
            "readOnlyRootFilesystem": True,
            "capabilitiesDropped": True,
            "noNewPrivileges": True,
            "productionDockerSocketPresent": Path("/var/run/docker.sock").exists(),
            "hostMountsPresent": False,
        },
        "execution": {
            "productionDockerSocketUsed": False,
            "productionRootMounted": False,
            "targetMutated": False,
            "automaticExecution": False,
        },
        "rawEvidenceStored": False,
        "sealGranted": False,
        "catalogPublished": False,
        "remediationApplied": False,
    }
    print(REPORT_MARKER + json.dumps(report, separators=(",", ":"), sort_keys=True))
    return 0 if status in {"completed", "partial"} else 1


def main() -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--smoke", action="store_true")
    args = parser.parse_args()
    return run_smoke() if args.smoke else run_diagnostic()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"SETUPMNO_STRIX_EXECUTOR_ERROR:{type(exc).__name__}", file=sys.stderr)
        raise SystemExit(1)
