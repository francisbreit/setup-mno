---
{
  "schemaVersion": 1,
  "documentId": "setup-combo-vibe-ops-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "a5d51494e817297471e48c81354482d37040779fb8418fef8d12c66fca526fb0",
  "documentType": "setup",
  "title": "Combo Vibe Ops (Hermes Agent + n8n) no Setup MNO",
  "setupId": "combo-vibe-ops",
  "setupVersion": "7.48.28",
  "architectures": [
    "amd64",
    "arm64"
  ],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-09-06",
  "sourceType": "setup-mno",
  "risk": "medium",
  "language": "pt-BR",
  "tags": [
    "vibe-ops",
    "hermes-agent",
    "n8n",
    "devops",
    "sre",
    "combo",
    "blueprint",
    "ia"
  ],
  "sources": [
    {
      "sourceId": "combo-vibe-ops-installer",
      "title": "Instalador Combo Vibe Ops (Hermes Agent + n8n)",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/combo_vibe_ops.sh",
      "license": "project-internal",
      "verifiedAt": "2026-09-06"
    },
    {
      "sourceId": "hermes-agent-official-doc",
      "title": "Documentação oficial do Hermes Agent",
      "sourceType": "official-documentation",
      "location": "https://github.com/NousResearch/Hermes-Function-Calling",
      "license": "documentation-reference",
      "verifiedAt": "2026-09-06"
    },
    {
      "sourceId": "n8n-official-documentation",
      "title": "Documentação oficial do n8n",
      "sourceType": "official-documentation",
      "location": "https://docs.n8n.io/",
      "license": "documentation-reference",
      "verifiedAt": "2026-09-06"
    }
  ],
  "homologation": {
    "verifiedAt": null,
    "verifiedPorts": [],
    "verifiedImages": []
  }
}
---
# Combo Vibe Ops (Hermes Agent + n8n) no Setup MNO

## Quando usar

Use para provisionar e orquestrar de forma integrada o ecossistema oficial do Blueprint #006 (Vibe Ops & SRE Autônomo com Hermes Agent, n8n v2 em Modo Fila, Sentinel e Fleet Hub). Esta stack é ideal para operar servidores Docker Swarm através de linguagem natural via WhatsApp ou Telegram com segurança fail-closed, orquestração de incidentes e auto-remediação de serviços sem expor portas administrativas.

## Arquitetura no Setup MNO

O combo executa na rede overlay segura e isolada `interna` do Docker Swarm. O Hermes Agent consome modelos de linguagem através do vLLM, LiteLLM ou provedores externos, recebendo chamadas de ferramentas estruturadas em formato OpenAI/Hermes Tool Calling. O n8n v2 atua como orquestrador transacional de fluxos, integrando o webhook do Sentinel ao MNO Fleet Hub para execução de tarefas idempotentes. Toda a exposição é intermediada pelo Traefik com SSL ou Cloudflare Tunnel nativo com zero portas abertas.

## Pré-requisitos

Servidor VPS ou ambiente de desenvolvimento WSL2 com no mínimo 3 GB de memória RAM dedicada (recomendado 4 GB a 8 GB caso execute modelos locais de IA), 2 vCPUs ou superior, rede overlay `interna` provisionada pelo Setup MNO, PostgreSQL central ativo e RabbitMQ para mensageria assíncrona do n8n em modo fila.

## Fluxo seguro

A instalação é realizada pelo menu Whiptail do Setup MNO ou via Control Center. O assistente verifica se dependências essenciais (como n8n ou PostgreSQL) já estão presentes e oferece reutilização segura sem duplicação de containers nem risco de sobrescrever volumes de dados existentes.

## Validação

Após o provisionamento da stack, acesse o painel administrativo do n8n e valide o status da stack do Hermes Agent com `docker service ls`. Envie um comando de diagnóstico simulado para o endpoint do Fleet Hub e confirme que a resposta em linguagem natural reflete as métricas do cluster com auditoria nos logs.

## Riscos e limites

Operações acionadas por agentes autônomos exigem estrita política de fail-closed e controle de concorrência com idempotência. Nunca conceda acesso irrestrito de escrita ou privilégios root desnecessários sem confirmação humana prévia para comandos potencialmente destrutivos.

## Diagnóstico

Monitore a integridade dos serviços executando `docker service logs combo_vibe_ops_hermes` e inspecione as mensagens de fila no RabbitMQ. Verifique a resolução DNS interna entre os containers na rede `interna` e garanta que as variáveis de ambiente com credenciais estejam devidamente configuradas via secrets ou configs do Swarm.
