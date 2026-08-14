---
{
  "schemaVersion": 1,
  "documentId": "setup-meilisearch-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "1beca2de8fa6ab1c6b4928e766c320911518ae02885342b0be0ddc03ba030686",
  "documentType": "setup",
  "title": "Meilisearch no Setup MNO",
  "setupId": "meilisearch",
  "setupVersion": "7.18.0",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["meilisearch", "busca", "full-text", "indices", "api"],
  "sources": [
    {"sourceId":"meilisearch-installer","title":"Instalador Meilisearch","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/meilisearch.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"meilisearch-docker","title":"Imagem Docker oficial do Meilisearch","sourceType":"official-documentation","location":"https://www.meilisearch.com/integrations/docker","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"meilisearch-backup","title":"Backups do Meilisearch","sourceType":"official-documentation","location":"https://www.meilisearch.com/docs/resources/self_hosting/data_backup/overview","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"meilisearch-update","title":"Atualização do Meilisearch","sourceType":"official-documentation","location":"https://www.meilisearch.com/docs/resources/migration/updating","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# Meilisearch no Setup MNO

## Quando usar

Use para busca textual rápida, tolerância a erros, filtros e facetas em catálogos
e aplicações. Não é banco primário: a origem dos documentos deve continuar em
um sistema capaz de reconstruir o índice.

## Arquitetura no Setup MNO

O script cria uma réplica Meilisearch 1.41.0, master key aleatória, telemetria
desativada, limite de 512 MB e volume persistente. Acesso externo ocorre por
Traefik ou túnel; não há porta do host no YAML atual.

## Pré-requisitos

Defina chaves primárias, filtros, ranking, volume, taxa de indexação e estratégia
de reconstrução. Indexações grandes podem consumir muito mais memória que o
estado ocioso; valide SSD e folga além do rótulo de 512 MB.

## Fluxo seguro

Use chave administrativa somente para administração e gere chaves restritas para
busca e ingestão. Não exponha master key em frontend, URL ou conversa. Adicione
healthcheck, backup e monitoramento de tarefas antes de produção.

## Primeiro acesso e integrações

Consulte `/health`, crie um índice fictício, configure searchable e filterable
attributes e teste busca com chave limitada. LibreChat e aplicações web podem
integrar sem receber a master key.

## Backup, atualização e rollback

Snapshots são cópias rápidas vinculadas à mesma versão; dumps são portáveis e
indicados para migração. Gere dump antes de atualizar, mantenha-o fora do volume
primário e teste importação. Voltar uma imagem sem banco compatível pode falhar.

## Validação

Valide health, versão, autenticação, tarefas, indexação, busca, filtros, snapshot,
dump e restauração.

## Diagnóstico

Separe erro de chave, schema do documento, memória, disco e fila de tarefas. Não
envie documentos privados ou master key ao Assistente.

## Riscos e limites

Risco alto por limite de memória estreito, ausência de healthcheck e falta de
rotina de backup no instalador. A imagem está fixada, mas toda atualização exige
dump e compatibilidade de banco verificadas.
