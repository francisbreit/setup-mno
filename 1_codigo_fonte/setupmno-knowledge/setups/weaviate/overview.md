---
{
  "schemaVersion": 1,
  "documentId": "setup-weaviate-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "b431fef7f25e0949b36e828f5945b14f9a7ad16b9216c1a27c6353394ed3f60c",
  "documentType": "setup",
  "title": "Weaviate no Setup MNO",
  "setupId": "weaviate",
  "setupVersion": "7.2.13",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": ["weaviate", "vector-database", "rag", "busca-semantica", "embeddings"],
  "sources": [
    {"sourceId":"weaviate-installer","title":"Instalador Weaviate","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/weaviate.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"weaviate-docker","title":"Instalação Docker oficial do Weaviate","sourceType":"official-documentation","location":"https://docs.weaviate.io/deploy/installation-guides/docker-installation","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"weaviate-auth","title":"Autenticação oficial do Weaviate","sourceType":"official-documentation","location":"https://docs.weaviate.io/deploy/configuration/authentication","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"weaviate-backup","title":"Backups do Weaviate","sourceType":"official-documentation","location":"https://docs.weaviate.io/deploy/configuration/backups","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# Weaviate no Setup MNO

## Quando usar

Use para busca vetorial, híbrida e RAG quando o modelo de coleções e módulos do
Weaviate atender ao projeto. Não use sem definir origem dos vetores, política de
reindexação, distância e retenção.

## Arquitetura no Setup MNO

O script usa uma tag móvel da imagem Weaviate, uma réplica, 1 GB, volume de
dados e uma porta fixa publicada no host. Define apenas uma variável chamada
`AUTHENTICATION_APIKEY_ADMIN_KEYS`; não habilita autenticação por API key, não
declara usuários permitidos nem RBAC conforme a configuração oficial atual.

## Pré-requisitos

Defina vetorizador externo ou dados pré-vetorizados, memória por coleção, disco,
backup e acesso gRPC se necessário. Docker Compose é indicado para escala pequena;
produção escalável exige desenho de cluster e recursos medidos.

## Fluxo seguro

Não prossiga em produção. Fixe a imagem no registry oficial, remova a porta do
host, desabilite acesso anônimo explicitamente, habilite API key com usuários e
RBAC e guarde chaves fora do YAML. Configure hostname de cluster mesmo em nó único.

## Primeiro acesso e integrações

Após correções, consulte readiness, crie uma coleção fictícia, insira vetores e
teste busca com usuário não administrativo. Dify, Langflow e aplicações RAG devem
usar endpoint interno e credencial própria.

## Backup, atualização e rollback

Ative provider de backup compatível e teste restauração; backup de filesystem
local serve principalmente a desenvolvimento. Antes da atualização, revise a
matriz de migração, preserve backup externo e mantenha versão anterior.

## Validação

Valide versão, readiness, anonimato desativado, API key, RBAC, persistência,
coleção, busca, gRPC quando usado e restauração.

## Diagnóstico

Separe falhas de schema, vetor, memória, módulo e autorização. Não envie vetores,
documentos ou chaves ao Assistente.

## Riscos e limites

Risco crítico porque a autenticação declarada é incompleta, a porta do host está
aberta e a imagem é móvel. A descrição do catálogo também se chama alternativa
ao próprio Weaviate, texto que deve ser corrigido em lote específico de catálogo.
