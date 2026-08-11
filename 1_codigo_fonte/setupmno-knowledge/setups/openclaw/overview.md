---
{
  "schemaVersion": 1,
  "documentId": "setup-openclaw-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "17e5be3515edbdd621c1032f80c4fd41b4e873446e7584803675fdddee1e5c7f",
  "documentType": "setup",
  "title": "OpenClaw no Setup MNO",
  "setupId": "openclaw",
  "setupVersion": "7.12.4",
  "architectures": [
    "amd64",
    "arm64"
  ],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": [
    "openclaw",
    "ia",
    "agente",
    "ferramentas"
  ],
  "sources": [
    {
      "sourceId": "openclaw-installer",
      "title": "Instalador OpenClaw",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/openclaw.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "openclaw-docs",
      "title": "Documentação oficial do OpenClaw",
      "sourceType": "official-documentation",
      "location": "https://docs.openclaw.ai/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "openclaw-security",
      "title": "Segurança oficial do OpenClaw",
      "sourceType": "official-documentation",
      "location": "https://docs.openclaw.ai/gateway/security",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    }
  ],
  "homologation": {
    "verifiedAt": null,
    "verifiedPorts": [],
    "verifiedImages": []
  }
}
---
# OpenClaw no Setup MNO

## Quando usar

Use para experimentar um assistente pessoal auto-hospedado com canais, memória e ferramentas. Não o recomende para “fazer tudo”: cada capacidade precisa de finalidade, limite e aprovação humana.

## Arquitetura no Setup MNO

O instalador cria o gateway do OpenClaw com token e persistência conforme o script. O agente pode alcançar ferramentas e canais externos; isso o torna uma carga de risco crítico mesmo sem acesso ao Docker.

## Pré-requisitos

O catálogo não informa RAM mínima. Essa ausência bloqueia recomendação automática por capacidade até existir medição homologada.

Exige provedor de modelo, política de ferramentas, orçamento, dados permitidos e ambiente isolado. Defina quais canais, skills, diretórios e ações são explicitamente autorizados.

## Fluxo seguro

Comece sem shell, navegador autenticado ou credenciais produtivas. Use allowlists, confirmação humana e conta de teste; não monte socket Docker nem diretórios do host.

## Primeiro acesso e integrações

Valide o gateway com canal fictício e ferramenta inofensiva. Adicione uma integração por vez e confirme que o agente não atravessa o escopo definido.

## Backup e atualização

Preserve configuração e memória somente conforme política de privacidade. Remova tokens das cópias, registre versão e teste restauração em ambiente descartável.

## Validação

Confirme autenticação, isolamento, limites de ferramenta, cancelamento, consumo e auditoria. Teste prompt injection e negação de ação fora de escopo.

## Riscos e limites

Agentes podem executar ações reais, sofrer prompt injection e propagar dados por canais. Tag flutuante e skills de terceiros ampliam a superfície.

## Diagnóstico

Separe provedor, modelo, gateway, canal, skill, memória e permissão. Use logs sanitizados e nunca compartilhe tokens ou conteúdo privado.
