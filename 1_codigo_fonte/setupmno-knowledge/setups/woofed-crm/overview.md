---
{
  "schemaVersion": 1,
  "documentId": "setup-woofed-crm-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "b69b36cce93c2cd4b69d44891e292978c6a93dd4c694eb2ddd86d2c4de6664c4",
  "documentType": "setup",
  "title": "Woofed CRM no Setup MNO",
  "setupId": "woofed-crm",
  "setupVersion": "7.7.12",
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
    "woofed-crm",
    "crm",
    "whatsapp",
    "dados-pessoais"
  ],
  "sources": [
    {
      "sourceId": "woofed-crm-installer",
      "title": "Instalador Woofed CRM",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/woofedcrm.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "woofed-docs",
      "title": "Documentação oficial do Woofed CRM",
      "sourceType": "official-documentation",
      "location": "https://docs.woofedcrm.com/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "woofed-official",
      "title": "Repositório oficial do Woofed CRM",
      "sourceType": "official-documentation",
      "location": "https://github.com/douglara/woofed-crm",
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
# Woofed CRM no Setup MNO

## Quando usar

Use em x86 para gestão comercial e atendimento quando o fluxo do Woofed corresponder ao processo da equipe. Confirme recursos atuais no projeto oficial antes de prometer uma integração específica de WhatsApp.

## Arquitetura no Setup MNO

O instalador usa imagem do projeto, banco e Redis conforme sua configuração histórica. O script possui múltiplos papéis de serviço, exigindo validar web, worker e jobs.

## Pré-requisitos

O catálogo declara cerca de 3 GB de RAM em x86; web, workers, banco e Redis precisam de limites e medição separados.

Exige domínio HTTPS, banco, Redis, email e política para dados pessoais e comerciais. Dimensione pelos usuários, mensagens e jobs em background.

## Fluxo seguro

Use contas nominativas, menor privilégio e credenciais dedicadas. Dados de clientes, conversas e tokens não devem ser enviados ao Assistente.

## Primeiro acesso e integrações

Crie pipeline e contato fictícios, valide papéis e atividade de background. Só conecte email ou mensageria após confirmar consentimento e versão.

## Backup e atualização

Preserve banco, uploads e configuração; Redis não substitui o banco. Fixe versão e teste migrations, workers e restore em conjunto.

## Validação

Confirme x86, login, papéis, pipeline, worker, persistência, backup e restauração. Teste que usuário restrito não exporta toda a base.

## Riscos e limites

CRM e mensageria concentram dados pessoais. Tag flutuante, credenciais amplas e jobs sem monitoramento elevam o risco.

## Diagnóstico

Separe proxy, web, banco, Redis, worker, email e integração. Use contatos e mensagens fictícios.
