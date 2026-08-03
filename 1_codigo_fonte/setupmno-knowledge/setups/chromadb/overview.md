---
{
  "schemaVersion": 1,
  "documentId": "setup-chromadb-overview",
  "documentVersion": "1.0.2",
  "contentSHA256": "5c99b4f6f98e0cc4ca6472f90dbbbaf8be42b074f1708aecbfced2411222b6a8",
  "documentType": "setup",
  "title": "ChromaDB no Setup MNO",
  "setupId": "chromadb",
  "setupVersion": "7.7.1",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-07-30",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["chromadb", "vector-db", "rag"],
  "sources": [
    {
      "sourceId": "chromadb-installer",
      "title": "Instalador ChromaDB",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/chromadb.sh",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    },
    {
      "sourceId": "chromadb-catalog",
      "title": "Entrada ChromaDB no catálogo",
      "sourceType": "setup-mno",
      "location": "setupmno-control/catalog.json",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    }
  ],
  "homologation": {
    "verifiedAt": null,
    "verifiedPorts": [],
    "verifiedImages": []
  }
}
---
# ChromaDB no Setup MNO

## Quando usar

Use como banco vetorial para protótipos e aplicações de recuperação semântica.
Compare Qdrant quando houver requisitos diferentes de operação, escalabilidade
ou integração.

## Arquitetura no Setup MNO

A stack cria uma instância com persistência própria, autenticação por token,
redes interna e externa e rota pública conforme o modo de instalação.

## Pré-requisitos

Exige domínio, infraestrutura-base, volume e uma política para os documentos
indexados. Dados pessoais ou de clientes não devem ser carregados sem base
legal, sanitização e controle de acesso.

## Fluxo seguro

O instalador coleta domínio, gera ou recebe a credencial pelo fluxo protegido,
cria volume e implanta via Portainer ou Docker. A credencial nunca entra no
Assistente.

## Validação

Confirme saúde da réplica, autenticação e criação de uma coleção vazia de
teste. Valide persistência antes de indexar conteúdo real.

## Riscos e limites

Vetores podem reter informação sensível e não equivalem a anonimização.
Mudanças de modelo de embeddings podem tornar coleções incompatíveis. Registre
modelo e política de reindexação na aplicação consumidora.

## Diagnóstico

Falha de autenticação é diferente de indisponibilidade da réplica. Resultados
ruins podem vir da estratégia de chunking ou embeddings, não do banco. Evite
expor documentos recuperados ao suporte.
