#!/usr/bin/env python3
"""Gate determinístico para candidatos a skill externa do Setup MNO."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shlex
import stat
import sys
import tempfile
from pathlib import Path
from urllib.parse import urlparse


SCHEMA_VERSION = 1
MAX_MANIFEST_BYTES = 256 * 1024
MAX_FILE_BYTES = 1024 * 1024
MAX_TOTAL_BYTES = 4 * 1024 * 1024
MAX_FILES = 256
ALLOWED_LICENSES = {
    "Apache-2.0",
    "BSD-2-Clause",
    "BSD-3-Clause",
    "GPL-2.0-only",
    "GPL-2.0-or-later",
    "GPL-3.0-only",
    "GPL-3.0-or-later",
    "LGPL-2.1-only",
    "LGPL-2.1-or-later",
    "LGPL-3.0-only",
    "LGPL-3.0-or-later",
    "MIT",
    "MPL-2.0",
}
ALLOWED_RISKS = {"low", "medium", "high", "critical"}
ALLOWED_NETWORK = {"none", "declared-only"}
FORBIDDEN_FLOATING_VERSIONS = {"latest", "main", "master", "head", "*", "dev"}
FORBIDDEN_COMMANDS = {"docker", "sudo", "su", "mount", "umount", "systemctl", "service"}
SHELL_BUILTINS = {
    ".", "[", "alias", "break", "case", "cd", "continue", "declare", "do", "done",
    "echo", "elif", "else", "esac", "eval", "exec", "exit", "export", "false", "fi",
    "for", "function", "getopts", "if", "in", "local", "printf", "read", "readonly",
    "return", "set", "shift", "source", "test", "then", "time", "trap", "true", "typeset",
    "ulimit", "umask", "unalias", "unset", "until", "wait", "while",
}
URL_RE = re.compile(r"https?://[^\s<>'\"`)}\]]+")
SECRET_PATTERNS = (
    (re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"), "private-key"),
    (re.compile(r"\bcfut_[A-Za-z0-9_-]{20,}\b"), "cloudflare-token"),
    (re.compile(r"\bsk-[A-Za-z0-9_-]{20,}\b"), "api-key"),
)
SCRIPT_PATTERNS = (
    (re.compile(r"(?:curl|wget)[^\n|]*\|\s*(?:ba)?sh\b", re.I), "download-piped-to-shell", "critical"),
    (re.compile(r"\beval\s+", re.I), "dynamic-eval", "high"),
    (re.compile(r"\brm\s+-[^\n]*r[^\n]*f|\brm\s+-rf\b", re.I), "recursive-force-delete", "critical"),
    (re.compile(r"/var/run/docker\.sock"), "docker-socket", "critical"),
    (re.compile(r"\bsudo\b"), "sudo", "critical"),
    (re.compile(r"\bchmod\s+777\b"), "world-writable", "high"),
    (re.compile(r"(?:^|[;&|]\s*)(?:bash|sh)\s+-c\b", re.M), "dynamic-shell", "high"),
)


class GateError(Exception):
    pass


def canonical_json(value: object) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def regular_file(path: Path, label: str, maximum: int = MAX_FILE_BYTES) -> None:
    if path.is_symlink() or not path.is_file():
        raise GateError(f"{label} deve ser arquivo regular sem symlink: {path}")
    size = path.stat().st_size
    if size <= 0 or size > maximum:
        raise GateError(f"{label} possui tamanho inválido ({size} bytes): {path}")


def safe_relative(value: object, label: str) -> str:
    if not isinstance(value, str) or not value or "\\" in value:
        raise GateError(f"{label} inválido")
    candidate = Path(value)
    if candidate.is_absolute() or ".." in candidate.parts or value.startswith("./"):
        raise GateError(f"{label} contém caminho inseguro: {value}")
    normalized = candidate.as_posix()
    if normalized != value or any(not part or part in {".", ".."} for part in candidate.parts):
        raise GateError(f"{label} não está normalizado: {value}")
    return normalized


def require_bool(mapping: dict, field: str) -> bool:
    value = mapping.get(field)
    if not isinstance(value, bool):
        raise GateError(f"permissions.{field} deve ser booleano")
    return value


def require_exact_keys(mapping: dict, required: set[str], label: str) -> None:
    missing = sorted(required - set(mapping))
    extra = sorted(set(mapping) - required)
    if missing or extra:
        raise GateError(f"campos inválidos em {label}; ausentes={missing}, extras={extra}")


def require_string_list(mapping: dict, field: str) -> list[str]:
    value = mapping.get(field)
    if not isinstance(value, list) or any(not isinstance(item, str) or not item.strip() for item in value):
        raise GateError(f"{field} deve ser lista de strings não vazias")
    if len(value) != len(set(value)):
        raise GateError(f"{field} possui itens duplicados")
    return value


def validate_https_url(value: object, label: str, github_only: bool = False) -> str:
    if not isinstance(value, str):
        raise GateError(f"{label} deve ser URL")
    parsed = urlparse(value)
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or parsed.username
        or parsed.password
        or parsed.query
        or parsed.fragment
    ):
        raise GateError(f"{label} deve usar HTTPS, sem credencial, parâmetros ou fragmento: {value}")
    if github_only and parsed.hostname != "github.com":
        raise GateError(f"{label} deve apontar para github.com nesta versão do gate")
    return value.rstrip("/")


def inventory_files(root: Path) -> dict[str, Path]:
    files: dict[str, Path] = {}
    total = 0
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root).as_posix()
        if path.is_symlink():
            raise GateError(f"symlink proibido no candidato: {relative}")
        if path.is_dir():
            continue
        if not path.is_file():
            raise GateError(f"entrada não regular no candidato: {relative}")
        if relative == "skill-manifest.json":
            continue
        safe_relative(relative, "arquivo")
        size = path.stat().st_size
        if size <= 0 or size > MAX_FILE_BYTES:
            raise GateError(f"arquivo com tamanho inválido ({size} bytes): {relative}")
        total += size
        files[relative] = path
    if not files or len(files) > MAX_FILES or total > MAX_TOTAL_BYTES:
        raise GateError(f"inventário fora dos limites: files={len(files)} bytes={total}")
    return files


def validate_manifest(manifest: dict, root: Path, actual: dict[str, Path]) -> dict:
    require_exact_keys(
        manifest,
        {
            "schemaVersion", "skillId", "version", "maturity", "maintainerPlan",
            "source", "entrypoint", "urls", "dependencies", "permissions",
            "actions", "files",
        },
        "manifesto",
    )
    if manifest.get("schemaVersion") != SCHEMA_VERSION:
        raise GateError("schemaVersion deve ser 1")
    skill_id = manifest.get("skillId")
    if not isinstance(skill_id, str) or not re.fullmatch(r"[a-z0-9][a-z0-9-]{1,63}", skill_id):
        raise GateError("skillId inválido")
    if not re.fullmatch(r"\d+\.\d+\.\d+", str(manifest.get("version", ""))):
        raise GateError("version deve usar SemVer exato")
    if manifest.get("maturity") != "candidate" or manifest.get("maintainerPlan") != "pro-master":
        raise GateError("candidato deve declarar maturity=candidate e maintainerPlan=pro-master")

    source = manifest.get("source")
    if not isinstance(source, dict):
        raise GateError("source ausente")
    require_exact_keys(source, {"repository", "commit", "license", "licenseFile"}, "source")
    repository = validate_https_url(source.get("repository"), "source.repository", github_only=True)
    commit = source.get("commit")
    if not isinstance(commit, str) or not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise GateError("source.commit deve ser SHA Git completo de 40 caracteres")
    license_id = source.get("license")
    if license_id not in ALLOWED_LICENSES:
        raise GateError("licença ausente ou fora da allowlist SPDX suportada")
    license_file = safe_relative(source.get("licenseFile"), "source.licenseFile")
    entrypoint = safe_relative(manifest.get("entrypoint"), "entrypoint")
    if entrypoint not in actual or license_file not in actual:
        raise GateError("entrypoint ou arquivo de licença não está no inventário")

    declared_files = manifest.get("files")
    if not isinstance(declared_files, list) or not declared_files:
        raise GateError("files deve possuir inventário estrito")
    declared: dict[str, dict] = {}
    for entry in declared_files:
        if not isinstance(entry, dict):
            raise GateError("entrada inválida em files")
        require_exact_keys(entry, {"path", "sha256", "size", "mode"}, "files")
        relative = safe_relative(entry.get("path"), "files.path")
        if relative in declared:
            raise GateError(f"arquivo duplicado no manifesto: {relative}")
        if not re.fullmatch(r"[0-9a-f]{64}", str(entry.get("sha256", ""))):
            raise GateError(f"sha256 inválido: {relative}")
        if not isinstance(entry.get("size"), int) or entry["size"] <= 0:
            raise GateError(f"size inválido: {relative}")
        if not isinstance(entry.get("mode"), str) or not re.fullmatch(r"0[0-7]{3}", entry["mode"]):
            raise GateError(f"mode inválido: {relative}")
        declared[relative] = entry
    if set(declared) != set(actual):
        raise GateError(
            f"inventário divergente; não declarados={sorted(set(actual) - set(declared))}, "
            f"ausentes={sorted(set(declared) - set(actual))}"
        )
    for relative, path in actual.items():
        entry = declared[relative]
        observed_mode = f"0{stat.S_IMODE(path.stat().st_mode):03o}"
        if entry["size"] != path.stat().st_size or entry["sha256"] != sha256_file(path) or entry["mode"] != observed_mode:
            raise GateError(f"tamanho, modo ou SHA-256 divergente: {relative}")

    urls = require_string_list(manifest, "urls") if manifest.get("urls") else []
    normalized_urls = {validate_https_url(url, "urls") for url in urls}
    if len(normalized_urls) != len(urls):
        raise GateError("urls possui duplicidade após normalização")

    dependencies = manifest.get("dependencies")
    if not isinstance(dependencies, list):
        raise GateError("dependencies deve ser lista")
    for dependency in dependencies:
        if not isinstance(dependency, dict) or not isinstance(dependency.get("name"), str):
            raise GateError("dependência inválida")
        require_exact_keys(dependency, {"name", "version", "source", "sha256"}, "dependencies")
        version = str(dependency.get("version", "")).strip()
        if not version or version.lower() in FORBIDDEN_FLOATING_VERSIONS:
            raise GateError(f"dependência flutuante: {dependency.get('name', '?')}")
        validate_https_url(dependency.get("source"), f"dependency.{dependency.get('name')}.source")
        if not re.fullmatch(r"[0-9a-f]{64}", str(dependency.get("sha256", ""))):
            raise GateError(f"dependência sem SHA-256: {dependency.get('name')}")

    permissions = manifest.get("permissions")
    if not isinstance(permissions, dict) or permissions.get("networkAccess") not in ALLOWED_NETWORK:
        raise GateError("permissions.networkAccess inválido")
    require_exact_keys(
        permissions,
        {
            "networkAccess", "filesystemRead", "filesystemWrite", "commands",
            "root", "sudo", "dockerSocket", "privileged", "hostNetwork", "secrets",
        },
        "permissions",
    )
    for field in ("root", "sudo", "dockerSocket", "privileged", "hostNetwork", "secrets"):
        require_bool(permissions, field)
    for field in ("filesystemRead", "filesystemWrite", "commands"):
        require_string_list(permissions, field) if permissions.get(field) else []

    actions = manifest.get("actions")
    if not isinstance(actions, list) or not actions:
        raise GateError("actions deve descrever ao menos uma capacidade")
    for action in actions:
        if not isinstance(action, dict):
            raise GateError("action inválida")
        require_exact_keys(action, {"id", "description", "risk", "mutatesSystem"}, "actions")
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", str(action.get("id", ""))):
            raise GateError("action.id inválido")
        if not isinstance(action.get("description"), str) or not action["description"].strip():
            raise GateError("action.description ausente")
        if action.get("risk") not in ALLOWED_RISKS or not isinstance(action.get("mutatesSystem"), bool):
            raise GateError(f"risco ou mutatesSystem inválido em {action.get('id', '?')}")

    return {
        "skillId": skill_id,
        "version": manifest["version"],
        "repository": repository,
        "commit": commit,
        "license": license_id,
        "entrypoint": entrypoint,
        "urls": sorted(normalized_urls),
        "permissions": permissions,
        "dependencies": dependencies,
        "actions": actions,
    }


def decode_text(path: Path) -> str | None:
    data = path.read_bytes()
    if b"\x00" in data:
        return None
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return None


def extract_shell_commands(body: str) -> set[str]:
    """Extrai executáveis aparentes sem executar ou expandir o shell."""
    commands: set[str] = set()
    for raw_line in body.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        for segment in re.split(r"(?:&&|\|\||[;|])", line):
            try:
                tokens = shlex.split(segment, comments=True, posix=True)
            except ValueError:
                continue
            while tokens and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", tokens[0]):
                tokens.pop(0)
            if not tokens:
                continue
            executable = Path(tokens[0]).name.lower()
            if executable and executable not in SHELL_BUILTINS and not executable.startswith("$"):
                commands.add(executable)
    return commands


def scan_candidate(
    summary: dict, actual: dict[str, Path]
) -> tuple[list[dict], list[dict], list[str], list[str]]:
    blockers: list[dict] = []
    warnings: list[dict] = []
    observed_urls: set[str] = set()
    observed_commands: set[str] = set()

    for field in ("root", "sudo", "dockerSocket", "privileged", "hostNetwork", "secrets"):
        if summary["permissions"][field]:
            blockers.append({"code": f"permission-{field}", "path": "skill-manifest.json", "detail": "permissão proibida para skill SRE externa"})
    for path in summary["permissions"].get("filesystemWrite", []):
        if path.startswith(("/", "~")):
            blockers.append({"code": "host-write", "path": "skill-manifest.json", "detail": f"escrita no host declarada: {path}"})
    for command in summary["permissions"].get("commands", []):
        executable = command.strip().split()[0].lower()
        if executable in FORBIDDEN_COMMANDS:
            blockers.append({"code": "forbidden-command", "path": "skill-manifest.json", "detail": f"comando proibido: {executable}"})
    for action in summary["actions"]:
        if action["mutatesSystem"]:
            blockers.append({"code": "mutating-action", "path": "skill-manifest.json", "detail": f"ação altera sistema: {action['id']}"})
        if action["risk"] in {"high", "critical"}:
            warnings.append({"code": "high-risk-action", "path": "skill-manifest.json", "detail": f"ação {action['id']} declara risco {action['risk']}"})

    for relative, path in actual.items():
        body = decode_text(path)
        if body is None:
            blockers.append({"code": "unreviewed-binary", "path": relative, "detail": "arquivo binário ou texto não UTF-8"})
            continue
        for pattern, label in SECRET_PATTERNS:
            if pattern.search(body):
                blockers.append({"code": label, "path": relative, "detail": "possível segredo incorporado"})
        for pattern, label, risk in SCRIPT_PATTERNS:
            if pattern.search(body):
                target = blockers if risk == "critical" else warnings
                target.append({"code": label, "path": relative, "detail": f"padrão estático de risco {risk}"})
        observed_urls.update(url.rstrip(".,;") for url in URL_RE.findall(body))
        if relative.endswith((".sh", ".bash")) or body.startswith("#!"):
            observed_commands.update(extract_shell_commands(body))

    allowed_urls = set(summary["urls"]) | {summary["repository"]}
    undeclared = sorted(url for url in observed_urls if url.rstrip("/") not in allowed_urls)
    for url in undeclared:
        blockers.append({"code": "undeclared-url", "path": "candidate", "detail": url})
    declared_commands = {
        Path(command.strip().split()[0]).name.lower()
        for command in summary["permissions"].get("commands", [])
    }
    for command in sorted(observed_commands - declared_commands):
        blockers.append({
            "code": "undeclared-command",
            "path": "candidate",
            "detail": f"comando encontrado mas não declarado: {command}",
        })
    if summary["permissions"]["networkAccess"] == "none" and summary["urls"]:
        blockers.append({"code": "network-contract", "path": "skill-manifest.json", "detail": "URLs declaradas com networkAccess=none"})
    if summary["permissions"]["networkAccess"] == "declared-only" and not summary["urls"]:
        warnings.append({"code": "network-empty", "path": "skill-manifest.json", "detail": "acesso de rede declarado sem URL operacional"})
    warnings.append({"code": "static-analysis-limit", "path": "candidate", "detail": "análise estática não prova ausência de comportamento malicioso"})
    return blockers, warnings, sorted(observed_urls), sorted(observed_commands)


def baseline_diff(actual: dict[str, Path], baseline: Path | None) -> dict[str, list[str]]:
    current_hashes = {name: sha256_file(path) for name, path in actual.items()}
    if baseline is None:
        return {"added": sorted(current_hashes), "modified": [], "removed": []}
    baseline = baseline.resolve(strict=True)
    baseline_actual = inventory_files(baseline)
    baseline_hashes = {name: sha256_file(path) for name, path in baseline_actual.items()}
    return {
        "added": sorted(set(current_hashes) - set(baseline_hashes)),
        "modified": sorted(name for name in set(current_hashes) & set(baseline_hashes) if current_hashes[name] != baseline_hashes[name]),
        "removed": sorted(set(baseline_hashes) - set(current_hashes)),
    }


def write_atomic(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def evaluate(candidate: Path, baseline: Path | None, approval_token: str | None) -> dict:
    candidate = candidate.resolve(strict=True)
    if candidate.is_symlink() or not candidate.is_dir():
        raise GateError("candidato deve ser diretório regular")
    manifest_path = candidate / "skill-manifest.json"
    regular_file(manifest_path, "manifesto", MAX_MANIFEST_BYTES)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if not isinstance(manifest, dict):
        raise GateError("manifesto deve ser objeto JSON")
    actual = inventory_files(candidate)
    summary = validate_manifest(manifest, candidate, actual)
    blockers, warnings, observed_urls, observed_commands = scan_candidate(summary, actual)

    digest_material = {
        "manifest": manifest,
        "files": [{"path": name, "sha256": sha256_file(path)} for name, path in sorted(actual.items())],
    }
    candidate_digest = sha256_bytes(canonical_json(digest_material))
    expected_token = f"APROVAR-{candidate_digest[:16].upper()}"
    decision = "blocked" if blockers else "awaiting-pro-master-review"
    if approval_token is not None:
        if blockers:
            raise GateError("candidato bloqueado não pode receber aprovação")
        if approval_token != expected_token:
            raise GateError("token de aprovação não corresponde ao candidato exato")
        decision = "approved-for-canonical-review"

    return {
        "schemaVersion": 1,
        "gateVersion": "1.0.0",
        "maturity": "beta",
        "dryRun": True,
        "decision": decision,
        "skill": {key: summary[key] for key in ("skillId", "version", "repository", "commit", "license", "entrypoint")},
        "candidateSHA256": candidate_digest,
        "fileCount": len(actual),
        "totalBytes": sum(path.stat().st_size for path in actual.values()),
        "observedURLs": observed_urls,
        "observedCommands": observed_commands,
        "permissions": summary["permissions"],
        "dependencies": summary["dependencies"],
        "actions": summary["actions"],
        "diff": baseline_diff(actual, baseline),
        "blockers": blockers,
        "warnings": warnings,
        "approval": {
            "requiredPlan": "pro-master",
            "token": expected_token if not blockers else None,
            "authenticatedByGate": False,
            "effect": "review-only; no install, copy, commit, tag, release or publish",
        },
    }


def human_summary(report: dict) -> str:
    lines = [
        "SKILL_SUPPLY_CHAIN_GATE · BETA",
        f"Skill: {report['skill']['skillId']} v{report['skill']['version']}",
        f"Decisão: {report['decision']}",
        f"Arquivos: {report['fileCount']} | Tamanho: {report['totalBytes']} bytes",
        f"Bloqueios: {len(report['blockers'])} | Alertas: {len(report['warnings'])}",
    ]
    for issue in report["blockers"]:
        lines.append(f"BLOQUEIO: {issue['code']} | {issue['path']} | {issue['detail']}")
    for issue in report["warnings"]:
        lines.append(f"ALERTA: {issue['code']} | {issue['path']} | {issue['detail']}")
    if report["approval"]["token"]:
        lines.append(f"Token PRO MASTER: {report['approval']['token']}")
    lines.append("Nenhum arquivo foi instalado, executado, copiado ou publicado.")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--approval-token")
    args = parser.parse_args()
    try:
        report = evaluate(args.candidate, args.baseline, args.approval_token)
        if args.report:
            write_atomic(args.report.resolve(), canonical_json(report))
        print(human_summary(report))
        return 3 if report["decision"] == "blocked" else 0
    except (GateError, OSError, json.JSONDecodeError, UnicodeDecodeError) as error:
        print(f"SKILL_SUPPLY_CHAIN_ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
