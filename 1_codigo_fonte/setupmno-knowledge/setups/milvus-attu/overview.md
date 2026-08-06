---
{
  "schemaVersion": 1,
  "documentId": "setup-milvus-attu-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "91f3550456a34deb60cd07f67265e56d48802baa55a1ff2c15332b035bdf11e7",
  "documentType": "setup",
  "title": "Milvus com Attu no Setup MNO",
  "setupId": "milvus-attu",
  "setupVersion": "7.7.25",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": ["milvus", "attu", "vector-database", "rag", "minio"],
  "sources": [
    {"sourceId":"milvus-installer","title":"Instalador Milvus e Attu","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/milvus.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"milvus-compose","title":"Milvus standalone com Docker Compose","sourceType":"official-documentation","location":"https://milvus.io/docs/v2.4.x/install_standalone-docker-compose.md","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"milvus-requirements","title":"Requisitos do Milvus standalone","sourceType":"official-documentation","location":"https://milvus.io/docs/v2.4.x/prerequisite-docker.md","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"milvus-backup","title":"Backup e restauração do Milvus","sourceType":"official-documentation","location":"https://milvus.io/docs/v2.4.x/milvus_backup_api.md","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# Milvus com Attu no Setup MNO

## Quando usar

Use para coleções vetoriais grandes, busca de similaridade e RAG quando Qdrant,
ChromaDB ou Weaviate não atendem ao desenho. Não escolha apenas por volume de
estrelas: índice, dimensão, métrica, crescimento e operação são determinantes.

## Arquitetura no Setup MNO

O combo instala MinIO compartilhado ou novo, etcd 3.5.25, Milvus 2.4.16 em modo
standalone e Attu 3.0.0-beta.6. O Milvus recebe limite de 4 GB, enquanto a
documentação 2.4 exige no mínimo 8 GB e recomenda 16 GB para standalone. A UI
beta é exposta por HTTPS sem camada de autenticação declarada no YAML.

## Pré-requisitos

Exige CPU com extensão SIMD compatível, SSD com baixa latência, memória, etcd e
storage S3 consistentes. A referência recomenda quatro núcleos ou mais e validação
de IOPS. Dimensione também embeddings, réplicas, índice e retenção.

## Fluxo seguro

Não recomende produção no estado atual. Fixe versões suportadas, use Attu estável,
proteja a interface administrativa, eleve recursos e homologue a identidade S3.
Etcd, Milvus e MinIO devem ter persistência e recuperação coordenadas.

## Primeiro acesso e integrações

Após correções, crie coleção fictícia, insira vetores, construa índice, carregue
e teste similaridade. Dify, Langflow e aplicações RAG devem usar endpoint interno
e credenciais de menor privilégio quando disponíveis.

## Backup, atualização e rollback

Milvus Backup depende do storage de objetos corretamente configurado e não grava
backup em caminho local simples. Preserve metadados do etcd e objetos MinIO,
teste restauração em conjunto e siga a matriz de upgrade entre versões.

## Validação

Valide CPU, IOPS, etcd, bucket, Milvus, Attu, coleção, índice, inserção, busca,
persistência e restauração.

## Diagnóstico

Separe falha de metadado, objeto, memória e rede. Não envie vetores, documentos,
chaves S3 ou dados de clientes ao Assistente.

## Riscos e limites

Risco crítico por RAM abaixo do mínimo oficial, versões antigas, UI beta exposta
e ausência de backup automatizado. O catálogo de aproximadamente 2 GB diverge
ainda mais dos requisitos reais do conjunto.
