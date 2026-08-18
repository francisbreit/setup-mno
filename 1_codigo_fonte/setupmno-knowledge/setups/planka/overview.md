---
{
  "schemaVersion": 1,
  "documentId": "setup-planka-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "0d9b101bc07364e8052baa15628eb277a62ec2550d17bb70888ceb311070b54a",
  "documentType": "setup",
  "title": "PLANKA no Setup MNO",
  "setupId": "planka",
  "setupVersion": "7.20.0",
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
    "planka",
    "kanban",
    "projetos",
    "postgresql"
  ],
  "sources": [
    {
      "sourceId": "planka-installer",
      "title": "Instalador PLANKA",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/planka.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "planka-docker",
      "title": "Docker oficial PLANKA",
      "sourceType": "official-documentation",
      "location": "https://docs.planka.cloud/docs/category/docker/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "planka-docs",
      "title": "Documentação oficial PLANKA",
      "sourceType": "official-documentation",
      "location": "https://docs.planka.cloud/docs/welcome/",
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
# PLANKA no Setup MNO

## Quando usar

Use para quadros Kanban, projetos e colaboração de equipes pequenas ou médias. Não presuma controles corporativos avançados sem validar a edição e permissões.

## Arquitetura no Setup MNO

O instalador usa `PLANKA na tag latest`, PostgreSQL compartilhado, Redis no mesmo stack, volume e credenciais admin/SMTP no YAML, com 1 GB.

## Pré-requisitos

Exige domínio HTTPS, PostgreSQL, Redis, secret persistente, storage e SMTP opcional. Defina administrador, retenção e política de anexos.

## Fluxo seguro

Gere segredos exclusivos, altere admin inicial, proteja banco/SMTP e restrinja cadastro. Prefira Redis dedicado como substack no padrão atual do projeto.

## Primeiro acesso e integrações

Crie projeto, quadro, usuário e cartão fictícios; teste convite, permissão, anexo, movimento e notificação. Só então configure OIDC ou importação.

## Backup e atualização

A documentação Docker oferece scripts de backup/restore; preserve PostgreSQL, anexos e configuração. Faça backup antes do update e teste rollback com tag anterior.

## Validação

Confirme login, permissões, Kanban, anexos, notificações, persistência e restauração. Inspecione migrações e conectividade Redis.

## Riscos e limites

`latest`, dependências/segredos no mesmo YAML e credenciais iniciais ampliam impacto. Backup incompleto perde anexos ou board data.

## Diagnóstico

Separe app, banco, Redis, storage, SMTP/OIDC e proxy. Use projeto fictício e sanitize usuários.
