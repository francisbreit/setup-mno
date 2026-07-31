---
{
  "schemaVersion": 1,
  "documentId": "infra-security-architecture",
  "documentVersion": "1.0.2",
  "contentSHA256": "3dbbb737137349fde85fcd66f252d92d292a2a4affcef4bbaf2162c1455928fb",
  "documentType": "infrastructure",
  "title": "Limites de segurança do Control Center",
  "topicId": "security",
  "setupVersion": "4.99.0",
  "architectures": ["amd64", "arm64"],
  "category": "security",
  "status": "reviewed",
  "updatedAt": "2026-07-30",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": ["seguranca", "isolamento", "assistente"],
  "sources": [
    {
      "sourceId": "control-center-security-readme",
      "title": "Arquitetura do Setup MNO Control Center",
      "sourceType": "setup-mno",
      "location": "setupmno-control/README.md",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    },
    {
      "sourceId": "control-center-installer-script",
      "title": "Instalador gerado do Control Center",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/setupmno_control.sh",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    }
  ],
  "homologation": {
    "verifiedAt": null,
    "verifiedPorts": [],
    "verifiedImages": []
  }
}
---
# Limites de segurança do Control Center

## Papel no Setup MNO

O Control Center separa painel, agente de leitura, terminal e Assistente. O
painel não acessa o host; somente componentes estritamente autorizados recebem
os recursos necessários para sua função.

## Princípios

O Assistente permanece sem socket Docker, shell, terminal, mount do host ou
rota pública própria. Métricas são sanitizadas antes de chegar ao conector de
IA. A chave OpenAI existe somente como Docker Secret e respostas nunca
executam ações.

## Validação

Os gates verificam separação das stacks, mounts, redes, endpoints permitidos,
fallback local e ausência de dados sensíveis no payload. A falha de um
provedor deve ficar visível e ativar o diagnóstico básico.

## Riscos e limites

Transformar o Assistente em API de comandos quebraria o limite de confiança do
Beta. Prompt e RAG não são controles de autorização. Qualquer capacidade de
escrita exige outra fase arquitetural, política explícita e homologação
independente.
