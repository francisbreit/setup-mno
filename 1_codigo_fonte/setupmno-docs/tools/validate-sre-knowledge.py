#!/usr/bin/env python3
"""Valida integridade, escopo e metadados do Setup MNO SRE Knowledge Pack."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlparse


MAX_MANIFEST_BYTES = 256 * 1024
MAX_DOCUMENT_BYTES = 256 * 1024
ALLOWED_STATUS = {"draft", "implemented", "validated", "published", "outdated"}
ALLOWED_TYPES = {"index", "architecture", "manual", "faq"}
ALLOWED_SOURCE_DOMAINS = {
    "csrc.nist.gov",
    "developers.cloudflare.com",
    "dev.mysql.com",
    "doc.traefik.io",
    "docs.docker.com",
    "documentation.ubuntu.com",
    "learn.microsoft.com",
    "www.debian.org",
    "www.postgresql.org",
}
REQUIRED_METADATA = (
    "- Estado: `implemented`",
    "- Atualizado em: 2026-08-23",
    "- Público:",
    "- Ambientes:",
)
REQUIRED_SECTIONS = (
    "## Resumo para leigos",
    "## Limites e segurança",
    "## Publicação futura no Help",
)
FORBIDDEN_PATTERNS = (
    (re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"), "chave privada"),
    (re.compile(r"\bcfut_[A-Za-z0-9_-]{20,}\b"), "token Cloudflare"),
    (re.compile(r"\bsk-[A-Za-z0-9_-]{20,}\b"), "chave de API"),
    (re.compile(r"[A-Za-z0-9._%+-]+@(?!example\.com\b)[A-Za-z0-9.-]+\.[A-Za-z]{2,}"), "e-mail real"),
)


class ValidationError(Exception):
    pass


def regular_file(path: Path, label: str, max_bytes: int) -> None:
    if path.is_symlink():
        raise ValidationError(f"{label} não pode ser symlink: {path}")
    if not path.is_file():
        raise ValidationError(f"{label} ausente ou não regular: {path}")
    size = path.stat().st_size
    if size <= 0 or size > max_bytes:
        raise ValidationError(f"{label} com tamanho inválido ({size} bytes): {path}")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require_string_list(entry: dict, field: str) -> None:
    value = entry.get(field)
    if not isinstance(value, list) or not value or any(not isinstance(item, str) or not item for item in value):
        raise ValidationError(f"campo {field} deve ser lista não vazia de strings em {entry.get('id', '?')}")


def validate_source(url: str, document: str) -> None:
    parsed = urlparse(url)
    if parsed.scheme != "https" or not parsed.netloc or parsed.username or parsed.password:
        raise ValidationError(f"fonte não HTTPS ou com credencial em {document}: {url}")
    if parsed.hostname not in ALLOWED_SOURCE_DOMAINS:
        raise ValidationError(f"domínio de fonte não permitido em {document}: {parsed.hostname}")


def safe_document_path(docs_root: Path, relative: str) -> Path:
    if not relative.startswith("sre/") or Path(relative).is_absolute() or ".." in Path(relative).parts:
        raise ValidationError(f"caminho fora do pack SRE: {relative}")
    candidate = docs_root / relative
    try:
        candidate.resolve(strict=True).relative_to((docs_root / "sre").resolve(strict=True))
    except (FileNotFoundError, ValueError) as error:
        raise ValidationError(f"caminho inválido ou ausente: {relative}") from error
    return candidate


def validate_document(path: Path, entry: dict) -> None:
    regular_file(path, "documento", MAX_DOCUMENT_BYTES)
    body = path.read_text(encoding="utf-8")
    if not body.startswith("# "):
        raise ValidationError(f"título H1 ausente: {entry['path']}")
    for marker in REQUIRED_METADATA:
        if marker not in body:
            raise ValidationError(f"metadado ausente ({marker}) em {entry['path']}")
    for heading in REQUIRED_SECTIONS:
        if heading not in body:
            raise ValidationError(f"seção obrigatória ausente ({heading}) em {entry['path']}")
    for pattern, label in FORBIDDEN_PATTERNS:
        if pattern.search(body):
            raise ValidationError(f"possível {label} encontrado em {entry['path']}")
    for source in entry["sources"]:
        validate_source(source, entry["path"])
        if source not in body:
            raise ValidationError(f"fonte do manifesto não aparece no documento {entry['path']}: {source}")
    observed = sha256(path)
    if observed != entry["sha256"]:
        raise ValidationError(
            f"SHA-256 divergente em {entry['path']}: esperado {entry['sha256']}, observado {observed}"
        )


def validate(docs_root: Path) -> int:
    docs_root = docs_root.resolve(strict=True)
    manifest_path = docs_root / "sre" / "manifest.json"
    regular_file(manifest_path, "manifesto", MAX_MANIFEST_BYTES)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

    if manifest.get("schemaVersion") != 1:
        raise ValidationError("schemaVersion do manifesto deve ser 1")
    if manifest.get("knowledgePack") != "setup-mno-sre":
        raise ValidationError("knowledgePack inesperado")
    if not re.fullmatch(r"\d+\.\d+\.\d+", str(manifest.get("knowledgePackVersion", ""))):
        raise ValidationError("knowledgePackVersion deve usar SemVer")
    if manifest.get("status") not in ALLOWED_STATUS:
        raise ValidationError("status do manifesto inválido")
    if manifest.get("runtimePublished") is not False or manifest.get("controlCenterPublished") is not False:
        raise ValidationError("SRE-0 deve permanecer fora do runtime e do Control Center")
    if manifest.get("maintainerPlan") != "pro-master":
        raise ValidationError("governança do pack deve permanecer em pro-master")

    entries = manifest.get("entries")
    if not isinstance(entries, list) or not entries:
        raise ValidationError("manifesto deve possuir entries")

    seen_ids: set[str] = set()
    seen_paths: set[str] = set()
    for entry in entries:
        if not isinstance(entry, dict):
            raise ValidationError("entry inválida")
        entry_id = entry.get("id")
        relative = entry.get("path")
        if not isinstance(entry_id, str) or not re.fullmatch(r"[a-z0-9][a-z0-9-]*", entry_id):
            raise ValidationError(f"id inválido: {entry_id}")
        if entry_id in seen_ids:
            raise ValidationError(f"id duplicado: {entry_id}")
        if not isinstance(relative, str) or relative in seen_paths:
            raise ValidationError(f"path inválido ou duplicado: {relative}")
        if entry.get("type") not in ALLOWED_TYPES:
            raise ValidationError(f"type inválido em {entry_id}")
        if not isinstance(entry.get("title"), str) or not entry["title"].strip():
            raise ValidationError(f"title ausente em {entry_id}")
        if not re.fullmatch(r"[0-9a-f]{64}", str(entry.get("sha256", ""))):
            raise ValidationError(f"sha256 inválido em {entry_id}")
        require_string_list(entry, "audience")
        require_string_list(entry, "environments")
        require_string_list(entry, "topics")
        sources = entry.get("sources")
        if not isinstance(sources, list) or any(not isinstance(item, str) for item in sources):
            raise ValidationError(f"sources inválido em {entry_id}")
        if entry["type"] != "index" and not sources:
            raise ValidationError(f"documento sem fonte oficial: {entry_id}")

        path = safe_document_path(docs_root, relative)
        validate_document(path, entry)
        seen_ids.add(entry_id)
        seen_paths.add(relative)

    actual = {
        path.relative_to(docs_root).as_posix()
        for path in (docs_root / "sre").rglob("*.md")
        if path.is_file() and not path.is_symlink()
    }
    if actual != seen_paths:
        missing = sorted(actual - seen_paths)
        stale = sorted(seen_paths - actual)
        raise ValidationError(f"inventário divergente; não listados={missing}, ausentes={stale}")

    print(
        "SRE_KNOWLEDGE_OK "
        f"version={manifest['knowledgePackVersion']} entries={len(entries)} "
        "runtimePublished=false controlCenterPublished=false"
    )
    return 0


def main() -> int:
    default_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--docs-root", type=Path, default=default_root)
    args = parser.parse_args()
    try:
        return validate(args.docs_root)
    except (ValidationError, json.JSONDecodeError, UnicodeDecodeError) as error:
        print(f"SRE_KNOWLEDGE_ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
