---
{
  "schemaVersion": 1,
  "documentId": "setup-langfuse-minio-clickhouse-overview",
  "documentVersion": "1.1.0",
  "contentSHA256": "de08195e9cd69f81e2f3dfa403f33d6f5716628372b23f665a1c0fe2a0d5fc7f",
  "documentType": "setup",
  "title": "Langfuse com MinIO e ClickHouse no Setup MNO",
  "setupId": "langfuse-minio-clickhouse",
  "setupVersion": "7.7.31",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-08",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["langfuse", "observabilidade-ia", "clickhouse", "minio", "tracing"],
  "sources": [
    {"sourceId":"langfuse-installer","title":"Instalador Langfuse, MinIO e ClickHouse","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/langfuse.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"langfuse-compose","title":"Deploy oficial do Langfuse com Docker Compose","sourceType":"official-documentation","location":"https://langfuse.com/self-hosting/deployment/docker-compose","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"langfuse-scaling","title":"Requisitos e escala do Langfuse","sourceType":"official-documentation","location":"https://langfuse.com/self-hosting/configuration/scaling","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"langfuse-backups","title":"Backups self-hosted do Langfuse","sourceType":"official-documentation","location":"https://langfuse.com/self-hosting/configuration/backups","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"langfuse-v4","title":"Migração self-hosted do Langfuse v3 para v4","sourceType":"official-documentation","location":"https://langfuse.com/self-hosting/upgrade/upgrade-guides/upgrade-v3-to-v4","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# Langfuse com MinIO e ClickHouse no Setup MNO

## Quando usar

Use para rastrear chamadas de modelos, spans, custos, latência, prompts, scores e
datasets de aplicações de IA. Não use como substituto de logs de infraestrutura
nem envie dados pessoais sem política explícita de retenção e mascaramento.

## Arquitetura no Setup MNO

O combo usa Langfuse web e worker na linha principal `4`, ClickHouse 25.12,
Redis 7, PostgreSQL compartilhado e MinIO. Web e worker recebem 2 GiB cada e
`NODE_OPTIONS=--max-old-space-size=1536`. O bucket é privado e recebe uma
service account exclusiva. O instalador valida MinIO, autenticação e versão do
ClickHouse antes de criar o banco e antes de implantar o Langfuse.

## Pré-requisitos

Reserve pelo menos 6 GiB para uma homologação pequena e prefira 8 GiB ou mais.
Produção, alta ingestão e retenção extensa exigem dimensionamento próprio para
PostgreSQL, ClickHouse, Redis, storage S3, web e workers. A capacidade deve ser
medida com a carga e a política de retenção reais.

## Fluxo seguro

Use ClickHouse 25.12 ou superior e não force a instalação sobre uma versão
antiga compartilhada. Confirme `schema_migrations` sem estado `dirty`, mantenha
o bucket privado e use uma identidade exclusiva. Feche o cadastro público após
a criação controlada do administrador e planeje a migração das credenciais do
YAML para Docker Secrets.

## Primeiro acesso e integrações

Depois da homologação, crie organização e projeto, gere chaves exclusivas e
instrumente um fluxo fictício. n8n, aplicações Python/JavaScript e gateways de
LLM podem enviar telemetria sem fornecer ao Langfuse credenciais administrativas
do provedor.

## Backup, atualização e rollback

Proteja separadamente PostgreSQL, ClickHouse e objetos S3; o Redis pode conter
filas em trânsito. Teste restauração coordenada e retenção. A migração v4 exige
espaço adicional e tem ponto de compromisso após abandonar escrita legada; não
troque tags móveis sem plano específico de rollback.

## Validação

No WSL2 com Docker Desktop, a homologação de 8 de agosto de 2026 confirmou
Langfuse 4.6.0, ClickHouse 25.12.11.4, 46 migrações com `dirty=0`, web e worker
em `1/1` e `/api/public/health` com HTTP 200. Os manifests das três imagens
principais incluem `linux/amd64` e `linux/arm64`; ARM ainda requer smoke test em
hardware ou runner ARM real.

## Diagnóstico

Separe falhas por componente e nunca envie prompts, respostas, chaves ou conteúdo
de clientes ao Assistente.

## Riscos e limites

O risco residual é alto: credenciais ainda são materializadas no YAML gerado,
ClickHouse e PostgreSQL podem ser compartilhados, e uma atualização dentro da
linha principal do Langfuse pode introduzir nova migração. A evidência local é
de homologação funcional, não de carga, restauração coordenada ou produção ARM.
