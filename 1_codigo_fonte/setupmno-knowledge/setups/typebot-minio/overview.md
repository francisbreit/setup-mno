---
{
  "schemaVersion": 1,
  "documentId": "setup-typebot-minio-overview",
  "documentVersion": "1.0.2",
  "contentSHA256": "b79a4d4b269d975fbe66498293e57195d9b188a9766d01785ded3c219c5119ba",
  "documentType": "setup",
  "title": "Typebot com MinIO no Setup MNO",
  "setupId": "typebot-minio",
  "setupVersion": "7.7.50",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-07-30",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["typebot", "minio", "chatbot"],
  "sources": [
    {
      "sourceId": "typebot-minio-installer",
      "title": "Instalador Typebot com MinIO",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/typebot_minio.sh",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    },
    {
      "sourceId": "typebot-minio-catalog",
      "title": "Entrada Typebot com MinIO no catálogo",
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
# Typebot com MinIO no Setup MNO

## Quando usar

Use para criar chatbots e formulários com builder, viewer e armazenamento S3
compatível. A variante com MinIO é adequada quando os fluxos precisam de
arquivos sob controle próprio.

## Arquitetura no Setup MNO

O fluxo prepara ou reutiliza MinIO conforme a estratégia compartilhada, cria
recursos isolados para o Typebot e implanta builder e viewer conectados ao
PostgreSQL base. Cada interface possui papel e rota distintos.

## Pré-requisitos

Exige infraestrutura-base, PostgreSQL, domínios do builder, viewer e storage,
SMTP e capacidade de armazenamento. Defina retenção e tamanho de uploads.

## Fluxo seguro

O instalador coleta dados pelo Whiptail, prepara storage, banco e segredos e
implanta dependências antes da aplicação. No Portainer, cada stack deve
permanecer editável e com ordem explícita.

## Validação

Confirme acesso ao builder e viewer, criação de bot descartável, envio de
arquivo de teste e leitura pelo fluxo. Verifique storage e banco separadamente.

## Riscos e limites

Falha do storage afeta uploads mesmo quando o chatbot responde. Credenciais S3
devem ser restritas ao recurso do Typebot. Backup consistente cobre banco,
configuração e objetos.

## Diagnóstico

Builder indisponível aponta para aplicação ou rota; viewer sem conteúdo pode
ser publicação do bot. Erro de arquivo aponta para MinIO, política ou
conectividade. Nunca cole credenciais de storage no Assistente.
