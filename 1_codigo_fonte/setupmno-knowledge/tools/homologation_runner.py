#!/usr/bin/python3
"""Gera e verifica evidências candidatas de homologação do Setup MNO.

O runner não executa comandos fornecidos pelo usuário, não cria recursos Docker,
não altera a governança canônica e nunca concede o Selo de Homologação.
"""

from __future__ import annotations

import argparse
import datetime as dt
import gzip
import hashlib
import io
import json
import os
import platform
import re
import subprocess
import sys
import tarfile
import tempfile
import time
from pathlib import Path
from typing import Any


RUNNER_VERSION = "1.3.0"
RUNNER_RELEASE_DATE = "2026-08-23"
CANDIDATE_SCHEMA_VERSION = 1
PACKAGE_SCHEMA_VERSION = 1
MAX_JSON_BYTES = 128 << 10
MAX_BUNDLE_BYTES = 512 << 10
MAX_REVIEW_PACK_BYTES = 2 << 20
MAX_MAINTAINER_WORKSPACE_BYTES = 8 << 20
SUPPORTED_RUNNER_VERSIONS = {"1.1.0", "1.2.0", RUNNER_VERSION}
CHECKS = (
    "deploy",
    "convergence",
    "health",
    "persistence",
    "restart",
    "update",
    "backup",
    "restore",
    "cleanup",
)
OPERATIONAL_CHECKS = (
    "deploy",
    "convergence",
    "health",
)
STATUSES = {"passed", "not-tested", "not-applicable"}
PLATFORMS = {"linux-vps", "wsl2-docker-desktop", "linux-emulated"}
ARCHITECTURES = {"amd64", "arm64"}
ID_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
RUN_ID_RE = re.compile(r"^setupmno-hml-[a-z0-9]+(?:-[a-z0-9]+)*-[0-9]{12}$")
SEMVER_RE = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
SHA256_RE = re.compile(r"^[a-f0-9]{64}$")
IMAGE_RE = re.compile(r"^\S+@sha256:[a-f0-9]{64}$")
DISPLAY_NAME_RE = re.compile(r"^[A-Za-zÀ-ÖØ-öø-ÿ0-9][A-Za-zÀ-ÖØ-öø-ÿ0-9 ._-]*$")
SERVICE_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$")
URL_RE = re.compile(r"^https?://[^\s/]+(?::[0-9]{1,5})?(?:/[^\s]*)?$")
CRITICAL_LOG_RE = re.compile(
    r"(?:\bfatal\b|\bpanic\b|segmentation fault|uncaught exception|"
    r"permission denied|address already in use)",
    re.IGNORECASE,
)
REASON_CODES = {
    "operational-evidence-accepted",
    "incomplete-evidence",
    "artifact-mismatch",
    "unsafe-data",
    "check-failed",
    "rerun-required",
    "other",
}
SENSITIVE_PATTERNS = (
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"\bBearer\s+[A-Za-z0-9._~+/-]{12,}", re.IGNORECASE),
    re.compile(r"\b(?:sk|cfut)_[A-Za-z0-9_-]{12,}\b"),
    re.compile(r"\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b"),
    re.compile(r"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", re.IGNORECASE),
)


class RunnerError(ValueError):
    """Falha segura e apresentável ao operador."""


def canonical_json(value: Any) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        + "\n"
    ).encode("utf-8")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_datetime(value: str) -> dt.datetime:
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise RunnerError("data deve usar ISO-8601 com fuso horário") from exc
    if parsed.tzinfo is None:
        raise RunnerError("data deve possuir fuso horário")
    return parsed.astimezone(dt.timezone.utc)


def utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0)


def iso_z(value: dt.datetime) -> str:
    return value.astimezone(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def ensure_regular(path: Path, max_bytes: int = MAX_JSON_BYTES) -> bytes:
    if path.is_symlink() or not path.is_file():
        raise RunnerError(f"arquivo ausente, irregular ou symlink: {path}")
    size = path.stat().st_size
    if size <= 0 or size > max_bytes:
        raise RunnerError(f"arquivo fora do limite permitido: {path}")
    return path.read_bytes()


def load_json(path: Path, max_bytes: int = MAX_JSON_BYTES) -> Any:
    try:
        return json.loads(ensure_regular(path, max_bytes))
    except json.JSONDecodeError as exc:
        raise RunnerError(f"JSON inválido: {path}") from exc


def atomic_write(path: Path, data: bytes, mode: int = 0o600) -> None:
    parent = path.parent
    parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    if parent.is_symlink() or not parent.is_dir():
        raise RunnerError(f"diretório de saída inseguro: {parent}")
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=parent)
    temporary = Path(temporary_name)
    try:
        os.fchmod(descriptor, mode)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def reject_sensitive(value: Any, context: str = "candidato") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if re.search(r"password|passwd|senha|token|secret|credential|authorization", key, re.I):
                raise RunnerError(f"campo sensível proibido em {context}: {key}")
            reject_sensitive(child, context)
        return
    if isinstance(value, list):
        for child in value:
            reject_sensitive(child, context)
        return
    if isinstance(value, str) and any(pattern.search(value) for pattern in SENSITIVE_PATTERNS):
        raise RunnerError(f"possível dado sensível detectado em {context}")


def package_directory(args: argparse.Namespace | None = None) -> Path:
    if args is not None and getattr(args, "package_dir", None):
        return Path(args.package_dir).resolve()
    return Path(__file__).resolve().parent


def validate_package(directory: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    manifest_path = directory / "manifest.json"
    registry_path = directory / "runner-registry.json"
    schema_path = directory / "homologation-candidate.schema.json"
    decision_schema_path = directory / "homologation-review-decision.schema.json"
    review_pack_schema_path = directory / "homologation-review-pack.schema.json"
    manifest = load_json(manifest_path)
    expected_keys = {
        "schemaVersion", "runnerVersion", "candidateSchemaVersion", "setupVersion",
        "generatedAt", "registryEntries", "maintainerWorkspaceBytes",
        "maintainerWorkspaceSHA256", "remoteCertification", "files",
    }
    if not isinstance(manifest, dict) or set(manifest) != expected_keys:
        raise RunnerError("manifesto do runner possui campos inesperados")
    if (
        manifest["schemaVersion"] != PACKAGE_SCHEMA_VERSION
        or manifest["runnerVersion"] != RUNNER_VERSION
        or manifest["candidateSchemaVersion"] != CANDIDATE_SCHEMA_VERSION
        or not SEMVER_RE.fullmatch(str(manifest["setupVersion"]))
        or not isinstance(manifest["registryEntries"], int)
        or manifest["registryEntries"] < 1
        or manifest["remoteCertification"] is not True
        or not SHA256_RE.fullmatch(str(manifest["maintainerWorkspaceSHA256"]))
        or not isinstance(manifest["maintainerWorkspaceBytes"], int)
        or not 0 < manifest["maintainerWorkspaceBytes"] <= MAX_MAINTAINER_WORKSPACE_BYTES
    ):
        raise RunnerError("manifesto do runner é incompatível")
    parse_datetime(manifest["generatedAt"])
    files = manifest.get("files")
    if not isinstance(files, list) or len(files) != 11:
        raise RunnerError("inventário do runner inválido")
    expected_names = {
        "homologation_runner.py",
        "homologation_wizard.sh",
        "homologation-candidate.schema.json",
        "homologation-review-decision.schema.json",
        "homologation-review-pack.schema.json",
        "runner-registry.json",
        "maintainer_console.sh",
        "maintainer_workspace.sh",
        "maintainer_validation_wizard.sh",
        "certification_wizard.sh",
        "maintainer-workspace.tar.gz",
    }
    found_names: set[str] = set()
    for item in files:
        if not isinstance(item, dict) or set(item) != {"path", "sha256", "size"}:
            raise RunnerError("entrada inválida no inventário do runner")
        name = item["path"]
        if name not in expected_names or name in found_names:
            raise RunnerError("arquivo inesperado no pacote do runner")
        found_names.add(name)
        file_path = directory / name
        limit = MAX_MAINTAINER_WORKSPACE_BYTES if name == "maintainer-workspace.tar.gz" else MAX_JSON_BYTES
        data = ensure_regular(file_path, limit)
        if item["size"] != len(data) or item["sha256"] != sha256_bytes(data):
            raise RunnerError(f"integridade divergente no runner: {name}")
    if found_names != expected_names:
        raise RunnerError("pacote do runner incompleto")
    workspace = ensure_regular(directory / "maintainer-workspace.tar.gz", MAX_MAINTAINER_WORKSPACE_BYTES)
    if (
        manifest["maintainerWorkspaceBytes"] != len(workspace)
        or manifest["maintainerWorkspaceSHA256"] != sha256_bytes(workspace)
    ):
        raise RunnerError("workspace do mantenedor diverge do manifesto")
    registry = load_json(registry_path)
    if (
        not isinstance(registry, dict)
        or set(registry) != {"schemaVersion", "runnerVersion", "setupVersion", "entries"}
        or registry["schemaVersion"] != 1
        or registry["runnerVersion"] != RUNNER_VERSION
        or registry["setupVersion"] != manifest["setupVersion"]
        or not isinstance(registry["entries"], list)
        or len(registry["entries"]) != manifest["registryEntries"]
    ):
        raise RunnerError("registro do runner inválido")
    schema = load_json(schema_path)
    if schema.get("properties", {}).get("schemaVersion", {}).get("const") != CANDIDATE_SCHEMA_VERSION:
        raise RunnerError("schema de candidato incompatível")
    decision_schema = load_json(decision_schema_path)
    review_pack_schema = load_json(review_pack_schema_path)
    if decision_schema.get("properties", {}).get("officialSeal", {}).get("const") is not False:
        raise RunnerError("schema de decisão ultrapassa a fronteira de confiança")
    if review_pack_schema.get("properties", {}).get("officialSeal", {}).get("const") is not False:
        raise RunnerError("schema do pacote de revisão ultrapassa a fronteira de confiança")
    return manifest, registry


def registry_by_id(registry: dict[str, Any]) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for entry in registry["entries"]:
        if not isinstance(entry, dict) or set(entry) != {
            "setupId", "catalogName", "script", "architectures", "artifacts",
        }:
            raise RunnerError("entrada inesperada no registro do runner")
        setup_id = entry.get("setupId")
        if not isinstance(setup_id, str) or not ID_RE.fullmatch(setup_id) or setup_id in result:
            raise RunnerError("setupId inválido ou duplicado no runner")
        architectures = entry.get("architectures")
        artifacts = entry.get("artifacts")
        if (
            not isinstance(architectures, list)
            or not architectures
            or any(value not in ARCHITECTURES for value in architectures)
            or len(set(architectures)) != len(architectures)
            or not isinstance(artifacts, dict)
            or set(artifacts) != set(architectures)
        ):
            raise RunnerError(f"arquiteturas inválidas para {setup_id}")
        for architecture, artifact in artifacts.items():
            prefix = "x86" if architecture == "amd64" else "arm"
            if (
                not isinstance(artifact, dict)
                or set(artifact) != {"path", "sha256"}
                or artifact["path"] != f"{prefix}/SetupLowCodeMno/{entry['script']}"
                or not SHA256_RE.fullmatch(str(artifact["sha256"]))
            ):
                raise RunnerError(f"artefato inválido para {setup_id}/{architecture}")
        result[setup_id] = entry
    return result


def docker_preflight(expected_architecture: str) -> None:
    try:
        result = subprocess.run(
            ["docker", "info", "--format", "{{.Swarm.LocalNodeState}} {{.Architecture}}"],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired) as exc:
        raise RunnerError("Docker não está disponível para a homologação") from exc
    if result.returncode != 0:
        raise RunnerError("Docker não respondeu ao preflight do runner")
    fields = result.stdout.strip().split()
    if len(fields) != 2 or fields[0] != "active":
        raise RunnerError("Docker Swarm precisa estar ativo")
    detected_architecture = {"x86_64": "amd64", "aarch64": "arm64"}.get(fields[1], fields[1])
    if detected_architecture != expected_architecture:
        raise RunnerError(
            f"arquitetura Docker {detected_architecture} diverge da seleção {expected_architecture}"
        )


def run_fixed_command(arguments: list[str], timeout: int = 20) -> subprocess.CompletedProcess[str]:
    """Executa somente argumentos construídos pelo Runner, nunca texto de shell."""
    try:
        return subprocess.run(
            arguments,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired) as exc:
        raise RunnerError(f"comando controlado indisponível: {arguments[0]}") from exc


def load_service(service_name: str) -> dict[str, Any]:
    if not SERVICE_RE.fullmatch(service_name):
        raise RunnerError("nome de serviço Docker inválido")
    result = run_fixed_command(["docker", "service", "inspect", service_name])
    if result.returncode != 0:
        raise RunnerError("serviço Docker não foi encontrado")
    try:
        values = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise RunnerError("Docker retornou inspeção de serviço inválida") from exc
    if not isinstance(values, list) or len(values) != 1 or not isinstance(values[0], dict):
        raise RunnerError("Docker retornou uma quantidade inesperada de serviços")
    return values[0]


def resolved_image(image: str) -> str:
    if IMAGE_RE.fullmatch(image):
        return image
    result = run_fixed_command(
        ["docker", "image", "inspect", image, "--format", "{{json .RepoDigests}}"]
    )
    if result.returncode == 0:
        try:
            digests = json.loads(result.stdout.strip())
        except json.JSONDecodeError:
            digests = []
        if isinstance(digests, list):
            matches = sorted(value for value in digests if isinstance(value, str) and IMAGE_RE.fullmatch(value))
            if matches:
                return matches[0]
    raise RunnerError("a imagem do serviço ainda não possui digest verificável")


def service_url(service: dict[str, Any]) -> str:
    spec = service.get("Spec", {})
    labels = spec.get("Labels", {}) if isinstance(spec, dict) else {}
    if isinstance(labels, dict):
        for key, value in sorted(labels.items()):
            if key.endswith(".rule") and isinstance(value, str):
                match = re.search(r"Host\(`([^`]+)`\)", value)
                if match:
                    return f"https://{match.group(1)}"
    container = spec.get("TaskTemplate", {}).get("ContainerSpec", {}) if isinstance(spec, dict) else {}
    environment = container.get("Env", []) if isinstance(container, dict) else []
    for value in environment if isinstance(environment, list) else []:
        if isinstance(value, str) and value.startswith("VIRTUAL_HOST="):
            host = value.split("=", 1)[1].strip()
            if host and not re.search(r"[\s/]", host):
                return f"https://{host}"
    return ""


def service_task_sample(service_name: str) -> tuple[int, int, list[str]]:
    result = run_fixed_command([
        "docker", "service", "ps",
        "--filter", "desired-state=running",
        "--format", "{{.CurrentState}}\t{{.Error}}",
        service_name,
    ])
    if result.returncode != 0:
        raise RunnerError("não foi possível consultar as tarefas do serviço")
    rows = [line.split("\t", 1) for line in result.stdout.splitlines() if line.strip()]
    desired = len(rows)
    running = sum(parts[0].startswith("Running ") or parts[0] == "Running" for parts in rows)
    errors = [parts[1].strip() for parts in rows if len(parts) == 2 and parts[1].strip()]
    return desired, running, errors


def command_inspect(args: argparse.Namespace) -> None:
    """Produz os gates essenciais sem alterar, reiniciar ou remover recursos Docker."""
    session_path = Path(args.session).resolve()
    session = load_session(session_path)
    report_path = session_path.parent / "essential-inspection.json"
    if report_path.exists():
        raise RunnerError("esta sessão já possui inspeção essencial")
    docker_preflight(session["architecture"])
    service = load_service(args.service)
    container = service.get("Spec", {}).get("TaskTemplate", {}).get("ContainerSpec", {})
    image = resolved_image(str(container.get("Image", "")))
    first_desired, first_running, first_errors = service_task_sample(args.service)
    if first_desired < 1 or first_running != first_desired or first_errors:
        raise RunnerError(
            f"serviço ainda não convergiu: executando={first_running}, esperado={first_desired}"
        )
    time.sleep(3)
    second_desired, second_running, second_errors = service_task_sample(args.service)
    if (
        second_desired != first_desired
        or second_running != second_desired
        or second_errors
    ):
        raise RunnerError("o serviço não permaneceu estável durante a verificação")

    logs = run_fixed_command([
        "docker", "service", "logs",
        "--raw", "--since", "10m", "--tail", "200", args.service,
    ], timeout=30)
    if logs.returncode != 0:
        raise RunnerError("os logs recentes do serviço não puderam ser verificados")
    combined_logs = (logs.stdout + "\n" + logs.stderr)[: 256 << 10]
    critical_matches = len(CRITICAL_LOG_RE.findall(combined_logs))
    if critical_matches:
        raise RunnerError("os logs recentes contêm indicador crítico; revise o serviço")

    target_url = args.url or service_url(service)
    if not target_url or not URL_RE.fullmatch(target_url):
        raise RunnerError("não foi possível detectar a URL; informe http:// ou https://")
    response = run_fixed_command([
        "curl", "-L", "-sS", "-o", "/dev/null", "-w", "%{http_code}",
        "--connect-timeout", "10", "--max-time", "20", target_url,
    ], timeout=25)
    status_text = response.stdout.strip()
    valid_http_status = status_text.isdigit() and (
        200 <= int(status_text) < 400 or int(status_text) in {401, 403}
    )
    if response.returncode != 0 or not valid_http_status:
        raise RunnerError("a aplicação não respondeu de forma válida por HTTP/HTTPS")

    session["checks"]["deploy"] = check_record(
        "passed", "Serviço Docker encontrado e imagem imutável identificada automaticamente."
    )
    session["checks"]["convergence"] = check_record(
        "passed", f"Serviço convergiu automaticamente com {second_running} de {second_desired} tarefas em execução."
    )
    session["checks"]["health"] = check_record(
        "passed", f"Aplicação respondeu por HTTP com status {status_text}; logs recentes sem indicador crítico."
    )
    for name in ("persistence", "restart", "update", "backup", "restore", "cleanup"):
        session["checks"][name] = check_record(
            "not-applicable", "Fora do escopo do Selo Essencial; disponível na homologação avançada."
        )
    atomic_write(session_path, canonical_json(session))
    report = {
        "schemaVersion": 1,
        "kind": "setupmno-essential-inspection",
        "runId": session["runId"],
        "setupId": session["setupId"],
        "setupVersion": session["setupVersion"],
        "architecture": session["architecture"],
        "checkedAt": iso_z(utc_now()),
        "desiredTasks": second_desired,
        "runningTasks": second_running,
        "httpStatus": int(status_text),
        "criticalLogIndicators": critical_matches,
        "images": [image],
        "result": "passed",
        "mutationsPerformed": False,
    }
    reject_sensitive(report, "inspeção essencial")
    atomic_write(report_path, canonical_json(report))
    print(json.dumps(report | {"report": str(report_path)}, ensure_ascii=False, sort_keys=True))


def default_platform() -> str:
    try:
        kernel = Path("/proc/version").read_text(encoding="utf-8", errors="replace").lower()
    except OSError:
        kernel = platform.release().lower()
    return "wsl2-docker-desktop" if "microsoft" in kernel or "wsl" in kernel else "linux-vps"


def check_record(status: str, evidence: str) -> dict[str, str]:
    normalized = " ".join(evidence.split())
    if status not in STATUSES or not 1 <= len(normalized) <= 240:
        raise RunnerError("check exige status permitido e evidência entre 1 e 240 caracteres")
    reject_sensitive(normalized, "descrição do check")
    return {"status": status, "evidence": normalized}


def validate_candidate(candidate: Any) -> dict[str, Any]:
    required = {
        "schemaVersion", "kind", "candidateId", "runId", "runnerVersion", "setupId",
        "setupVersion", "architecture", "createdAt", "tester", "environment", "artifact",
        "images", "checks", "result", "sanitized", "submission",
    }
    if not isinstance(candidate, dict) or set(candidate) != required:
        raise RunnerError("candidato possui campos ausentes ou inesperados")
    if (
        candidate["schemaVersion"] != CANDIDATE_SCHEMA_VERSION
        or candidate["kind"] != "setupmno-homologation-candidate"
        or not ID_RE.fullmatch(str(candidate["candidateId"]))
        or not RUN_ID_RE.fullmatch(str(candidate["runId"]))
        or candidate["runnerVersion"] not in SUPPORTED_RUNNER_VERSIONS
        or not ID_RE.fullmatch(str(candidate["setupId"]))
        or not SEMVER_RE.fullmatch(str(candidate["setupVersion"]))
        or candidate["architecture"] not in ARCHITECTURES
        or candidate["sanitized"] is not True
    ):
        raise RunnerError("identidade do candidato inválida")
    parse_datetime(candidate["createdAt"])
    tester = candidate["tester"]
    if (
        not isinstance(tester, dict)
        or set(tester) != {"displayName", "attestation"}
        or tester.get("attestation") != "self-attested"
        or not isinstance(tester.get("displayName"), str)
        or not 2 <= len(tester["displayName"]) <= 80
        or not DISPLAY_NAME_RE.fullmatch(tester["displayName"])
    ):
        raise RunnerError("identificação pública do testador inválida")
    environment = candidate["environment"]
    if environment != {
        "platform": environment.get("platform") if isinstance(environment, dict) else None,
        "orchestrator": "docker-swarm",
        "isolation": "setupmno-hml",
    } or environment["platform"] not in PLATFORMS:
        raise RunnerError("ambiente candidato inválido")
    artifact = candidate["artifact"]
    expected_prefix = "x86" if candidate["architecture"] == "amd64" else "arm"
    if (
        not isinstance(artifact, dict)
        or set(artifact) != {"path", "sha256"}
        or not re.fullmatch(rf"{expected_prefix}/SetupLowCodeMno/[a-z0-9_-]+\.sh", str(artifact.get("path", "")))
        or not SHA256_RE.fullmatch(str(artifact.get("sha256", "")))
    ):
        raise RunnerError("artefato candidato inválido")
    images = candidate["images"]
    if (
        not isinstance(images, list)
        or not images
        or len(images) != len(set(images))
        or not all(isinstance(image, str) and IMAGE_RE.fullmatch(image) for image in images)
    ):
        raise RunnerError("imagens devem estar fixadas por digest SHA-256")
    checks = candidate["checks"]
    if not isinstance(checks, dict) or set(checks) != set(CHECKS):
        raise RunnerError("conjunto de checks candidato inválido")
    for name in CHECKS:
        item = checks[name]
        if not isinstance(item, dict) or set(item) != {"status", "evidence"}:
            raise RunnerError(f"estrutura inválida no check {name}")
        check_record(str(item["status"]), str(item["evidence"]))
    if any(checks[name]["status"] != "passed" for name in OPERATIONAL_CHECKS):
        raise RunnerError("candidato não passou todos os checks operacionais")
    all_passed = all(checks[name]["status"] == "passed" for name in CHECKS)
    expected_result = "candidate-full" if all_passed else "candidate-operational"
    if candidate["result"] != expected_result:
        raise RunnerError("resultado candidato diverge dos checks")
    if candidate["submission"] != {
        "status": "pending-maintainer-review",
        "automaticPromotion": False,
        "officialSeal": False,
    }:
        raise RunnerError("candidato tentou ultrapassar a revisão do mantenedor")
    reject_sensitive(candidate)
    return candidate


def deterministic_bundle(candidate_data: bytes, manifest_data: bytes) -> bytes:
    memory = io.BytesIO()
    with tarfile.open(fileobj=memory, mode="w", format=tarfile.PAX_FORMAT) as archive:
        for name, data in (("candidate.json", candidate_data), ("manifest.json", manifest_data)):
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = 0o600
            info.mtime = 0
            info.uid = 0
            info.gid = 0
            info.uname = ""
            info.gname = ""
            archive.addfile(info, io.BytesIO(data))
    compressed = io.BytesIO()
    with gzip.GzipFile(filename="", mode="wb", fileobj=compressed, mtime=0, compresslevel=9) as stream:
        stream.write(memory.getvalue())
    data = compressed.getvalue()
    if len(data) > MAX_BUNDLE_BYTES:
        raise RunnerError("bundle candidato excede o limite de tamanho")
    return data


def read_bundle(path: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    data = ensure_regular(path, MAX_BUNDLE_BYTES)
    try:
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
            members = archive.getmembers()
            if [member.name for member in members] != ["candidate.json", "manifest.json"]:
                raise RunnerError("bundle contém inventário inesperado")
            if any(not member.isfile() or member.issym() or member.islnk() for member in members):
                raise RunnerError("bundle contém entrada não regular")
            payloads = {
                member.name: archive.extractfile(member).read()  # type: ignore[union-attr]
                for member in members
            }
    except (tarfile.TarError, EOFError) as exc:
        raise RunnerError("bundle candidato inválido") from exc
    try:
        candidate = json.loads(payloads["candidate.json"])
        manifest = json.loads(payloads["manifest.json"])
    except json.JSONDecodeError as exc:
        raise RunnerError("bundle contém JSON inválido") from exc
    if not isinstance(manifest, dict) or set(manifest) != {
        "schemaVersion", "kind", "runnerVersion", "candidateId", "candidateSHA256",
        "candidateBytes", "createdAt", "automaticPromotion", "officialSeal",
    }:
        raise RunnerError("manifesto candidato inválido")
    if (
        manifest["schemaVersion"] != 1
        or manifest["kind"] != "setupmno-homologation-candidate-bundle"
        or manifest["runnerVersion"] not in SUPPORTED_RUNNER_VERSIONS
        or manifest["runnerVersion"] != candidate.get("runnerVersion")
        or manifest["candidateSHA256"] != sha256_bytes(payloads["candidate.json"])
        or manifest["candidateBytes"] != len(payloads["candidate.json"])
        or manifest["automaticPromotion"] is not False
        or manifest["officialSeal"] is not False
    ):
        raise RunnerError("integridade ou fronteira de confiança do bundle inválida")
    validate_candidate(candidate)
    if manifest["candidateId"] != candidate["candidateId"] or manifest["createdAt"] != candidate["createdAt"]:
        raise RunnerError("manifesto não corresponde ao candidato")
    return candidate, manifest


def command_list(args: argparse.Namespace) -> None:
    manifest, registry = validate_package(package_directory(args))
    print(f"Setup MNO {manifest['setupVersion']} · Homologation Runner {RUNNER_VERSION}")
    for entry in registry["entries"]:
        print(f"{entry['setupId']}\t{entry['catalogName']}\t{','.join(entry['architectures'])}")


def command_init(args: argparse.Namespace) -> None:
    manifest, registry = validate_package(package_directory(args))
    entries = registry_by_id(registry)
    entry = entries.get(args.setup_id)
    if entry is None:
        raise RunnerError("setup não existe no registro canônico do runner")
    if args.architecture not in entry["architectures"]:
        raise RunnerError("arquitetura não declarada para este setup")
    selected_platform = args.platform or default_platform()
    if selected_platform not in PLATFORMS:
        raise RunnerError("plataforma não suportada")
    if not args.skip_docker_preflight:
        docker_preflight(args.architecture)
    created_at = parse_datetime(args.created_at) if args.created_at else utc_now()
    run_id = f"setupmno-hml-{args.setup_id}-{created_at.strftime('%y%m%d%H%M%S')}"
    if not RUN_ID_RE.fullmatch(run_id):
        raise RunnerError("identificador de execução inválido")
    output_parent = Path(args.output_dir).resolve()
    if output_parent.exists() and (output_parent.is_symlink() or not output_parent.is_dir()):
        raise RunnerError("diretório pai de saída é inseguro")
    output_parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    work_dir = output_parent / run_id
    if work_dir.exists():
        raise RunnerError("execução já existe; não haverá sobrescrita")
    work_dir.mkdir(mode=0o700)
    session = {
        "schemaVersion": 1,
        "kind": "setupmno-homologation-session",
        "runId": run_id,
        "runnerVersion": RUNNER_VERSION,
        "setupId": args.setup_id,
        "setupVersion": manifest["setupVersion"],
        "architecture": args.architecture,
        "createdAt": iso_z(created_at),
        "environment": {
            "platform": selected_platform,
            "orchestrator": "docker-swarm",
            "isolation": "setupmno-hml",
        },
        "artifact": entry["artifacts"][args.architecture],
        "checks": {
            name: {
                "status": "not-tested",
                "evidence": "Aguardando registro explícito do testador.",
            }
            for name in CHECKS
        },
    }
    atomic_write(work_dir / "session.json", canonical_json(session))
    print(work_dir / "session.json")


def load_session(path: Path) -> dict[str, Any]:
    session = load_json(path)
    required = {
        "schemaVersion", "kind", "runId", "runnerVersion", "setupId", "setupVersion",
        "architecture", "createdAt", "environment", "artifact", "checks",
    }
    if (
        not isinstance(session, dict)
        or set(session) != required
        or session["schemaVersion"] != 1
        or session["kind"] != "setupmno-homologation-session"
        or session["runnerVersion"] != RUNNER_VERSION
        or not RUN_ID_RE.fullmatch(str(session["runId"]))
        or not ID_RE.fullmatch(str(session["setupId"]))
        or session["architecture"] not in ARCHITECTURES
        or not isinstance(session["checks"], dict)
        or set(session["checks"]) != set(CHECKS)
    ):
        raise RunnerError("sessão de homologação inválida")
    parse_datetime(session["createdAt"])
    for name in CHECKS:
        item = session["checks"][name]
        if not isinstance(item, dict):
            raise RunnerError(f"check inválido na sessão: {name}")
        check_record(str(item.get("status", "")), str(item.get("evidence", "")))
    reject_sensitive(session, "sessão")
    return session


def command_record(args: argparse.Namespace) -> None:
    session_path = Path(args.session).resolve()
    if session_path.is_symlink():
        raise RunnerError("sessão não pode ser symlink")
    session = load_session(session_path)
    session["checks"][args.check] = check_record(args.status, args.evidence)
    atomic_write(session_path, canonical_json(session))
    print(f"{args.check}: {args.status}")


def command_finalize(args: argparse.Namespace) -> None:
    package_manifest, registry = validate_package(package_directory(args))
    entries = registry_by_id(registry)
    session_path = Path(args.session).resolve()
    session = load_session(session_path)
    entry = entries.get(session["setupId"])
    if entry is None or session["setupVersion"] != package_manifest["setupVersion"]:
        raise RunnerError("sessão pertence a outra release do runner")
    if session["artifact"] != entry["artifacts"].get(session["architecture"]):
        raise RunnerError("artefato da sessão diverge do registro assinado da release")
    tester = " ".join(args.tester.split())
    if not 2 <= len(tester) <= 80 or not DISPLAY_NAME_RE.fullmatch(tester):
        raise RunnerError("use um nome público sem e-mail, token ou caracteres especiais")
    images = sorted(set(args.image))
    if not images or not all(IMAGE_RE.fullmatch(image) for image in images):
        raise RunnerError("informe ao menos uma imagem no formato repositorio@sha256:digest")
    if any(session["checks"][name]["status"] != "passed" for name in OPERATIONAL_CHECKS):
        raise RunnerError("todos os checks operacionais precisam estar como passed")
    all_passed = all(session["checks"][name]["status"] == "passed" for name in CHECKS)
    execution_stamp = session["runId"].rsplit("-", 1)[-1]
    candidate_id = f"{session['setupId']}-{session['architecture']}-{execution_stamp}-candidate"
    candidate = {
        "schemaVersion": CANDIDATE_SCHEMA_VERSION,
        "kind": "setupmno-homologation-candidate",
        "candidateId": candidate_id,
        "runId": session["runId"],
        "runnerVersion": RUNNER_VERSION,
        "setupId": session["setupId"],
        "setupVersion": session["setupVersion"],
        "architecture": session["architecture"],
        "createdAt": session["createdAt"],
        "tester": {"displayName": tester, "attestation": "self-attested"},
        "environment": session["environment"],
        "artifact": session["artifact"],
        "images": images,
        "checks": session["checks"],
        "result": "candidate-full" if all_passed else "candidate-operational",
        "sanitized": True,
        "submission": {
            "status": "pending-maintainer-review",
            "automaticPromotion": False,
            "officialSeal": False,
        },
    }
    validate_candidate(candidate)
    candidate_data = canonical_json(candidate)
    manifest = {
        "schemaVersion": 1,
        "kind": "setupmno-homologation-candidate-bundle",
        "runnerVersion": RUNNER_VERSION,
        "candidateId": candidate_id,
        "candidateSHA256": sha256_bytes(candidate_data),
        "candidateBytes": len(candidate_data),
        "createdAt": session["createdAt"],
        "automaticPromotion": False,
        "officialSeal": False,
    }
    manifest_data = canonical_json(manifest)
    bundle_data = deterministic_bundle(candidate_data, manifest_data)
    output = Path(args.output).resolve() if args.output else session_path.parent / f"{candidate_id}.tar.gz"
    if output.exists():
        raise RunnerError("bundle já existe; não haverá sobrescrita")
    atomic_write(output, bundle_data)
    print(json.dumps({
        "bundle": str(output),
        "sha256": sha256_bytes(bundle_data),
        "result": candidate["result"],
        "officialSeal": False,
        "status": "pending-maintainer-review",
    }, ensure_ascii=False, sort_keys=True))


def command_verify(args: argparse.Namespace) -> None:
    candidate, _ = read_bundle(Path(args.bundle).resolve())
    package_manifest, registry = validate_package(package_directory(args))
    entry = registry_by_id(registry).get(candidate["setupId"])
    if (
        entry is None
        or candidate["setupVersion"] != package_manifest["setupVersion"]
        or candidate["architecture"] not in entry["architectures"]
        or candidate["artifact"] != entry["artifacts"][candidate["architecture"]]
    ):
        raise RunnerError("candidato diverge do pacote canônico informado")
    print(json.dumps({
        "candidateId": candidate["candidateId"],
        "setupId": candidate["setupId"],
        "setupVersion": candidate["setupVersion"],
        "architecture": candidate["architecture"],
        "result": candidate["result"],
        "status": "pending-maintainer-review",
        "officialSeal": False,
        "bundleSHA256": sha256_file(Path(args.bundle).resolve()),
    }, ensure_ascii=False, sort_keys=True))


def command_review(args: argparse.Namespace) -> None:
    candidate, _ = read_bundle(Path(args.bundle).resolve())
    package_manifest, registry = validate_package(package_directory(args))
    entry = registry_by_id(registry).get(candidate["setupId"])
    if (
        entry is None
        or candidate["setupVersion"] != package_manifest["setupVersion"]
        or candidate["artifact"] != entry["artifacts"].get(candidate["architecture"])
    ):
        raise RunnerError("revisão recusada: candidato diverge da release canônica")
    reviewer = " ".join(args.reviewer.split())
    if not 2 <= len(reviewer) <= 80 or not DISPLAY_NAME_RE.fullmatch(reviewer):
        raise RunnerError("identidade pública do revisor inválida")
    reviewed_at = dt.date.fromisoformat(args.reviewed_at) if args.reviewed_at else dt.date.today()
    verified_at = parse_datetime(candidate["createdAt"])
    if reviewed_at < verified_at.date():
        raise RunnerError("revisão não pode anteceder a execução")
    evidence = {
        "schemaVersion": 1,
        "evidenceId": candidate["candidateId"].removesuffix("-candidate"),
        "setupId": candidate["setupId"],
        "setupVersion": candidate["setupVersion"],
        "architecture": candidate["architecture"],
        "verifiedAt": candidate["createdAt"],
        "environment": candidate["environment"],
        "artifact": candidate["artifact"],
        "images": candidate["images"],
        "checks": candidate["checks"],
        "result": "passed",
        "sanitized": True,
        "review": {
            "decision": "approved",
            "reviewedBy": reviewer,
            "reviewedAt": reviewed_at.isoformat(),
        },
    }
    reject_sensitive(evidence, "evidência revisada")
    output = Path(args.output).resolve()
    if output.exists():
        raise RunnerError("evidência revisada já existe; não haverá sobrescrita")
    atomic_write(output, canonical_json(evidence))
    print(json.dumps({
        "evidence": str(output),
        "sha256": sha256_file(output),
        "governanceUpdated": False,
        "officialSeal": False,
        "nextStep": "revisão de código e inclusão explícita na governança canônica",
    }, ensure_ascii=False, sort_keys=True))


def deterministic_review_pack(entries: list[tuple[str, bytes]]) -> bytes:
    memory = io.BytesIO()
    with tarfile.open(fileobj=memory, mode="w", format=tarfile.PAX_FORMAT) as archive:
        for name, data in entries:
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = 0o600
            info.mtime = 0
            info.uid = 0
            info.gid = 0
            info.uname = ""
            info.gname = ""
            archive.addfile(info, io.BytesIO(data))
    compressed = io.BytesIO()
    with gzip.GzipFile(filename="", mode="wb", fileobj=compressed, mtime=0, compresslevel=9) as stream:
        stream.write(memory.getvalue())
    payload = compressed.getvalue()
    if len(payload) > MAX_REVIEW_PACK_BYTES:
        raise RunnerError("pacote de revisão excede o limite de tamanho")
    return payload


def command_decide(args: argparse.Namespace) -> None:
    bundle_path = Path(args.bundle).resolve()
    candidate, _ = read_bundle(bundle_path)
    package_manifest, registry = validate_package(package_directory(args))
    entry = registry_by_id(registry).get(candidate["setupId"])
    if entry is None or candidate["artifact"] != entry["artifacts"].get(candidate["architecture"]):
        raise RunnerError("decisão recusada: o instalador atual diverge do artefato testado")
    reviewer = " ".join(args.reviewer.split())
    reason = " ".join(args.reason.split())
    if not 2 <= len(reviewer) <= 80 or not DISPLAY_NAME_RE.fullmatch(reviewer):
        raise RunnerError("identidade pública do revisor inválida")
    if args.reason_code not in REASON_CODES or not 3 <= len(reason) <= 240:
        raise RunnerError("decisão exige motivo permitido e justificativa entre 3 e 240 caracteres")
    if args.decision == "approved" and args.reason_code != "operational-evidence-accepted":
        raise RunnerError("aprovação exige o motivo operational-evidence-accepted")
    if args.decision == "rejected" and args.reason_code == "operational-evidence-accepted":
        raise RunnerError("rejeição exige um motivo de recusa")
    reject_sensitive(reason, "justificativa da decisão")
    reviewed_at = parse_datetime(args.reviewed_at) if args.reviewed_at else utc_now()
    verified_at = parse_datetime(candidate["createdAt"])
    if reviewed_at < verified_at:
        raise RunnerError("decisão não pode anteceder a execução")
    decision_id = f"{candidate['candidateId'].removesuffix('-candidate')}-review-{reviewed_at.strftime('%y%m%d%H%M%S')}"
    decision = {
        "schemaVersion": 1,
        "kind": "setupmno-homologation-review-decision",
        "decisionId": decision_id,
        "candidateId": candidate["candidateId"],
        "candidateBundleSHA256": sha256_file(bundle_path),
        "decision": args.decision,
        "reasonCode": args.reason_code,
        "reason": reason,
        "reviewedBy": reviewer,
        "reviewedAt": iso_z(reviewed_at),
        "immutable": True,
        "governanceUpdated": False,
        "officialSeal": False,
    }
    reject_sensitive(decision, "decisão")
    decision_data = canonical_json(decision)
    decision_output = Path(args.decision_output).resolve()
    if decision_output.exists():
        raise RunnerError("já existe uma decisão imutável para este candidato")

    evidence_output: Path | None = None
    review_pack_output: Path | None = None
    evidence_data = b""
    if args.decision == "approved":
        if not args.evidence_output or not args.review_pack_output:
            raise RunnerError("aprovação exige saídas para evidência e pacote de revisão")
        evidence_output = Path(args.evidence_output).resolve()
        review_pack_output = Path(args.review_pack_output).resolve()
        if evidence_output.exists() or review_pack_output.exists():
            raise RunnerError("evidência ou pacote de revisão já existe; não haverá sobrescrita")
        evidence = {
            "schemaVersion": 1,
            "evidenceId": candidate["candidateId"].removesuffix("-candidate"),
            "setupId": candidate["setupId"],
            "setupVersion": candidate["setupVersion"],
            "architecture": candidate["architecture"],
            "verifiedAt": candidate["createdAt"],
            "environment": candidate["environment"],
            "artifact": candidate["artifact"],
            "images": candidate["images"],
            "checks": candidate["checks"],
            "result": "passed",
            "sanitized": True,
            "review": {
                "decision": "approved",
                "reviewedBy": reviewer,
                "reviewedAt": reviewed_at.date().isoformat(),
            },
        }
        reject_sensitive(evidence, "evidência revisada")
        evidence_data = canonical_json(evidence)
        bundle_data = ensure_regular(bundle_path, MAX_BUNDLE_BYTES)
        manifest = {
            "schemaVersion": 1,
            "kind": "setupmno-homologation-review-pack",
            "candidateId": candidate["candidateId"],
            "createdAt": iso_z(reviewed_at),
            "files": [
                {"path": "candidate.tar.gz", "sha256": sha256_bytes(bundle_data), "size": len(bundle_data)},
                {"path": "decision.json", "sha256": sha256_bytes(decision_data), "size": len(decision_data)},
                {"path": "operational-evidence.json", "sha256": sha256_bytes(evidence_data), "size": len(evidence_data)},
            ],
            "automaticPromotion": False,
            "governanceUpdated": False,
            "officialSeal": False,
        }
        manifest_data = canonical_json(manifest)
        review_pack_data = deterministic_review_pack([
            ("candidate.tar.gz", bundle_data),
            ("decision.json", decision_data),
            ("operational-evidence.json", evidence_data),
            ("manifest.json", manifest_data),
        ])
        atomic_write(evidence_output, evidence_data)
        try:
            atomic_write(review_pack_output, review_pack_data)
        except Exception:
            evidence_output.unlink(missing_ok=True)
            raise

    try:
        atomic_write(decision_output, decision_data)
    except Exception:
        if evidence_output is not None:
            evidence_output.unlink(missing_ok=True)
        if review_pack_output is not None:
            review_pack_output.unlink(missing_ok=True)
        raise
    print(json.dumps({
        "candidateId": candidate["candidateId"],
        "decision": args.decision,
        "decisionFile": str(decision_output),
        "evidence": str(evidence_output) if evidence_output else None,
        "reviewPack": str(review_pack_output) if review_pack_output else None,
        "governanceUpdated": False,
        "officialSeal": False,
        "nextStep": "importação canônica com dry-run" if evidence_output else "corrigir e executar uma nova sessão",
    }, ensure_ascii=False, sort_keys=True))


def command_seal_essential(args: argparse.Namespace) -> None:
    """Concede selo operacional por arquitetura após gates automáticos e atestação."""
    bundle_path = Path(args.bundle).resolve()
    decision_path = Path(args.decision).resolve()
    candidate, _ = read_bundle(bundle_path)
    decision = load_json(decision_path)
    expected_decision_keys = {
        "schemaVersion", "kind", "decisionId", "candidateId",
        "candidateBundleSHA256", "decision", "reasonCode", "reason",
        "reviewedBy", "reviewedAt", "immutable", "governanceUpdated",
        "officialSeal",
    }
    if (
        not isinstance(decision, dict)
        or set(decision) != expected_decision_keys
        or decision.get("schemaVersion") != 1
        or decision.get("kind") != "setupmno-homologation-review-decision"
        or decision.get("candidateId") != candidate["candidateId"]
        or decision.get("candidateBundleSHA256") != sha256_file(bundle_path)
        or decision.get("decision") != "approved"
        or decision.get("reasonCode") != "operational-evidence-accepted"
        or decision.get("immutable") is not True
        or decision.get("governanceUpdated") is not False
        or decision.get("officialSeal") is not False
    ):
        raise RunnerError("decisão aprovada não corresponde ao candidato")
    if any(candidate["checks"][name]["status"] != "passed" for name in OPERATIONAL_CHECKS):
        raise RunnerError("os gates essenciais não estão aprovados")
    maintainer = " ".join(args.maintainer.split())
    if not 2 <= len(maintainer) <= 80 or not DISPLAY_NAME_RE.fullmatch(maintainer):
        raise RunnerError("identificação pública do mantenedor inválida")
    package_manifest, registry = validate_package(package_directory(args))
    entry = registry_by_id(registry).get(candidate["setupId"])
    if (
        entry is None
        or candidate["setupVersion"] != package_manifest["setupVersion"]
        or candidate["artifact"] != entry["artifacts"].get(candidate["architecture"])
    ):
        raise RunnerError("o candidato não corresponde ao instalador atual")
    issued_at = iso_z(utc_now())
    seal_id = candidate["candidateId"].removesuffix("-candidate") + "-essential-seal"
    seal = {
        "schemaVersion": 1,
        "kind": "setupmno-essential-homologation-seal",
        "sealId": seal_id,
        "candidateId": candidate["candidateId"],
        "setupId": candidate["setupId"],
        "setupVersion": candidate["setupVersion"],
        "architecture": candidate["architecture"],
        "issuedAt": issued_at,
        "issuedBy": maintainer,
        "scope": "essential-startup",
        "artifact": candidate["artifact"],
        "images": candidate["images"],
        "checks": {name: candidate["checks"][name] for name in OPERATIONAL_CHECKS},
        "candidateBundleSHA256": sha256_file(bundle_path),
        "decisionSHA256": sha256_file(decision_path),
        "status": "issued",
        "immutable": True,
        "maintainerAttested": True,
        "automaticPublication": False,
        "officialSeal": True,
    }
    reject_sensitive(seal, "selo essencial")
    output = Path(args.output).resolve()
    if output.exists():
        raise RunnerError("selo essencial já existe; não haverá sobrescrita")
    if output.parent != bundle_path.parent:
        raise RunnerError("selo essencial deve permanecer junto do candidato")
    atomic_write(output, canonical_json(seal))
    print(json.dumps({
        "seal": str(output),
        "sealId": seal_id,
        "sha256": sha256_file(output),
        "setupId": candidate["setupId"],
        "setupVersion": candidate["setupVersion"],
        "architecture": candidate["architecture"],
        "scope": "essential-startup",
        "officialSeal": True,
        "automaticPublication": False,
    }, ensure_ascii=False, sort_keys=True))


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(
        description="Homologation Runner do Setup MNO: concede Selo Essencial por arquitetura sem publicar releases."
    )
    root.add_argument("--package-dir", help="pacote canônico do runner; padrão: diretório deste arquivo")
    subparsers = root.add_subparsers(dest="command", required=True)

    list_parser = subparsers.add_parser("list", help="listar setups e arquiteturas aceitas")
    list_parser.set_defaults(handler=command_list)

    init_parser = subparsers.add_parser("init", help="iniciar sessão isolada de coleta")
    init_parser.add_argument("--setup-id", required=True)
    init_parser.add_argument("--architecture", choices=sorted(ARCHITECTURES), required=True)
    init_parser.add_argument("--platform", choices=sorted(PLATFORMS))
    init_parser.add_argument("--output-dir", required=True)
    init_parser.add_argument("--created-at", help=argparse.SUPPRESS)
    init_parser.add_argument("--skip-docker-preflight", action="store_true", help=argparse.SUPPRESS)
    init_parser.set_defaults(handler=command_init)

    record_parser = subparsers.add_parser("record", help="registrar resultado de um check permitido")
    record_parser.add_argument("--session", required=True)
    record_parser.add_argument("--check", choices=CHECKS, required=True)
    record_parser.add_argument("--status", choices=sorted(STATUSES), required=True)
    record_parser.add_argument("--evidence", required=True)
    record_parser.set_defaults(handler=command_record)

    inspect_parser = subparsers.add_parser(
        "inspect", help="executar gates essenciais automáticos e somente leitura"
    )
    inspect_parser.add_argument("--session", required=True)
    inspect_parser.add_argument("--service", required=True)
    inspect_parser.add_argument("--url", default="")
    inspect_parser.set_defaults(handler=command_inspect)

    finalize_parser = subparsers.add_parser("finalize", help="gerar bundle candidato sanitizado")
    finalize_parser.add_argument("--session", required=True)
    finalize_parser.add_argument("--image", action="append", required=True)
    finalize_parser.add_argument("--tester", required=True)
    finalize_parser.add_argument("--output")
    finalize_parser.set_defaults(handler=command_finalize)

    verify_parser = subparsers.add_parser("verify", help="verificar integridade de um bundle candidato")
    verify_parser.add_argument("--bundle", required=True)
    verify_parser.set_defaults(handler=command_verify)

    review_parser = subparsers.add_parser("review", help="converter candidato após revisão humana")
    review_parser.add_argument("--bundle", required=True)
    review_parser.add_argument("--reviewer", required=True)
    review_parser.add_argument("--reviewed-at")
    review_parser.add_argument("--output", required=True)
    review_parser.set_defaults(handler=command_review)

    decide_parser = subparsers.add_parser("decide", help="registrar decisão imutável e gerar pacote revisado")
    decide_parser.add_argument("--bundle", required=True)
    decide_parser.add_argument("--reviewer", required=True)
    decide_parser.add_argument("--decision", choices=["approved", "rejected"], required=True)
    decide_parser.add_argument("--reason-code", choices=sorted(REASON_CODES), required=True)
    decide_parser.add_argument("--reason", required=True)
    decide_parser.add_argument("--reviewed-at", help=argparse.SUPPRESS)
    decide_parser.add_argument("--decision-output", required=True)
    decide_parser.add_argument("--evidence-output")
    decide_parser.add_argument("--review-pack-output")
    decide_parser.set_defaults(handler=command_decide)

    seal_parser = subparsers.add_parser(
        "seal-essential", help="conceder selo essencial por arquitetura"
    )
    seal_parser.add_argument("--bundle", required=True)
    seal_parser.add_argument("--decision", required=True)
    seal_parser.add_argument("--maintainer", required=True)
    seal_parser.add_argument("--output", required=True)
    seal_parser.set_defaults(handler=command_seal_essential)
    return root


def main(argv: list[str] | None = None) -> int:
    arguments = parser().parse_args(argv)
    try:
        arguments.handler(arguments)
    except (RunnerError, OSError, ValueError) as exc:
        print(f"ERRO: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
