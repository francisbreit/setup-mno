---
{
  "schemaVersion": 1,
  "documentId": "setup-minio-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "cc788b955eef33bdadc8f6fa4e5b217f0e39e3682c72cd64da078b9f49f2ca8b",
  "documentType": "setup",
  "title": "MinIO no Setup MNO",
  "setupId": "minio",
  "setupVersion": "7.7.35",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["minio", "s3", "storage", "objetos", "backup"],
  "sources": [
    {"sourceId":"minio-installer","title":"Instalador MinIO","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/minio.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"minio-container-docs","title":"Documentação oficial MinIO em contêiner","sourceType":"official-documentation","location":"https://min.io/docs/minio/container/index.html","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"minio-single-node-docs","title":"Limites de single-node single-drive","sourceType":"official-documentation","location":"https://min.io/docs/minio/container/operations/install-deploy-manage/deploy-minio-single-node-single-drive.html","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"minio-upgrade-docs","title":"Atualização oficial do MinIO","sourceType":"official-documentation","location":"https://min.io/docs/minio/container/operations/install-deploy-manage/upgrade-minio-deployment.html","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# MinIO no Setup MNO

## Quando usar

Use como storage de objetos compatível com S3 para aplicações como Typebot,
Chatwoot ou Evolution. Não o trate como diretório compartilhado nem como backup
por si só. Para dados críticos e alta disponibilidade, uma instância de nó e
disco únicos não oferece redundância contra falha do host ou volume.

## Arquitetura no Setup MNO

O instalador cria um serviço MinIO com volume persistente e rotas separadas para
API pública e console administrativo. A implantação fica no manager e atende às
duas arquiteturas. Aplicações consumidoras devem usar buckets e identidades
próprias, evitando a credencial administrativa.

## Pré-requisitos

Exige dois domínios, volume com espaço e desempenho adequados, credencial forte,
política de backup e previsão de crescimento. Defina buckets, retenção,
versionamento, ciclo de vida, criptografia e quem pode ler ou gravar cada
prefixo antes de integrar aplicações.

## Fluxo seguro

O Instalador Seguro coleta domínios e credencial administrativa, cria volume e
implanta via Portainer ou Docker. Depois, crie usuários ou service accounts com
menor privilégio por aplicação. O console administrativo não deve ser usado
como endpoint de dados nem compartilhado com usuários comuns.

## Primeiro acesso e integrações

Crie um bucket de teste, uma identidade restrita e valide upload, leitura e
negação fora do escopo. Ao integrar uma aplicação, confirme endpoint, protocolo,
região quando exigida e estilo de acesso compatível. Separe buckets de produção,
teste e backup.

## Backup e atualização

Replicação ou cópia externa deve existir fora do mesmo volume e host. Teste
restauração de objetos, metadados e políticas. Antes de atualizar, leia as notas
oficiais, preserve backup e valide em ambiente isolado; downgrade pode não ser
simples após mudança de formato ou comportamento.

## Validação

Confirme saúde do serviço, acesso ao console, operação S3 com identidade
restrita, persistência após recriação, política de negação e restauração de um
objeto descartável. Monitore espaço, latência, erros e expiração de certificados.

## Riscos e limites

Single-node single-drive é ponto único de falha e não oferece erasure coding
distribuído. Credencial administrativa dentro de aplicações amplia o impacto de
vazamento. Exposição pública do console, bucket anônimo indevido e falta de
limites podem causar perda ou divulgação de dados.

## Diagnóstico

Separe rota, certificado, autenticação, política, bucket, volume e capacidade.
Use nomes fictícios e códigos sanitizados. Nunca envie credenciais, URLs
assinadas, nomes de clientes ou listagem real de objetos ao Assistente.
