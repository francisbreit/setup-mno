---
{
  "schemaVersion": 1,
  "documentId": "setup-matomo-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "c070d820d1608acb9ac1ab5d9a3f63d7a94ce7df46f7fa8ef724fae6773002ff",
  "documentType": "setup",
  "title": "Matomo no Setup MNO",
  "setupId": "matomo",
  "setupVersion": "7.12.5",
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
    "matomo",
    "analytics",
    "privacidade",
    "mysql"
  ],
  "sources": [
    {
      "sourceId": "matomo-installer",
      "title": "Instalador Matomo",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/matomo.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "matomo-backup",
      "title": "Backup e restauração oficiais Matomo",
      "sourceType": "official-documentation",
      "location": "https://matomo.org/faq/how-to/how-do-i-backup-and-restore-the-matomo-data/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "matomo-backup-policy",
      "title": "Recomendações oficiais de backup Matomo",
      "sourceType": "official-documentation",
      "location": "https://matomo.org/faq/on-premise/what-are-the-requirements-and-recommendations-for-matomo-backup/",
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
# Matomo no Setup MNO

## Quando usar

Use para analytics on-premise quando base legal, consentimento, retenção e anonimização estiverem definidos. Self-hosting não torna automaticamente o tracking compatível com leis de privacidade.

## Arquitetura no Setup MNO

O instalador usa `matomo:latest`, MySQL compartilhado e volume de aplicação, com 2 GB. O fluxo usa a senha root do MySQL para o banco da aplicação, ampliando privilégio e exposição.

## Pré-requisitos

Exige domínio HTTPS, MySQL/MariaDB, storage, cron de arquivamento, política de privacidade e capacidade baseada em tráfego. Configure timezone e retenção.

## Fluxo seguro

Crie usuário de banco dedicado com privilégio mínimo, proteja configuração e aplique anonimização/consentimento. Não envie IPs, URLs com identificadores ou eventos ao Assistente.

## Primeiro acesso e integrações

Use site e visitantes fictícios, valide código de tracking, exclusão, anonimização, arquivamento e relatórios. Revise cookies e banner com responsável jurídico.

## Backup e atualização

O backup oficial inclui dump MySQL/MariaDB, `config.ini.php`, plugins e arquivos customizados. Faça cópias externas antes de atualizar e teste restore; rollback usa banco e codebase compatíveis.

## Validação

Confirme login, coleta sintética, cron, relatórios, retenção, opt-out, backup e restauração. Audite que o usuário do banco não é root.

## Riscos e limites

Dados de navegação são pessoais em muitos contextos. Senha root compartilhada, `latest`, alto volume e plugins aumentam risco operacional e regulatório.

## Diagnóstico

Separe tracker, proxy, PHP, cron, banco, consentimento e navegador. Use eventos sintéticos e sanitize IP/URL.
