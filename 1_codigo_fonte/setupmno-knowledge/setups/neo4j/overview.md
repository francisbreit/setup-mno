---
{
  "schemaVersion": 1,
  "documentId": "setup-neo4j-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "a9c6c29ca8cfec3b3b2f90d4ab45bc8f24ebb0f14c46873ca491d6e210b7c107",
  "documentType": "setup",
  "title": "Neo4j no Setup MNO",
  "setupId": "neo4j",
  "setupVersion": "7.34.1",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": ["neo4j", "grafos", "cypher", "knowledge-graph", "database"],
  "sources": [
    {"sourceId":"neo4j-installer","title":"Instalador Neo4j","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/neo4j.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"neo4j-docker","title":"Neo4j oficial em Docker","sourceType":"official-documentation","location":"https://neo4j.com/docs/operations-manual/current/docker/introduction/","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"neo4j-security","title":"TLS no Neo4j em Docker","sourceType":"official-documentation","location":"https://neo4j.com/docs/operations-manual/current/docker/security/","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"neo4j-backup","title":"Backup e restauração do Neo4j","sourceType":"official-documentation","location":"https://neo4j.com/docs/operations-manual/current/backup-restore/","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# Neo4j no Setup MNO

## Quando usar

Use para relações complexas, caminhos, dependências, fraude e knowledge graphs.
Não substitua banco relacional por grafo sem consultas e modelo que se beneficiem
de travessias; duplicar toda a origem sem sincronização cria inconsistência.

## Arquitetura no Setup MNO

A tela chama a instalação de Enterprise, mas o YAML usa `neo4j:latest`, que sem o
sufixo Enterprise instala Community. APOC e Graph Data Science não são ativados.
Uma réplica publica Browser e Bolt, este último em uma porta alternativa do host,
sem TLS declarado. Dados e logs ficam em volumes externos.

## Pré-requisitos

Escolha Community ou Enterprise conscientemente; Enterprise exige licença aceita.
Dimensione heap, page cache, disco e modelo. Alta disponibilidade, RBAC ampliado
e backup online dependem da edição e da topologia.

## Fluxo seguro

Não prossiga em produção com título e edição divergentes. Fixe versão e edição,
remova portas públicas, configure TLS para Browser e Bolt e habilite plugins
somente se a versão for compatível. Credenciais devem ficar fora do YAML.

## Primeiro acesso e integrações

Após correções, autentique como `neo4j`, altere a senha quando aplicável e execute
Cypher sobre dados fictícios. Aplicações RAG podem acessar Bolt internamente com
usuário restrito; não compartilhe administrador.

## Backup, atualização e rollback

Métodos de backup variam entre Community e Enterprise. Preserve `/data`, banco,
versão e plugins e teste o procedimento documentado para a edição escolhida.
Uma tag móvel impede restaurar com confiança após mudança de formato.

## Validação

Valide edição, versão, autenticação, TLS, Browser, Bolt, persistência, Cypher,
plugins e restauração.

## Diagnóstico

Separe falhas de protocolo, certificado, memória, store e plugin. Não envie
grafos, consultas, senhas ou dados pessoais ao Assistente.

## Riscos e limites

Risco crítico por promessa de Enterprise com imagem Community, tag móvel, portas
do host e ausência de TLS. Uma réplica Community não entrega cluster nem recursos
Enterprise; o Assistente deve corrigir essa expectativa explicitamente.
