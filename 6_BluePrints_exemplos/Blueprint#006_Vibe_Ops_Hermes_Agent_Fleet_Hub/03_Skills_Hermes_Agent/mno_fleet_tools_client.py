#!/usr/bin/env python3
"""
MNO Fleet Hub Tools Client for Hermes Agent / Python Autonomous Agents
======================================================================
Permite que o Hermes Agent execute as ferramentas da frota do Setup MNO
com validação de schemas, controle de erros e autenticação segura via Bearer token.
"""

from __future__ import annotations
import json
import os
import sys
import urllib.error
import urllib.request
from typing import Any, Dict, Optional


class MNOFleetClient:
    """Cliente oficial para executar Tool Calling na API do MNO Fleet Hub."""

    def __init__(
        self,
        base_url: Optional[str] = None,
        auth_token: Optional[str] = None,
        timeout: int = 15,
    ) -> None:
        self.base_url = (
            base_url
            or os.environ.get("FLEET_HUB_BASE_URL")
            or "http://mnoctrle181325-web:8080"
        ).rstrip("/")
        self.auth_token = auth_token or os.environ.get("SETUPMNO_FLEET_TOKEN") or ""
        self.timeout = timeout

    def fetch_schema(self) -> Dict[str, Any]:
        """Obtém o schema JSON das ferramentas no padrão OpenAI / Hermes Tool Calling."""
        url = f"{self.base_url}/api/fleet/tools/schema.json"
        req = urllib.request.Request(url, headers={"Accept": "application/json"})
        with urllib.request.urlopen(req, timeout=self.timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))

    def execute_tool(self, tool_name: str, arguments: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Executa uma ferramenta específica no MNO Fleet Hub e retorna o resultado."""
        url = f"{self.base_url}/api/fleet/tools/execute"
        payload = json.dumps({
            "tool": tool_name,
            "arguments": arguments or {},
        }).encode("utf-8")

        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json",
        }
        if self.auth_token:
            headers["Authorization"] = f"Bearer {self.auth_token}"

        req = urllib.request.Request(url, data=payload, headers=headers, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8")
            try:
                err_json = json.loads(body)
                return {"error": err_json.get("error", str(exc)), "status_code": exc.code}
            except Exception:
                return {"error": body, "status_code": exc.code}
        except Exception as exc:
            return {"error": f"falha de conexão com o Fleet Hub: {exc}"}

    # Atalhos convenientes para cada uma das 6 ferramentas:

    def get_status(self) -> Dict[str, Any]:
        """Obtém status consolidado da frota."""
        return self.execute_tool("fleet_get_status")

    def list_nodes(self) -> Dict[str, Any]:
        """Lista todos os nós registrados na frota."""
        return self.execute_tool("fleet_list_nodes")

    def diagnose_node(self, node_query: str) -> Dict[str, Any]:
        """Executa probe detalhado em tempo real no nó selecionado."""
        return self.execute_tool("fleet_diagnose_node", {"node_query": node_query})

    def consult_dispatch(self, node_query: str, application: str) -> Dict[str, Any]:
        """Avalia capacidade e gera roteiro de despacho para uma aplicação."""
        return self.execute_tool("fleet_consult_dispatch", {"node_query": node_query, "application": application})

    def ping_node(self, node_id: str) -> Dict[str, Any]:
        """Envia probe rápido de latência para o nó."""
        return self.execute_tool("fleet_ping_node", {"node_id": node_id})

    def sentinel_status(self) -> Dict[str, Any]:
        """Consulta incidentes ativos e histórico de alertas do MNO Sentinel."""
        return self.execute_tool("fleet_sentinel_status")


if __name__ == "__main__":
    client = MNOFleetClient()
    print("=== MNO Fleet Hub Client Test ===")
    try:
        schema = client.fetch_schema()
        print(f"Sucesso! Encontradas {len(schema.get('tools', []))} ferramentas no schema.")
        for t in schema.get("tools", []):
            print(f" - {t['function']['name']}: {t['function']['description'][:60]}...")
    except Exception as err:
        print(f"Erro ao conectar: {err}", file=sys.stderr)
        sys.exit(1)
