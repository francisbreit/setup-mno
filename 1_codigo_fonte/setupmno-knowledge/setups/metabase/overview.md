---
{
  "schemaVersion": 1,
  "documentId": "setup-metabase-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "ee0111595dd294c7562ba1856322c1b342457aeea5eae7b945413a97950fd36f",
  "documentType": "setup",
  "title": "Metabase no Setup MNO",
  "setupId": "metabase",
  "setupVersion": "7.47.3",
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
    "metabase",
    "bi",
    "analytics",
    "postgresql"
  ],
  "sources": [
    {
      "sourceId": "metabase-installer",
      "title": "Instalador Metabase",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/metabase.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "metabase-install",
      "title": "Instalação oficial Metabase",
      "sourceType": "official-documentation",
      "location": "https://www.metabase.com/docs/latest/installation-and-operation/installing-metabase",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "metabase-upgrade",
      "title": "Atualização oficial Metabase",
      "sourceType": "official-documentation",
      "location": "https://www.metabase.com/docs/latest/installation-and-operation/upgrading-metabase",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "metabase-backup",
      "title": "Backup oficial Metabase",
      "sourceType": "official-documentation",
      "location": "https://www.metabase.com/docs/latest/installation-and-operation/backing-up-metabase-application-data",
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
# Metabase no Setup MNO

## Quando usar

Use para perguntas, dashboards e BI sobre bancos autorizados. Não conecte com superusuário nem presuma segurança em nível de linha disponível em todas as edições.

## Arquitetura no Setup MNO

O instalador usa `Metabase na tag latest`, banco de aplicação PostgreSQL compartilhado com credencial privilegiada e define `MB_DB_MIGRATION_LOCATION=none`, configuração suspeita que precisa ser validada. O catálogo estima 1 GB.

## Pré-requisitos

Exige domínio HTTPS, banco de aplicação PostgreSQL de produção e usuários somente leitura nos bancos analisados. Planeje memória Java, concorrência e SMTP.

## Fluxo seguro

Use bancos e papéis dedicados com mínimo privilégio, restrinja embedding/admin e proteja secrets. Não conecte dados reais antes de revisar permissões e auditoria.

## Primeiro acesso e integrações

Crie administrador, conecte banco sintético com usuário read-only e publique dashboard de teste; valide grupos, filtros e exportação.

## Backup e atualização

A documentação exige backup do banco de aplicação antes do upgrade e recomenda tag específica. Para rollback de major, restaure backup ou execute procedimento compatível; não use banco migrado cegamente.

## Validação

Confirme migração, login, conexão read-only, consulta, dashboard, permissões, SMTP, persistência e restauração. Verifique se `MB_DB_MIGRATION_LOCATION=none` não bloqueia schema.

## Riscos e limites

Conexão privilegiada pode expor ou alterar dados. `latest`, banco compartilhado e configuração de migração não comprovada tornam atualização de alto risco.

## Diagnóstico

Separe JVM, banco de aplicação, fonte analítica, driver, migração e proxy. Use schema sintético e queries sem dados reais.
