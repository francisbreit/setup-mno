---
{
  "schemaVersion": 1,
  "documentId": "setup-typebot-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "daccf0f0d7767455d762e7482902a89e700ee49646154e9cfac7705d037e73fa",
  "documentType": "setup",
  "title": "Typebot sem MinIO no Setup MNO",
  "setupId": "typebot",
  "setupVersion": "7.2.13",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": ["typebot", "chatbot", "builder", "viewer", "s3"],
  "sources": [
    {"sourceId":"typebot-installer","title":"Instalador Typebot sem MinIO","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/typebot.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"typebot-docker-docs","title":"Deploy oficial do Typebot com Docker","sourceType":"official-documentation","location":"https://docs.typebot.com/self-hosting/deploy/docker","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"typebot-config-docs","title":"Configuração oficial do Typebot","sourceType":"official-documentation","location":"https://docs.typebot.com/self-hosting/configuration","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"typebot-s3-docs","title":"Configuração S3 do Typebot","sourceType":"official-documentation","location":"https://docs.typebot.com/self-hosting/guides/s3","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# Typebot sem MinIO no Setup MNO

## Quando usar

Use para construir e publicar formulários conversacionais quando já existe um
storage compatível com S3 administrado fora desta stack. Para instalação nova,
prefira a variante Typebot + MinIO, que explicita a dependência de objetos.

## Arquitetura no Setup MNO

O setup cria builder e viewer em uma stack, banco lógico no PostgreSQL base e
duas rotas públicas. O storage não é instalado: o usuário informa um endpoint
externo. Builder e viewer precisam compartilhar banco, segredo de criptografia,
URLs públicas, SMTP e configuração S3.

## Pré-requisitos

Exige domínios distintos para edição e publicação, domínio de storage, bucket,
PostgreSQL e SMTP válido para autenticação por email. O storage deve existir,
ter política mínima e permitir o fluxo de upload exigido pelo Typebot.

## Fluxo seguro

Bloqueio de segurança vigente: o instalador atual contém credenciais S3 estáticas
no template. Não use esta variante em produção até que as credenciais sejam
coletadas ou geradas de forma exclusiva e o instalador seja corrigido. Não copie
nem reutilize os valores presentes no script.

## Primeiro acesso e integrações

Após a correção do bloqueio, valide login no builder, publicação no viewer,
upload descartável e envio de email. Integrações com webhook, Chatwoot, n8n e
canais externos devem usar autenticação própria, consentimento e limitação de
dados. O domínio do viewer precisa coincidir com a URL configurada.

## Backup e atualização

Backup precisa incluir PostgreSQL, objetos do bucket e segredo de criptografia.
Preserve as mesmas chaves entre builder e viewer. Antes de atualizar, confira
breaking changes, fixe uma versão quando estabilidade for prioritária e teste
publicação, upload e autenticação em cópia isolada.

## Validação

Somente após corrigir o instalador: confirme builder, viewer, autenticação,
publicação, upload e leitura do objeto, persistência e email. Abertura da tela não
valida storage nem recuperação. Revogue qualquer credencial que tenha sido
exposta ou compartilhada.

## Riscos e limites

Status crítico até correção das credenciais estáticas. Tags móveis também podem
introduzir mudanças sem janela controlada. Upload público, SMTP incorreto e
segredo divergente entre serviços causam falha ou exposição. Esta documentação
não converte a variante atual em setup homologado.

## Diagnóstico

Separe builder, viewer, banco, SMTP e storage. Verifique domínio configurado,
permissões do bucket e consistência do segredo sem exibir valores. Nunca envie
senha, access key, secret key, conteúdo de formulário ou dados de lead ao chat.
