---
{
  "schemaVersion": 1,
  "documentId": "setup-openfang-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "457dd72464d5d8190476dfc7131c174989f0a4827452482848d67f03be41cd73",
  "documentType": "setup",
  "title": "OpenFang no Setup MNO",
  "setupId": "openfang",
  "setupVersion": "7.48.28",
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
    "openfang",
    "ia",
    "agent-os",
    "automacao"
  ],
  "sources": [
    {
      "sourceId": "openfang-installer",
      "title": "Instalador OpenFang",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/openfang.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "openfang-docs",
      "title": "Documentação oficial do OpenFang",
      "sourceType": "official-documentation",
      "location": "https://www.openfang.sh/docs",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "openfang-security",
      "title": "Segurança oficial do OpenFang",
      "sourceType": "official-documentation",
      "location": "https://www.openfang.sh/docs/security",
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
# OpenFang no Setup MNO

## Quando usar

Use para avaliar um sistema operacional de agentes autônomos com skills, canais e workflows. O projeto evolui rapidamente; fixe a versão e mantenha o uso em laboratório até homologação.

## Arquitetura no Setup MNO

O instalador constrói o runtime a partir de uma base Debian em vez de consumir uma imagem oficial pronta. Essa construção dinâmica precisa de revisão, hash e evidência antes de produção.

## Pré-requisitos

O catálogo não informa RAM mínima. Essa ausência bloqueia recomendação automática por capacidade até existir medição homologada.

Exige provedor de modelo, política de skills, canais autorizados, orçamento e ambiente isolado. Defina responsabilidades, dados permitidos e critérios de interrupção.

## Fluxo seguro

Inicie com agente mínimo, sem credenciais produtivas, shell privilegiado ou acesso ao host. Skills, MCPs e canais devem usar allowlist e aprovação humana.

## Primeiro acesso e integrações

Valide uma tarefa reversível com dados sintéticos e um canal de teste. Adicione integrações individualmente e registre permissões concedidas.

## Backup e atualização

Preserve configuração e estado conforme a política, excluindo tokens. Fixe código ou versão, teste migração e restauração e mantenha a imagem anterior para rollback.

## Validação

Confirme autenticação, limites, auditoria, cancelamento e ausência de mounts privilegiados. Teste prompt injection e falha do provedor.

## Riscos e limites

Autonomia, código baixado no build e mudanças pré-estáveis elevam o risco. Não interprete a instalação como autorização para ações externas.

## Diagnóstico

Separe build, kernel, provedor, skill, canal e persistência. Use logs sanitizados e não exponha prompts, tokens ou saídas privadas.
