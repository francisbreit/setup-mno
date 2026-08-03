---
{
  "schemaVersion": 1,
  "documentId": "setup-nocodb-overview",
  "documentVersion": "1.0.2",
  "contentSHA256": "1cdff41c3001cb63c587b1c7cba3db2d3989ceb08a7bcdb8caf74377a470e95b",
  "documentType": "setup",
  "title": "NocoDB no Setup MNO",
  "setupId": "nocodb",
  "setupVersion": "7.7.5",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-07-30",
  "sourceType": "setup-mno",
  "risk": "medium",
  "language": "pt-BR",
  "tags": ["nocodb", "no-code", "planilhas"],
  "sources": [
    {
      "sourceId": "nocodb-installer",
      "title": "Instalador NocoDB",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/nocodb.sh",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    },
    {
      "sourceId": "nocodb-catalog",
      "title": "Entrada NocoDB no catálogo",
      "sourceType": "setup-mno",
      "location": "setupmno-control/catalog.json",
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
# NocoDB no Setup MNO

## Quando usar

Use para manipular dados por uma interface semelhante a planilha e construir
visões no-code. Compare Baserow e considere governança de banco quando os
dados forem críticos.

## Arquitetura no Setup MNO

A aplicação mantém volume próprio e usa banco lógico no PostgreSQL base.
Participa das redes interna e externa e publica uma única interface.

## Pré-requisitos

Exige PostgreSQL, domínio, infraestrutura-base e política de usuários. Fontes
externas conectadas devem usar contas de menor privilégio.

## Fluxo seguro

O instalador coleta domínio e opção de deploy, cria o banco lógico, prepara o
volume e publica a stack. A credencial do PostgreSQL permanece no fluxo
interno.

## Validação

Confirme login, criação de tabela de teste, gravação e persistência. Se conectar
outra base, valide primeiro com dados descartáveis e permissão restrita.

## Riscos e limites

Alterações feitas por interface podem impactar modelos compartilhados.
Permissões excessivas em bases externas ampliam o dano potencial. Backup deve
cobrir banco e metadados persistidos.

## Diagnóstico

Falha de inicialização pode apontar para PostgreSQL. Erro em uma fonte externa
deve ser isolado como conectividade ou permissão. Nunca inclua connection
string ou dados de linha no chat.
