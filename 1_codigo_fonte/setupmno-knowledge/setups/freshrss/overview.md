---
{
  "schemaVersion": 1,
  "documentId": "setup-freshrss-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "6617a2368c716834ea3041cac09c8f908a21a7e4ba940678c7ce75ce94d5ddb8",
  "documentType": "setup",
  "title": "FreshRSS no Setup MNO",
  "setupId": "freshrss",
  "setupVersion": "7.48.12",
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
    "freshrss",
    "rss",
    "feeds",
    "leitura"
  ],
  "sources": [
    {
      "sourceId": "freshrss-installer",
      "title": "Instalador FreshRSS",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/freshrss.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "freshrss-admin",
      "title": "Administração oficial FreshRSS",
      "sourceType": "official-documentation",
      "location": "https://freshrss.github.io/FreshRSS/en/admins/01_Index.html",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "freshrss-update",
      "title": "Atualização oficial FreshRSS",
      "sourceType": "official-documentation",
      "location": "https://freshrss.github.io/FreshRSS/en/admins/04_Updating.html",
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
# FreshRSS no Setup MNO

## Quando usar

Use para agregar e ler feeds RSS/Atom, com usuários e categorias. Não é crawler irrestrito nem garante disponibilidade ou completude de sites sem feeds.

## Arquitetura no Setup MNO

O instalador usa `FreshRSS na tag latest`, volume persistente, rota e limite de 128 MB. O estado pode incluir banco/configuração no volume e tarefas de atualização de feeds.

## Pré-requisitos

Exige domínio HTTPS, volume, administrador e capacidade proporcional a usuários, feeds e frequência. Planeje cron, retenção e importação OPML.

## Fluxo seguro

Restrinja registro, use senha forte e trate URLs de feeds privados como sensíveis. Fixe versão em atualizações planejadas e evite extensões sem revisão.

## Primeiro acesso e integrações

Crie usuário de teste, importe OPML fictício, atualize feeds e valide categorias, leitura e compartilhamento. Configure cron sem frequência abusiva.

## Backup e atualização

Preserve volume/banco e exporte OPML. Antes de atualizar, copie dados, registre versão e valide restore e migrações numa cópia.

## Validação

Confirme login, cadastro, coleta, cron, importação/exportação, persistência e comportamento de feed inválido. Verifique consumo com a carga prevista.

## Riscos e limites

128 MB pode ser insuficiente para muitos feeds. `latest`, extensões e feeds privados exigem cautela; o conteúdo externo pode ser malicioso.

## Diagnóstico

Separe DNS/TLS do feed, parser, cron, banco, extensão e proxy. Use feeds públicos e remova URLs privadas.
