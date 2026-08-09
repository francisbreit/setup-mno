---
{
  "schemaVersion": 1,
  "documentId": "setup-baserow-overview",
  "documentVersion": "1.0.2",
  "contentSHA256": "ae5fd55c366c547b5b51d29c4cc01b184be70e0a59135d1bd1a45ba6973105ee",
  "documentType": "setup",
  "title": "Baserow no Setup MNO",
  "setupId": "baserow",
  "setupVersion": "7.7.49",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-07-30",
  "sourceType": "setup-mno",
  "risk": "medium",
  "language": "pt-BR",
  "tags": ["baserow", "banco-de-dados", "no-code"],
  "sources": [
    {
      "sourceId": "baserow-installer",
      "title": "Instalador Baserow",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/baserow.sh",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    },
    {
      "sourceId": "baserow-catalog",
      "title": "Entrada Baserow no catálogo",
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
# Baserow no Setup MNO

## Quando usar

Use para organizar dados em uma interface semelhante a planilha, com
colaboração e automações no-code. Não substitui modelagem e governança de um
banco crítico quando há transações complexas.

## Arquitetura no Setup MNO

A aplicação usa volume próprio para dados locais e um banco lógico no
PostgreSQL base. Participa das redes interna e externa e recebe rota conforme o
tipo de instalação.

## Pré-requisitos

Exige PostgreSQL e infraestrutura-base saudáveis, domínio e capacidade de
memória. Defina previamente proprietários, política de acesso e criticidade dos
dados.

## Fluxo seguro

O instalador coleta domínio e modo de deploy, valida a base, cria o banco,
prepara volume e implanta a stack. A senha do PostgreSQL é tratada pelo
instalador e não deve aparecer em documentação ou conversa.

## Validação

Confirme acesso, criação de uma base de teste, gravação e leitura após nova
sessão. Observe separadamente saúde da aplicação, banco e persistência.

## Riscos e limites

Usuários podem transformar planilhas simples em sistemas críticos sem backup
ou controle de mudança. Inclua o banco e o volume no plano de recuperação e
defina limites de uso.

## Diagnóstico

Erro de inicialização pode indicar indisponibilidade do PostgreSQL. Erro apenas
em uma base pode ser de permissão ou modelo de dados. Preserve evidências e
evite alterações diretas no banco.
