#!/usr/bin/python3
"""Gera o pacote reproduzível de conhecimento do Assistente MNO."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import json
import os
import re
import subprocess
import sys
import tarfile
import tempfile
import unicodedata
from pathlib import Path
from typing import Any

from lint_knowledge import load_documents, load_json


PACKAGE_SCHEMA = 1
MAX_DOCUMENTS = 512
MAX_DOCUMENT_BYTES = 256 << 10
MAX_INDEX_BYTES = 2 << 20
MAX_ARCHIVE_BYTES = 8 << 20
SEMVER_RE = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
TOKEN_RE = re.compile(r"[a-z0-9][a-z0-9-]{1,63}")
STOP_WORDS = {
    "a",
    "ao",
    "aos",
    "as",
    "com",
    "como",
    "da",
    "das",
    "de",
    "do",
    "dos",
    "e",
    "em",
    "entre",
    "no",
    "nos",
    "o",
    "os",
    "ou",
    "para",
    "pela",
    "pelo",
    "por",
    "que",
    "se",
    "sem",
    "um",
    "uma",
}


def canonical_json(value: Any) -> bytes:
    return (
        json.dumps(
            value,
            ensure_ascii=False,
            separators=(",", ":"),
            sort_keys=True,
        )
        + "\n"
    ).encode("utf-8")


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def normalize_terms(text: str) -> list[str]:
    normalized = unicodedata.normalize("NFKD", text.casefold())
    ascii_text = "".join(character for character in normalized if not unicodedata.combining(character))
    terms = {
        match.group(0)
        for match in TOKEN_RE.finditer(ascii_text)
        if match.group(0) not in STOP_WORDS
    }
    return sorted(terms)


def ensure_regular_source(path: Path, root: Path) -> bytes:
    if path.is_symlink():
        raise ValueError(f"symlink proibido na fonte: {path.relative_to(root)}")
    stat = path.stat()
    if not path.is_file():
        raise ValueError(f"arquivo não regular na fonte: {path.relative_to(root)}")
    if stat.st_size > MAX_DOCUMENT_BYTES:
        raise ValueError(f"arquivo excede o limite: {path.relative_to(root)}")
    return path.read_bytes()


def add_package_file(files: dict[str, bytes], path: str, data: bytes) -> None:
    if path.startswith("/") or ".." in Path(path).parts:
        raise ValueError(f"caminho inseguro no pacote: {path}")
    if path in files:
        raise ValueError(f"caminho duplicado no pacote: {path}")
    files[path] = data


def build_package_files(
    root: Path,
    setup_version: str,
) -> tuple[dict[str, bytes], dict[str, Any]]:
    taxonomy = load_json(root / "schema" / "taxonomy.json")
    registry = load_json(root / "registry" / "setups.json")
    knowledge_version = (root / "VERSION").read_text(encoding="utf-8").strip()
    if not SEMVER_RE.fullmatch(knowledge_version):
        raise ValueError("VERSION da base de conhecimento não segue SemVer")
    if registry.get("setupVersion") != setup_version:
        raise ValueError(
            "registry/setups.json não corresponde à versão do Setup MNO "
            f"({registry.get('setupVersion')} != {setup_version})"
        )

    documents, parse_errors = load_documents(root)
    if parse_errors:
        raise ValueError("; ".join(parse_errors))
    allowed_statuses = set(taxonomy["normalRetrievalStatuses"])
    selected = [
        document
        for document in documents
        if document.metadata.get("status") in allowed_statuses
    ]
    if not selected:
        raise ValueError("nenhum documento elegível para o pacote")
    if len(selected) > MAX_DOCUMENTS:
        raise ValueError(f"quantidade de documentos excede {MAX_DOCUMENTS}")

    files: dict[str, bytes] = {}
    index_entries: list[dict[str, Any]] = []
    inverted_index: dict[str, list[str]] = {}
    latest_date = ""

    for document in sorted(selected, key=lambda item: item.metadata["documentId"]):
        metadata = document.metadata
        if metadata["setupVersion"] != setup_version:
            raise ValueError(
                f"{metadata['documentId']}: setupVersion incompatível "
                f"({metadata['setupVersion']} != {setup_version})"
            )
        raw_document = ensure_regular_source(document.path, root)
        packaged_path = (
            f"documents/{metadata['documentType']}/{metadata['documentId']}.md"
        )
        add_package_file(files, packaged_path, raw_document)
        search_material = " ".join(
            [
                metadata["title"],
                " ".join(metadata["tags"]),
                document.body,
            ]
        )
        terms = normalize_terms(search_material)
        entry = {
            "architectures": metadata["architectures"],
            "category": metadata["category"],
            "contentSHA256": metadata["contentSHA256"],
            "documentId": metadata["documentId"],
            "documentType": metadata["documentType"],
            "documentVersion": metadata["documentVersion"],
            "path": packaged_path,
            "risk": metadata["risk"],
            "setupId": metadata.get("setupId"),
            "setupVersion": metadata["setupVersion"],
            "sourcePath": str(document.path.relative_to(root)),
            "status": metadata["status"],
            "tags": metadata["tags"],
            "terms": terms,
            "title": metadata["title"],
            "topicId": metadata.get("topicId"),
            "updatedAt": metadata["updatedAt"],
        }
        index_entries.append(entry)
        for term in terms:
            inverted_index.setdefault(term, []).append(metadata["documentId"])
        latest_date = max(latest_date, metadata["updatedAt"])

    index = {
        "schemaVersion": PACKAGE_SCHEMA,
        "knowledgeVersion": knowledge_version,
        "setupVersion": setup_version,
        "normalRetrievalStatuses": taxonomy["normalRetrievalStatuses"],
        "entries": index_entries,
        "invertedIndex": dict(sorted(inverted_index.items())),
    }
    index_data = canonical_json(index)
    if len(index_data) > MAX_INDEX_BYTES:
        raise ValueError(f"índice excede {MAX_INDEX_BYTES} bytes")
    add_package_file(files, "index.json", index_data)

    for source, target in (
        (root / "VERSION", "VERSION"),
        (root / "schema" / "document.schema.json", "schema/document.schema.json"),
        (root / "schema" / "taxonomy.json", "schema/taxonomy.json"),
        (root / "registry" / "setups.json", "registry/setups.json"),
    ):
        add_package_file(files, target, ensure_regular_source(source, root))

    summary = {
        "documentEntries": len(index_entries),
        "documentTypeEntries": {
            document_type: sum(
                entry["documentType"] == document_type for entry in index_entries
            )
            for document_type in sorted(
                {entry["documentType"] for entry in index_entries}
            )
        },
        "infrastructureEntries": sum(
            entry["documentType"] == "infrastructure" for entry in index_entries
        ),
        "knowledgeVersion": knowledge_version,
        "latestDocumentDate": latest_date,
        "setupEntries": sum(entry["documentType"] == "setup" for entry in index_entries),
        "indexSHA256": sha256_hex(index_data),
    }
    return files, summary


def deterministic_archive(files: dict[str, bytes]) -> bytes:
    tar_buffer = io.BytesIO()
    with tarfile.open(fileobj=tar_buffer, mode="w", format=tarfile.PAX_FORMAT) as archive:
        for path in sorted(files):
            data = files[path]
            info = tarfile.TarInfo(path)
            info.size = len(data)
            info.mode = 0o644
            info.mtime = 0
            info.uid = 0
            info.gid = 0
            info.uname = ""
            info.gname = ""
            archive.addfile(info, io.BytesIO(data))
    compressed = io.BytesIO()
    with gzip.GzipFile(
        filename="",
        mode="wb",
        fileobj=compressed,
        mtime=0,
        compresslevel=9,
    ) as stream:
        stream.write(tar_buffer.getvalue())
    return compressed.getvalue()


def build_manifest(
    files: dict[str, bytes],
    archive_data: bytes,
    summary: dict[str, Any],
    setup_version: str,
    control_version: str,
) -> dict[str, Any]:
    if len(archive_data) > MAX_ARCHIVE_BYTES:
        raise ValueError(f"arquivo compactado excede {MAX_ARCHIVE_BYTES} bytes")
    inventory = [
        {
            "path": path,
            "sha256": sha256_hex(files[path]),
            "size": len(files[path]),
        }
        for path in sorted(files)
    ]
    return {
        "schemaVersion": PACKAGE_SCHEMA,
        "knowledgeVersion": summary["knowledgeVersion"],
        "setupVersion": setup_version,
        "controlVersion": control_version,
        "generatedAt": summary["latestDocumentDate"] + "T00:00:00Z",
        "archiveFile": "knowledge-package.tar.gz",
        "archiveSHA256": sha256_hex(archive_data),
        "archiveBytes": len(archive_data),
        "indexSHA256": summary["indexSHA256"],
        "documentEntries": summary["documentEntries"],
        "documentTypeEntries": summary["documentTypeEntries"],
        "setupEntries": summary["setupEntries"],
        "infrastructureEntries": summary["infrastructureEntries"],
        "fileEntries": len(files),
        "limits": {
            "maxArchiveBytes": MAX_ARCHIVE_BYTES,
            "maxDocumentBytes": MAX_DOCUMENT_BYTES,
            "maxDocuments": MAX_DOCUMENTS,
            "maxIndexBytes": MAX_INDEX_BYTES,
        },
        "files": inventory,
    }


def lint_source(root: Path, catalog: Path) -> None:
    linter = root / "tools" / "lint_knowledge.py"
    result = subprocess.run(
        [
            sys.executable,
            "-B",
            str(linter),
            "--root",
            str(root),
            "--catalog",
            str(catalog),
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise ValueError("linter recusou a base canônica:\n" + result.stderr.strip())


def atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink():
        raise ValueError(f"destino não pode ser symlink: {path}")
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=path.name + ".",
        suffix=".tmp",
        dir=path.parent,
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o644)
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def generate(args: argparse.Namespace) -> dict[str, Any]:
    root = args.root.resolve()
    catalog = args.catalog.resolve()
    output = args.output.resolve()
    if not SEMVER_RE.fullmatch(args.setup_version):
        raise ValueError("--setup-version deve seguir SemVer")
    if not SEMVER_RE.fullmatch(args.control_version):
        raise ValueError("--control-version deve seguir SemVer")
    if root == output or root in output.parents:
        raise ValueError("o destino não pode conter ou substituir a fonte canônica")
    lint_source(root, catalog)
    files, summary = build_package_files(root, args.setup_version)
    archive_data = deterministic_archive(files)
    repeated_archive = deterministic_archive(files)
    if archive_data != repeated_archive:
        raise ValueError("o pacote não é reproduzível")
    manifest = build_manifest(
        files,
        archive_data,
        summary,
        args.setup_version,
        args.control_version,
    )
    output.mkdir(parents=True, exist_ok=True)
    allowed_outputs = {"knowledge-package.tar.gz", "manifest.json"}
    for existing in output.iterdir():
        if existing.name not in allowed_outputs:
            raise ValueError(f"arquivo inesperado no destino: {existing}")
        if existing.is_symlink() or not existing.is_file():
            raise ValueError(f"destino contém entrada não regular: {existing}")
    atomic_write(output / "knowledge-package.tar.gz", archive_data)
    atomic_write(output / "manifest.json", canonical_json(manifest))
    return manifest


def parse_args() -> argparse.Namespace:
    default_root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=default_root)
    parser.add_argument(
        "--catalog",
        type=Path,
        default=default_root.parent / "setupmno-control" / "catalog.json",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=default_root.parent / "setupmno-control" / "knowledge-package",
    )
    parser.add_argument("--setup-version", required=True)
    parser.add_argument("--control-version", required=True)
    return parser.parse_args()


def main() -> int:
    try:
        manifest = generate(parse_args())
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"ERRO: {exc}", file=sys.stderr)
        return 1
    print(
        json.dumps(
            {
                "result": "ok",
                "knowledgeVersion": manifest["knowledgeVersion"],
                "setupVersion": manifest["setupVersion"],
                "controlVersion": manifest["controlVersion"],
                "documentEntries": manifest["documentEntries"],
                "archiveBytes": manifest["archiveBytes"],
                "archiveSHA256": manifest["archiveSHA256"],
            },
            ensure_ascii=False,
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
