---
{
  "schemaVersion": 1,
  "documentId": "setup-openclaw-knowledge-stack-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "0929e3d271f539a5396db5d7ef60ce4983dc9f90effd0838b4d302cd46084428",
  "documentType": "setup",
  "title": "OpenClaw + Qdrant + Neo4j + Cognee + SearXNG no Setup MNO",
  "setupId": "openclaw-knowledge-stack",
  "setupVersion": "7.2.13",
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
    "openclaw",
    "qdrant",
    "neo4j",
    "cognee",
    "searxng",
    "combo"
  ],
  "sources": [
    {
      "sourceId": "openclaw-knowledge-stack-installer",
      "title": "Instalador OpenClaw + Qdrant + Neo4j + Cognee + SearXNG",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/openclawpro.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "openclaw-combo-docs",
      "title": "Documentação oficial do OpenClaw",
      "sourceType": "official-documentation",
      "location": "https://docs.openclaw.ai/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "qdrant-docs",
      "title": "Documentação oficial do Qdrant",
      "sourceType": "official-documentation",
      "location": "https://qdrant.tech/documentation/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "neo4j-docs",
      "title": "Documentação oficial do Neo4j",
      "sourceType": "official-documentation",
      "location": "https://neo4j.com/docs/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "cognee-docs",
      "title": "Documentação oficial do Cognee",
      "sourceType": "official-documentation",
      "location": "https://docs.cognee.ai/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "searxng-docs",
      "title": "Documentação oficial do SearXNG",
      "sourceType": "official-documentation",
      "location": "https://docs.searxng.org/",
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
# OpenClaw + Qdrant + Neo4j + Cognee + SearXNG no Setup MNO

## Quando usar

Use este combo hipotético para laboratório de agente com memória vetorial, grafo e busca. Só escolha a composição quando cada componente tiver uma responsabilidade comprovada; mais serviços não garantem respostas melhores.

## Arquitetura no Setup MNO

O script coordena stacks separadas para OpenClaw, Qdrant, Neo4j, Cognee, SearXNG e dependências. As integrações são configuradas pelo instalador, mas o combo não possui homologação editorial como Blueprint implantável.

## Pré-requisitos

O catálogo declara cerca de 4 GB de RAM para o combo, valor que precisa ser medido com todos os componentes e carga de ingestão ativos.

Exige pelo menos os recursos indicados no catálogo, provedores compatíveis, domínio, storage e políticas de coleta, retenção e acesso. Defina IDs, embeddings e esquema do grafo antes de ingerir conteúdo.

## Fluxo seguro

Implante em dados fictícios, restrinja todos os bancos à rede interna e exponha apenas a interface indispensável. O agente não recebe acesso ao Docker, host ou credenciais administrativas.

## Primeiro acesso e integrações

Valide cada componente isoladamente e depois o caminho busca, ingestão, recuperação e resposta. Compare o resultado com uma baseline sem memória para provar o ganho.

## Backup e atualização

Faça backup consistente de configurações, vetores, grafo e metadados de ingestão. Registre versões de todos os componentes e teste restauração na mesma matriz.

## Validação

Confirme saúde individual, autenticação, isolamento, recuperação com fonte, deleção por política e comportamento sem um componente. Meça RAM e latência sob carga sintética.

## Riscos e limites

A composição multiplica falhas, versões e cópias de dados. Prompt injection em conteúdo recuperado, divergência entre índices e tags flutuantes tornam o risco crítico.

## Diagnóstico

Trace uma consulta por agente, busca, ingestão, vetor, grafo e resposta. Não tente corrigir tudo ao mesmo tempo; use IDs sintéticos e evidências sanitizadas.
