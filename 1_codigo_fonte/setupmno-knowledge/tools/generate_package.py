#!/usr/bin/python3
"""Gera o pacote reproduzível de conhecimento do Assistente MNO."""

from __future__ import annotations

import argparse
from collections import Counter
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

from blueprint_factory import build_blueprint_package
from lint_knowledge import load_documents, load_json


PACKAGE_SCHEMA = 1
LEGACY_INDEX_SCHEMA = 1
INDEX_SCHEMA = 2
RETRIEVAL_VERSION = "1.2.0"
MAX_DOCUMENTS = 512
MAX_DOCUMENT_BYTES = 256 << 10
MAX_INDEX_BYTES = 2 << 20
MAX_ARCHIVE_BYTES = 8 << 20
MAX_CHUNK_CHARACTERS = 2400
MAX_CHUNK_OVERLAP = 200
MIN_CHUNK_CHARACTERS = 120
SEMVER_RE = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
TOKEN_RE = re.compile(r"[a-z0-9][a-z0-9-]{1,63}")
HEADING_RE = re.compile(r"^(#{1,3})[ \t]+(.+?)[ \t]*$")
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


def tokenize(text: str) -> list[str]:
    normalized = unicodedata.normalize("NFKD", text.casefold())
    ascii_text = "".join(character for character in normalized if not unicodedata.combining(character))
    return [
        match.group(0)
        for match in TOKEN_RE.finditer(ascii_text)
        if match.group(0) not in STOP_WORDS
    ]


def normalize_terms(text: str) -> list[str]:
    return sorted(set(tokenize(text)))


def term_frequencies(text: str) -> dict[str, int]:
    return dict(sorted(Counter(tokenize(text)).items()))


def slugify(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value.casefold())
    ascii_text = "".join(
        character for character in normalized if not unicodedata.combining(character)
    )
    slug = re.sub(r"[^a-z0-9]+", "-", ascii_text).strip("-")
    if not slug:
        raise ValueError(f"heading não produz slug estável: {value!r}")
    return slug[:80].rstrip("-")


def markdown_sections(body: str, fallback_title: str) -> list[tuple[str, str]]:
    """Separa o Markdown por H2; H3 permanece no conteúdo da seção H2."""
    sections: list[tuple[str, str]] = []
    current_heading = fallback_title
    current_lines: list[str] = []
    saw_h2 = False
    for line in body.splitlines():
        match = HEADING_RE.match(line)
        if match and len(match.group(1)) == 1:
            continue
        if match and len(match.group(1)) == 2:
            content = "\n".join(current_lines).strip()
            if content:
                sections.append((current_heading, content))
            current_heading = match.group(2).strip()
            current_lines = []
            saw_h2 = True
            continue
        current_lines.append(line)
    content = "\n".join(current_lines).strip()
    if content:
        sections.append((current_heading, content))
    if not sections:
        raise ValueError("documento sem conteúdo recuperável")
    if not saw_h2:
        return [(fallback_title, sections[0][1])]
    return sections


def overlap_suffix(content: str) -> str:
    if len(content) <= MAX_CHUNK_OVERLAP:
        return content
    suffix = content[-MAX_CHUNK_OVERLAP:]
    first_space = suffix.find(" ")
    if first_space >= 0:
        suffix = suffix[first_space + 1 :]
    return suffix.strip()


def split_section(content: str) -> list[str]:
    paragraphs = [
        paragraph.strip()
        for paragraph in re.split(r"\n[ \t]*\n", content)
        if paragraph.strip()
    ]
    if any(len(paragraph) > MAX_CHUNK_CHARACTERS for paragraph in paragraphs):
        raise ValueError(
            "parágrafo excede o limite de chunk; divida-o editorialmente "
            f"em blocos de até {MAX_CHUNK_CHARACTERS} caracteres"
        )
    chunks: list[str] = []
    current = ""
    for paragraph in paragraphs:
        candidate = paragraph if not current else current + "\n\n" + paragraph
        if len(candidate) <= MAX_CHUNK_CHARACTERS:
            current = candidate
            continue
        chunks.append(current)
        overlap = overlap_suffix(current)
        candidate = overlap + "\n\n" + paragraph if overlap else paragraph
        current = candidate if len(candidate) <= MAX_CHUNK_CHARACTERS else paragraph
    if current:
        chunks.append(current)

    merged: list[str] = []
    for chunk in chunks:
        if len(chunk) < MIN_CHUNK_CHARACTERS and merged:
            candidate = merged[-1] + "\n\n" + chunk
            if len(candidate) <= MAX_CHUNK_CHARACTERS:
                merged[-1] = candidate
                continue
        merged.append(chunk)
    if len(merged) > 1 and len(merged[0]) < MIN_CHUNK_CHARACTERS:
        candidate = merged[0] + "\n\n" + merged[1]
        if len(candidate) <= MAX_CHUNK_CHARACTERS:
            merged[:2] = [candidate]
    return merged


def aliases_for_document(
    metadata: dict[str, Any],
    registry_by_id: dict[str, dict[str, Any]],
    taxonomy: dict[str, Any],
    document_path: Path,
) -> list[str]:
    if metadata["documentType"] == "setup":
        return list(registry_by_id[metadata["setupId"]]["aliases"])
    if metadata["documentType"] == "infrastructure":
        return list(taxonomy.get("synonyms", {}).get(metadata["topicId"], []))
    if metadata["documentType"] == "blueprint":
        manifest = load_json(document_path.parent / "blueprint.json")
        aliases = [
            metadata["blueprintId"],
            manifest["title"],
            *manifest.get("aliases", []),
        ]
        return list(dict.fromkeys(str(alias) for alias in aliases if str(alias).strip()))
    return []


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
    catalog_path: Path,
    setup_version: str,
) -> tuple[dict[str, bytes], dict[str, Any]]:
    taxonomy = load_json(root / "schema" / "taxonomy.json")
    registry = load_json(root / "registry" / "setups.json")
    registry_by_id = {
        entry["setupId"]: entry for entry in registry.get("setups", [])
    }
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
    chunks: list[dict[str, Any]] = []
    chunk_ids: set[str] = set()
    document_frequencies: Counter[str] = Counter()
    field_length_totals: Counter[str] = Counter()
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
        aliases = aliases_for_document(
            metadata,
            registry_by_id,
            taxonomy,
            document.path,
        )
        search_material = " ".join(
            [
                metadata["title"],
                " ".join(metadata["tags"]),
                " ".join(aliases),
                document.body,
            ]
        )
        terms = normalize_terms(search_material)
        entry = {
            "architectures": metadata["architectures"],
            "category": metadata["category"],
            "blueprintId": metadata.get("blueprintId"),
            "fictitious": metadata.get("fictitious", False),
            "deployable": metadata.get("deployable", False),
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

        for heading, section_content in markdown_sections(
            document.body,
            metadata["title"],
        ):
            section_chunks = split_section(section_content)
            heading_slug = slugify(heading)
            for position, content in enumerate(section_chunks, start=1):
                chunk_id = (
                    f"{metadata['documentId']}#{heading_slug}-{position:02d}"
                )
                if chunk_id in chunk_ids:
                    raise ValueError(f"chunkId duplicado: {chunk_id}")
                chunk_ids.add(chunk_id)
                fields = {
                    "aliases": " ".join(aliases),
                    "content": content,
                    "heading": heading,
                    "tags": " ".join(metadata["tags"]),
                    "title": metadata["title"],
                }
                field_frequencies = {
                    field: term_frequencies(value)
                    for field, value in sorted(fields.items())
                }
                field_lengths = {
                    field: sum(frequencies.values())
                    for field, frequencies in field_frequencies.items()
                }
                for field, length in field_lengths.items():
                    field_length_totals[field] += length
                chunk_terms = {
                    term
                    for frequencies in field_frequencies.values()
                    for term in frequencies
                }
                document_frequencies.update(chunk_terms)
                chunks.append(
                    {
                        "aliases": aliases,
                        "architectures": metadata["architectures"],
                        "category": metadata["category"],
                        "blueprintId": metadata.get("blueprintId"),
                        "fictitious": metadata.get("fictitious", False),
                        "deployable": metadata.get("deployable", False),
                        "chunkId": chunk_id,
                        "content": content,
                        "contentSHA256": sha256_hex(content.encode("utf-8")),
                        "documentId": metadata["documentId"],
                        "documentType": metadata["documentType"],
                        "documentVersion": metadata["documentVersion"],
                        "fieldLengths": field_lengths,
                        "fieldTermFrequencies": field_frequencies,
                        "heading": heading,
                        "setupId": metadata.get("setupId"),
                        "setupVersion": metadata["setupVersion"],
                        "status": metadata["status"],
                        "tags": metadata["tags"],
                        "title": metadata["title"],
                        "topicId": metadata.get("topicId"),
                    }
                )
        latest_date = max(latest_date, metadata["updatedAt"])

    legacy_index = {
        "schemaVersion": LEGACY_INDEX_SCHEMA,
        "knowledgeVersion": knowledge_version,
        "setupVersion": setup_version,
        "normalRetrievalStatuses": taxonomy["normalRetrievalStatuses"],
        "entries": index_entries,
        "invertedIndex": dict(sorted(inverted_index.items())),
    }
    legacy_index_data = canonical_json(legacy_index)
    add_package_file(files, "index-v1.json", legacy_index_data)

    chunk_count = len(chunks)
    index = {
        "schemaVersion": INDEX_SCHEMA,
        "retrievalVersion": RETRIEVAL_VERSION,
        "knowledgeVersion": knowledge_version,
        "setupVersion": setup_version,
        "normalRetrievalStatuses": taxonomy["normalRetrievalStatuses"],
        "synonyms": {
            target: list(aliases)
            for target, aliases in sorted(taxonomy["synonyms"].items())
        },
        "chunkCount": chunk_count,
        "averageFieldLengths": {
            field: round(total / chunk_count, 6)
            for field, total in sorted(field_length_totals.items())
        },
        "documentFrequencies": dict(sorted(document_frequencies.items())),
        "chunks": chunks,
    }
    index_data = canonical_json(index)
    if len(index_data) > MAX_INDEX_BYTES:
        raise ValueError(f"índice excede {MAX_INDEX_BYTES} bytes")
    add_package_file(files, "index.json", index_data)

    for source, target in (
        (root / "VERSION", "VERSION"),
        (root / "schema" / "document.schema.json", "schema/document.schema.json"),
        (root / "schema" / "index-v2.schema.json", "schema/index-v2.schema.json"),
        (root / "schema" / "taxonomy.json", "schema/taxonomy.json"),
        (root / "registry" / "setups.json", "registry/setups.json"),
    ):
        add_package_file(files, target, ensure_regular_source(source, root))

    blueprint_files, blueprint_summary = build_blueprint_package(
        root,
        catalog_path,
        setup_version,
    )
    for path, data in sorted(blueprint_files.items()):
        add_package_file(files, path, data)

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
        "blueprintKnowledgeEntries": sum(
            entry["documentType"] == "blueprint" for entry in index_entries
        ),
        "blueprintFixtureEntries": sum(
            entry["documentType"] == "blueprint" and entry["fictitious"]
            for entry in index_entries
        ),
        "chunkEntries": chunk_count,
        "indexSchemaVersion": INDEX_SCHEMA,
        "knowledgeVersion": knowledge_version,
        "legacyIndexSHA256": sha256_hex(legacy_index_data),
        "latestDocumentDate": max(
            latest_date,
            blueprint_summary["latestBlueprintDate"],
        ),
        "retrievalVersion": RETRIEVAL_VERSION,
        "setupEntries": sum(entry["documentType"] == "setup" for entry in index_entries),
        "indexSHA256": sha256_hex(index_data),
        **blueprint_summary,
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
        "legacyIndexSHA256": summary["legacyIndexSHA256"],
        "indexSchemaVersion": summary["indexSchemaVersion"],
        "retrievalVersion": summary["retrievalVersion"],
        "documentEntries": summary["documentEntries"],
        "chunkEntries": summary["chunkEntries"],
        "documentTypeEntries": summary["documentTypeEntries"],
        "setupEntries": summary["setupEntries"],
        "infrastructureEntries": summary["infrastructureEntries"],
        "blueprintSchemaVersion": 1,
        "blueprintFactoryVersion": summary["blueprintFactoryVersion"],
        "blueprintEntries": summary["blueprintEntries"],
        "blueprintBundleEntries": summary["blueprintBundleEntries"],
        "blueprintIndexSHA256": summary["blueprintIndexSHA256"],
        "blueprintKnowledgeEntries": summary["blueprintKnowledgeEntries"],
        "blueprintFixtureEntries": summary["blueprintFixtureEntries"],
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
    files, summary = build_package_files(root, catalog, args.setup_version)
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
                "blueprintEntries": manifest["blueprintEntries"],
                "blueprintBundleEntries": manifest["blueprintBundleEntries"],
                "blueprintFactoryVersion": manifest["blueprintFactoryVersion"],
                "blueprintKnowledgeEntries": manifest["blueprintKnowledgeEntries"],
                "blueprintFixtureEntries": manifest["blueprintFixtureEntries"],
                "chunkEntries": manifest["chunkEntries"],
                "indexSchemaVersion": manifest["indexSchemaVersion"],
                "retrievalVersion": manifest["retrievalVersion"],
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
