---
{
  "schemaVersion": 1,
  "documentId": "setup-qdrant-overview",
  "documentVersion": "1.0.2",
  "contentSHA256": "61a0643ecfaf1729790a218bbf0c0c84f4243c747f53f797ec1d0f18d3e1aa18",
  "documentType": "setup",
  "title": "Qdrant no Setup MNO",
  "setupId": "qdrant",
  "setupVersion": "7.16.1",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-07-30",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["qdrant", "vector-db", "rag"],
  "sources": [
    {
      "sourceId": "qdrant-installer",
      "title": "Instalador Qdrant",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/qdrant.sh",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    },
    {
      "sourceId": "qdrant-catalog",
      "title": "Entrada Qdrant no catálogo",
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
# Qdrant no Setup MNO

## Quando usar

Use para busca vetorial e RAG quando a aplicação precisa de coleções
persistentes e API dedicada. Compare ChromaDB conforme escala, operação e
ecossistema do projeto.

## Arquitetura no Setup MNO

O setup cria uma instância com volume persistente, autenticação e participação
nas redes interna e externa. A aplicação consumidora se conecta à API conforme
a rota e política definidas.

## Pré-requisitos

Exige domínio, armazenamento, memória e definição do modelo de embeddings.
Classifique os dados antes de indexar e estabeleça política de exclusão e
reindexação.

## Fluxo seguro

O Instalador Seguro coleta domínio, gera a credencial, cria o volume e implanta
via Portainer ou Docker. A credencial é configurada na aplicação cliente sem
passar pelo Assistente.

## Validação

Confirme saúde, autenticação e ciclo de criação, consulta e remoção de uma
coleção descartável. Teste persistência antes de dados reais.

## Riscos e limites

Embeddings podem representar informação sensível. Alterar dimensões ou modelo
pode exigir reindexação. Backup do volume deve ser consistente com o estado da
coleção.

## Diagnóstico

Falha de autenticação difere de erro de dimensão e de indisponibilidade.
Qualidade baixa de busca deve avaliar chunking, embeddings e filtros antes de
culpar o banco.
