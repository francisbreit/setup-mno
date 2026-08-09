---
{
  "schemaVersion": 1,
  "documentId": "setup-superset-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "7d252d4c98329b2222d734f671ad85188f74804f6b9c37ecdd19a34970833944",
  "documentType": "setup",
  "title": "Apache Superset no Setup MNO",
  "setupId": "superset",
  "setupVersion": "7.7.46",
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
    "superset",
    "bi",
    "dashboards",
    "banco-de-dados"
  ],
  "sources": [
    {
      "sourceId": "superset-installer",
      "title": "Instalador Apache Superset",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/superset.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "superset-install",
      "title": "Métodos oficiais de instalação do Superset",
      "sourceType": "official-documentation",
      "location": "https://superset.apache.org/admin-docs/installation/installation-methods/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "superset-docker",
      "title": "Docker Compose oficial do Superset",
      "sourceType": "official-documentation",
      "location": "https://superset.apache.org/admin-docs/installation/docker-compose/",
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
# Apache Superset no Setup MNO

## Quando usar

Use para BI, exploração SQL e dashboards quando fontes, métricas e acesso estiverem governados. Não use credencial ampla de banco para simplificar a conexão.

## Arquitetura no Setup MNO

O instalador usa uma instância simplificada da imagem Superset. A documentação oficial diferencia quickstart de produção e prevê banco de metadados, cache e workers conforme a carga.

## Pré-requisitos

O catálogo declara cerca de 2 GB de RAM; essa referência é insuficiente para generalizar uma topologia com metadados, cache, workers e consultas concorrentes.

Exige domínio HTTPS, banco de metadados, drivers das fontes, segredo de aplicação e usuários de leitura dedicados. Alertas e relatórios podem exigir componentes adicionais.

## Fluxo seguro

Use credenciais somente leitura por fonte, Row Level Security quando aplicável e papéis mínimos. SQL, dados e credenciais não devem ser enviados ao Assistente.

## Primeiro acesso e integrações

Troque credenciais iniciais, crie banco fictício e dashboard de teste. Valide papéis, filtros e exportação antes de conectar fontes reais.

## Backup e atualização

Preserve banco de metadados e configuração; dashboards não vivem apenas na imagem. Fixe release, instale drivers controladamente e teste migrações e restore.

## Validação

Confirme autenticação, papéis, consulta restrita, dashboard, cache, backup e restauração. Teste que uma conta de visualização não acessa SQL Lab indevido.

## Riscos e limites

Superset pode executar consultas pesadas e revelar dados amplos. Quickstart, tag flutuante, segredo padrão ou usuário de banco privilegiado são riscos críticos.

## Diagnóstico

Separe proxy, aplicação, metadados, driver, fonte, cache e consulta. Use dataset sintético e planos sem dados reais.
