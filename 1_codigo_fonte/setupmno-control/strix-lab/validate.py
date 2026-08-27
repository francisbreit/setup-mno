#!/usr/bin/env python3
"""Validador fail-closed dos contratos SRE-6; nunca executa o Strix."""
import datetime as dt
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
HEX64 = re.compile(r"^[a-f0-9]{64}$")
AUTH_ID = re.compile(r"^strix-[a-z0-9]{12,48}$")

def fail(message):
    raise ValueError(message)

def load(path):
    target = Path(path)
    if target.is_symlink() or not target.is_file() or target.stat().st_size > 32768:
        fail("arquivo ausente, inseguro ou grande demais")
    return json.loads(target.read_text(encoding="utf-8"))

def keys(value, expected):
    if not isinstance(value, dict) or set(value) != set(expected):
        fail("campos ausentes ou inesperados")

def instant(value):
    if not isinstance(value, str): fail("data inválida")
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        fail("data inválida")
    if parsed.tzinfo is None: fail("data sem fuso horário")
    return parsed

def integer(value):
    return isinstance(value, int) and not isinstance(value, bool)

def validate_lock(value):
    keys(value, ["schemaVersion", "maturity", "project", "version", "license", "pythonRequires", "developmentStatus", "sourceRepository", "sourceTag", "artifacts", "sandbox", "fork", "execution"])
    expected = {"schemaVersion": 1, "maturity": "beta", "project": "strix-agent", "version": "1.5.3", "license": "Apache-2.0", "pythonRequires": ">=3.12", "developmentStatus": "alpha", "sourceRepository": "https://github.com/usestrix/strix", "sourceTag": "v1.5.3"}
    if any(value[k] != v for k, v in expected.items()): fail("metadados upstream divergentes")
    hashes = {
        "amd64": "ba0b6b13f13f41e45f3eb4dba515641d1bc71363ca6e758d0cd05c20ff56b6ea",
        "arm64": "da35ae6e9a6ae0bf5cc662012608cf0aa671479129ba94052a3f893bff74c43f",
        "source": "a5babe4e6d42cb24a10d4508bcd3c477bd369ff7194c95a7c58de6d6e4c3be18",
    }
    if set(value["artifacts"]) != set(hashes): fail("arquiteturas upstream divergentes")
    for arch, digest in hashes.items():
        artifact = value["artifacts"][arch]
        keys(artifact, ["filename", "sha256"])
        if artifact["sha256"] != digest or not HEX64.fullmatch(artifact["sha256"]): fail("hash upstream divergente")
    keys(value["sandbox"], ["status", "image", "digest"])
    if value["sandbox"] != {"status": "pending-homologation", "image": "", "digest": ""}: fail("sandbox não homologado deve permanecer bloqueado")
    keys(value["fork"], ["used", "commit", "diffSHA256"])
    if value["fork"] != {"used": False, "commit": "", "diffSHA256": ""}: fail("fork não auditado")
    keys(value["execution"], ["available", "reason", "productionDockerSocketAllowed", "productionRootMountAllowed", "targetMutationAllowed", "automaticExecution"])
    if value["execution"]["available"] is not False or any(value["execution"][k] is not False for k in ["productionDockerSocketAllowed", "productionRootMountAllowed", "targetMutationAllowed", "automaticExecution"]): fail("execução insegura")

def validate_authorization(value):
    expected = ["schemaVersion", "contractVersion", "maturity", "plan", "authorizationID", "targetSHA256", "issuedAt", "expiresAt", "maxDurationMinutes", "limits", "writtenPermission", "automaticExecution", "targetMutationAllowed", "productionDockerSocketAllowed", "productionRootMountAllowed", "state"]
    keys(value, expected)
    if (value["schemaVersion"], value["contractVersion"], value["maturity"], value["plan"]) != (1, "1.0.0", "beta", "pro-master"): fail("contrato ou plano inválido")
    if not isinstance(value["authorizationID"], str) or not AUTH_ID.fullmatch(value["authorizationID"]): fail("identificador inválido")
    if not isinstance(value["targetSHA256"], str) or not HEX64.fullmatch(value["targetSHA256"]): fail("alvo não sanitizado")
    issued, expires = instant(value["issuedAt"]), instant(value["expiresAt"])
    if expires <= issued or expires - issued > dt.timedelta(hours=2): fail("janela de autorização inválida")
    if not integer(value["maxDurationMinutes"]) or not 1 <= value["maxDurationMinutes"] <= 120: fail("duração inválida")
    keys(value["limits"], ["cpu", "memoryMB", "llmBudgetUSD"])
    cpu, memory, budget = value["limits"]["cpu"], value["limits"]["memoryMB"], value["limits"]["llmBudgetUSD"]
    if isinstance(cpu, bool) or not isinstance(cpu, (int, float)) or not 0 < cpu <= 2: fail("CPU inválida")
    if not integer(memory) or not 256 <= memory <= 4096: fail("memória inválida")
    if isinstance(budget, bool) or not isinstance(budget, (int, float)) or not 0 <= budget <= 20: fail("orçamento inválido")
    if value["writtenPermission"] is not True: fail("permissão escrita ausente")
    for field in ["automaticExecution", "targetMutationAllowed", "productionDockerSocketAllowed", "productionRootMountAllowed"]:
        if value[field] is not False: fail("capacidade proibida")
    if value["state"] not in ["draft", "approved", "expired", "revoked"]: fail("estado inválido")

def validate_report(value):
    expected = ["schemaVersion", "contractVersion", "maturity", "authorizationID", "targetSHA256", "generatedAt", "expiresAt", "status", "counts", "limitations", "execution", "rawEvidenceStored", "sealGranted", "catalogPublished", "remediationApplied"]
    keys(value, expected)
    if (value["schemaVersion"], value["contractVersion"], value["maturity"]) != (1, "1.0.0", "beta"): fail("contrato inválido")
    if not isinstance(value["authorizationID"], str) or not AUTH_ID.fullmatch(value["authorizationID"]): fail("identificador inválido")
    if not isinstance(value["targetSHA256"], str) or not HEX64.fullmatch(value["targetSHA256"]): fail("alvo não sanitizado")
    generated, expires = instant(value["generatedAt"]), instant(value["expiresAt"])
    if expires <= generated or expires - generated > dt.timedelta(hours=24): fail("validade do relatório inválida")
    if value["status"] not in ["completed", "partial", "failed"]: fail("estado inválido")
    keys(value["counts"], ["critical", "high", "medium", "low", "info"])
    if any(not integer(item) or item < 0 for item in value["counts"].values()): fail("contagem inválida")
    if not isinstance(value["limitations"], list) or len(value["limitations"]) > 20 or any(not isinstance(item, str) or not 1 <= len(item) <= 240 for item in value["limitations"]): fail("limitações inválidas")
    keys(value["execution"], ["productionDockerSocketUsed", "productionRootMounted", "targetMutated", "automaticExecution"])
    for item in value["execution"].values():
        if item is not False: fail("execução insegura")
    for field in ["rawEvidenceStored", "sealGranted", "catalogPublished", "remediationApplied"]:
        if value[field] is not False: fail("efeito proibido")

def main():
    if len(sys.argv) not in (2, 3): fail("uso: validate.py lock|authorization|report [arquivo]")
    mode = sys.argv[1]
    path = ROOT / "upstream-lock.json" if mode == "lock" and len(sys.argv) == 2 else (sys.argv[2] if len(sys.argv) == 3 else "")
    value = load(path)
    {"lock": validate_lock, "authorization": validate_authorization, "report": validate_report}.get(mode, lambda _: fail("modo inválido"))(value)
    print(f"SRE6_CONTRACT_OK:{mode}")

if __name__ == "__main__":
    try: main()
    except (ValueError, OSError, json.JSONDecodeError) as exc:
        print(f"SRE6_CONTRACT_ERROR:{exc}", file=sys.stderr)
        sys.exit(1)
