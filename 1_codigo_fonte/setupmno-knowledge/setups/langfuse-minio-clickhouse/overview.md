---
{
  "schemaVersion": 1,
  "documentId": "setup-langfuse-minio-clickhouse-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "9fc177d65a9b37ed732b04a10796f6e81eba7475844719633526779cbce754d6",
  "documentType": "setup",
  "title": "Langfuse com MinIO e ClickHouse no Setup MNO",
  "setupId": "langfuse-minio-clickhouse",
  "setupVersion": "7.2.8",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
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

O combo cria MinIO, ClickHouse 23.8, PostgreSQL compartilhado, Redis, servidor e
worker Langfuse com tags `latest`. Os serviços principais recebem apenas 1 GB
cada. A documentação atual exige recursos muito maiores e o Langfuse v4 requer
ClickHouse 25.12 no mínimo, recomendando 26.4. Portanto a combinação distribuída
é incompatível com uma atualização móvel para v4.

## Pré-requisitos

Planeje web e worker com pelo menos 2 CPU e 4 GiB cada, PostgreSQL, Redis/Valkey,
ClickHouse, storage S3 e espaço de retenção. O mínimo oficial de ClickHouse é 8
GiB e MinIO 4 GiB; o combo completo não cabe com segurança no rótulo de 4 GB.

## Fluxo seguro

Bloqueie produção. Fixe uma versão Langfuse compatível, atualize ClickHouse por
etapas, separe Redis em sua stack, use secrets e confirme todas as migrações.
MinIO deve usar bucket e identidade exclusivos. Cadastro público deve permanecer
fechado depois da criação controlada do administrador.

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

Valide health, migrações, ingestão, worker, ClickHouse, Redis, upload S3, consulta
e retenção.

## Diagnóstico

Separe falhas por componente e nunca envie prompts, respostas, chaves ou conteúdo
de clientes ao Assistente.

## Riscos e limites

Risco crítico por tags móveis, ClickHouse incompatível com v4, recursos muito
abaixo da referência e secrets gravados nos YAMLs. O Assistente deve informar
que o combo é exemplo não homologado para a arquitetura atual de produção.
