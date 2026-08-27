---
{
  "schemaVersion": 1,
  "documentId": "setup-memgraph-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "c839b9d92f35e97e9db0b9650b068ca39e6378999d6b8e69f1e059e8380cb41d",
  "documentType": "setup",
  "title": "Memgraph no Setup MNO",
  "setupId": "memgraph",
  "setupVersion": "7.36.2",
  "architectures": [
    "amd64",
    "arm64"
  ],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": [
    "memgraph",
    "grafos",
    "cypher",
    "graph-rag"
  ],
  "sources": [
    {
      "sourceId": "memgraph-installer",
      "title": "Instalador Memgraph",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/memgraph.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "memgraph-docs",
      "title": "Documentação oficial do Memgraph",
      "sourceType": "official-documentation",
      "location": "https://memgraph.com/docs",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "memgraph-quickstart",
      "title": "Quickstart oficial do Memgraph",
      "sourceType": "official-documentation",
      "location": "https://memgraph.com/docs/getting-started",
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
# Memgraph no Setup MNO

## Quando usar

Use para grafos consultados por Cypher, análise de relacionamentos e experimentos de Graph RAG. Prefira um banco relacional ou vetorial quando o problema não depender de relações explícitas.

## Arquitetura no Setup MNO

O instalador usa a distribuição Memgraph Platform em uma stack única, com interface visual e persistência conforme o script. O uso de tag flutuante exige registrar a imagem resolvida antes de promover.

## Pré-requisitos

O catálogo declara cerca de 1 GB de RAM, mas grafos e índices podem superar rapidamente essa referência; dimensione com uma amostra representativa.

Exige memória compatível com o grafo, storage, modelo de dados, política de retenção e cliente Cypher. Dimensione pela cardinalidade de nós, arestas, índices e consultas concorrentes, não apenas pelo tamanho bruto.

## Fluxo seguro

Restrinja os endpoints do banco à rede interna e publique somente a interface necessária atrás de autenticação. Não envie consultas, dados do grafo ou credenciais ao Assistente.

## Primeiro acesso e integrações

Comece com grafo fictício, crie índices deliberadamente e valide limites de consulta. Integrações com agentes precisam de usuário dedicado e consultas parametrizadas.

## Backup e atualização

Siga os mecanismos de snapshot e exportação compatíveis com a versão efetiva. Teste restauração em ambiente isolado antes de atualizar imagem ou esquema.

## Validação

Confirme saúde, persistência, consulta Cypher simples, índices, autenticação, consumo de RAM e restauração. Registre a versão efetiva da plataforma.

## Riscos e limites

Grafos em memória podem crescer rapidamente; consultas amplas causam pressão de recursos. Tag flutuante e exposição de interfaces administrativas elevam o risco.

## Diagnóstico

Separe proxy, interface, protocolo do banco, autenticação, consulta, índice, memória e disco. Reproduza com um grafo sintético mínimo.
