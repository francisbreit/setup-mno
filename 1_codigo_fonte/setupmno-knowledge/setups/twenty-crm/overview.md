---
{
  "schemaVersion": 1,
  "documentId": "setup-twenty-crm-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "a1a97acac295acbb4a859942fa71625cdff449a2c62106e29977b416367786ed",
  "documentType": "setup",
  "title": "Twenty CRM no Setup MNO",
  "setupId": "twenty-crm",
  "setupVersion": "7.7.7",
  "architectures": [
    "amd64"
  ],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": [
    "twenty-crm",
    "crm",
    "vendas",
    "versao-legada"
  ],
  "sources": [
    {
      "sourceId": "twenty-crm-installer",
      "title": "Instalador Twenty CRM",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/twentycrm.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "twenty-selfhost",
      "title": "Documentação oficial de self-host do Twenty",
      "sourceType": "official-documentation",
      "location": "https://docs.twenty.com/developers/self-host",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "twenty-official",
      "title": "Repositório oficial do Twenty",
      "sourceType": "official-documentation",
      "location": "https://github.com/twentyhq/twenty",
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
# Twenty CRM no Setup MNO

## Quando usar

Use em x86 para avaliar CRM moderno com contatos, oportunidades e workflows. Dados de clientes e comunicações exigem governança, retenção e controle de acesso.

## Arquitetura no Setup MNO

O instalador fixa uma versão 0.x antiga da imagem Twenty, muito anterior à linha oficial atual. Essa defasagem bloqueia homologação até existir plano de migração e teste.

## Pré-requisitos

O catálogo declara cerca de 5 GB de RAM em x86 e o menu aplica o alerta de aplicação pesada correspondente.

Exige pelo menos os recursos indicados no catálogo, domínio HTTPS, banco, storage e email conforme o uso. Defina papéis, campos, integrações e base legal.

## Fluxo seguro

Use dados fictícios, menor privilégio e credenciais dedicadas para email e integrações. Não envie contatos, negócios ou mensagens ao Assistente.

## Primeiro acesso e integrações

Crie pipeline e contatos sintéticos, valide papéis e exportação. Só conecte email, calendário ou automações após revisar escopo e versão.

## Backup e atualização

Preserve banco, storage e configuração. Não tente salto direto de versão em produção; construa caminho de migração em cópia e teste restore.

## Validação

Confirme x86, versão efetiva, autenticação, papéis, persistência, exportação, backup e restauração. Bloqueie promoção enquanto a linha antiga não estiver homologada.

## Riscos e limites

CRM concentra dados pessoais e comerciais. Versão antiga, recursos elevados e integrações com email tornam o risco crítico.

## Diagnóstico

Separe proxy, aplicação, banco, worker, storage, email e migração. Use contatos e domínio fictícios.
