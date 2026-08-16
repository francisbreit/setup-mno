---
{
  "schemaVersion": 1,
  "documentId": "setup-openproject-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "063e22cbc0d245b44a14ef2631e50dae1702f0f1510a7d60f235e121fe338028",
  "documentType": "setup",
  "title": "OpenProject no Setup MNO",
  "setupId": "openproject",
  "setupVersion": "7.19.3",
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
    "openproject",
    "projetos",
    "colaboracao",
    "postgresql"
  ],
  "sources": [
    {
      "sourceId": "openproject-installer",
      "title": "Instalador OpenProject",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/openproject.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "openproject-docker",
      "title": "Docker oficial OpenProject",
      "sourceType": "official-documentation",
      "location": "https://www.openproject.org/docs/installation-and-operations/installation/docker/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "openproject-compose",
      "title": "Docker Compose e backup OpenProject",
      "sourceType": "official-documentation",
      "location": "https://www.openproject.org/docs/installation-and-operations/installation/docker-compose/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "openproject-requirements",
      "title": "Requisitos oficiais OpenProject",
      "sourceType": "official-documentation",
      "location": "https://www.openproject.org/docs/installation-and-operations/system-requirements/",
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
# OpenProject no Setup MNO

## Quando usar

Use para gestão de projetos, work packages e colaboração quando sua operação aceita a complexidade da plataforma. Não prometa integração de repositório na instalação Docker, limitação documentada oficialmente.

## Arquitetura no Setup MNO

O instalador usa `OpenProject na linha 15`, PostgreSQL compartilhado, Redis base compartilhado, volume e limite de 1 GB. A linha oficial atual é 17 e recomenda containers slim por processo em produção; o fluxo atual está defasado e simplificado.

## Pré-requisitos

Exige domínio HTTPS, PostgreSQL, cache, volume de assets, secret persistente e recursos dimensionados por usuários. O projeto publica amd64 e arm64 para Docker.

## Fluxo seguro

Não use Redis compartilhado para nova arquitetura, proteja `SECRET_KEY_BASE`, banco e admin e mantenha hostname público correto. Proíba senha admin padrão.

## Primeiro acesso e integrações

Crie projeto, usuário, work package e anexo fictícios; valide permissões, email e calendário. Registre recursos indisponíveis na variante Docker.

## Backup e atualização

O guia oficial orienta backup de PostgreSQL e assets antes do upgrade. Migre da linha 15 para 17 somente com caminho suportado e ensaio; preserve banco e imagem anteriores.

## Validação

Confirme migrações, login, permissões, work packages, uploads, jobs, email, backup e restore. Meça RAM real além do 1 GB catalogado.

## Riscos e limites

Versão defasada, dependências compartilhadas, recursos possivelmente insuficientes e segredo em YAML impedem homologação automática de produção.

## Diagnóstico

Separe app/worker, banco, Redis/cache, assets, email e proxy. Use projeto fictício e sanitize nomes.
