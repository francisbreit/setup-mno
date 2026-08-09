---
{
  "schemaVersion": 1,
  "documentId": "setup-documenso-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "05fea19bca3226e8f303668fc536d083479ef87ce4a912cc4f1af0b4292b1dff",
  "documentType": "setup",
  "title": "Documenso no Setup MNO",
  "setupId": "documenso",
  "setupVersion": "7.7.45",
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
    "documenso",
    "assinatura",
    "documentos",
    "s3"
  ],
  "sources": [
    {
      "sourceId": "documenso-installer",
      "title": "Instalador Documenso",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/documenso.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "documenso-requirements",
      "title": "Requisitos oficiais Documenso",
      "sourceType": "official-documentation",
      "location": "https://docs.documenso.com/docs/self-hosting/getting-started/requirements",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "documenso-storage",
      "title": "Storage oficial Documenso",
      "sourceType": "official-documentation",
      "location": "https://docs.documenso.com/docs/self-hosting/configuration/storage",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "documenso-upgrade",
      "title": "Atualização oficial Documenso",
      "sourceType": "official-documentation",
      "location": "https://docs.documenso.com/docs/self-hosting/maintenance/upgrades",
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
# Documenso no Setup MNO

## Quando usar

Use para fluxos de assinatura eletrônica de documentos quando requisitos jurídicos e de identidade tiverem sido avaliados. Não declare validade legal universal nem equivalência a assinatura qualificada.

## Arquitetura no Setup MNO

O instalador usa `Documenso na tag latest`, PostgreSQL compartilhado, opção S3/MinIO e SMTP. Hoje exibe credenciais S3 e SMTP na confirmação, mantém signup habilitado e não coleta o certificado de assinatura exigido pela documentação oficial.

## Pré-requisitos

Oficialmente requer PostgreSQL 14+, certificado de assinatura, SMTP e cerca de 2 GB em produção; S3 é recomendado. Exige domínio HTTPS, política jurídica, retenção e identidade dos signatários.

## Fluxo seguro

Não use em produção até remover credenciais da tela/YAML, bloquear cadastro conforme política e configurar certificado de assinatura. Chaves, documentos e evidências nunca devem chegar ao Assistente.

## Primeiro acesso e integrações

Com dados fictícios, crie equipe, modelo, documento e fluxo com dois signatários; valide email, ordem, assinatura e trilha. Confirme storage e certificado.

## Backup e atualização

Preserve PostgreSQL, objetos S3/MinIO, certificado e segredos. Faça backup antes de cada atualização; teste restauração completa e retenha imagem anterior compatível com o dump.

## Validação

Confirme HTTPS, cadastro restrito, certificado, upload, assinatura, evidências, email, download, persistência e restauração. Audite que credenciais não aparecem na UI ou logs.

## Riscos e limites

Ausência do certificado obrigatório, recursos abaixo do recomendado, cadastro aberto e exposição explícita de credenciais tornam o instalador atual não homologado para produção jurídica.

## Diagnóstico

Separe banco, storage, certificado, SMTP, jobs e proxy. Use documentos simulados; nunca compartilhe contratos, assinaturas, evidências ou tokens.
