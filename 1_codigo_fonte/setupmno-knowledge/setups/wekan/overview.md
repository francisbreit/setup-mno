---
{
  "schemaVersion": 1,
  "documentId": "setup-wekan-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "5c259b64077a964ac69fbfe983c0e9985bc242104de3b34cef53d8d959afa782",
  "documentType": "setup",
  "title": "Wekan no Setup MNO",
  "setupId": "wekan",
  "setupVersion": "7.38.0",
  "architectures": [
    "amd64",
    "arm64"
  ],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": [
    "wekan",
    "kanban",
    "mongodb",
    "tarefas"
  ],
  "sources": [
    {
      "sourceId": "wekan-installer",
      "title": "Instalador Wekan",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/wekan.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "wekan-install",
      "title": "Instalação oficial do Wekan",
      "sourceType": "official-documentation",
      "location": "https://wekan.github.io/install/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "wekan-official",
      "title": "Repositório oficial do Wekan",
      "sourceType": "official-documentation",
      "location": "https://github.com/wekan/wekan",
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
# Wekan no Setup MNO

## Quando usar

Use para kanban e gestão de tarefas semelhante ao Trello. Defina equipes, papéis e retenção antes de importar quadros produtivos.

## Arquitetura no Setup MNO

O instalador cria ou reutiliza MongoDB conforme sua lógica e publica Wekan. O uso de um nome de stack genérico para o banco exige atenção para não confundir dependências entre aplicações.

## Pré-requisitos

O catálogo declara cerca de 1 GB de RAM; Wekan e MongoDB precisam ser medidos separadamente sob usuários e quadros reais.

Exige domínio HTTPS, MongoDB persistente, URL raiz, email opcional e política de cadastro. Confirme se o banco é dedicado e quem o administra.

## Fluxo seguro

Restrinja cadastro, use contas nominativas e menor privilégio no MongoDB. Não envie cartões, anexos ou credenciais ao Assistente.

## Primeiro acesso e integrações

Crie usuário, quadro e cartão fictícios, valide papéis e anexos. Ative email, webhooks ou importação somente após revisar dados.

## Backup e atualização

Faça dump consistente do MongoDB e preserve uploads/configuração aplicável. Fixe versão, teste migração e restauração antes de atualizar.

## Validação

Confirme login, papéis, quadro, anexo, persistência, backup e restore. Verifique que usuário externo não acessa quadro privado.

## Riscos e limites

MongoDB compartilhado ou sem autenticação, cadastro aberto e tag flutuante aumentam risco. Sync de dados não substitui backup.

## Diagnóstico

Separe proxy, aplicação, URL raiz, MongoDB, email, anexo e permissão. Use quadro fictício.
