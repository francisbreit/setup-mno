---
{
  "schemaVersion": 1,
  "documentId": "setup-mattermost-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "209605f5fd18f86e88b33e64d5874f98b204f58e463bdc7976f800411cf95aa4",
  "documentType": "setup",
  "title": "Mattermost no Setup MNO",
  "setupId": "mattermost",
  "setupVersion": "7.2.16",
  "architectures": ["amd64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["mattermost", "chat", "colaboracao", "postgresql", "webhook"],
  "sources": [
    {"sourceId":"mattermost-installer","title":"Instalador Mattermost","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/mattermost.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"mattermost-containers","title":"Deploy Mattermost using Containers","sourceType":"official-documentation","location":"https://docs.mattermost.com/deployment-guide/server/deploy-containers.html","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"mattermost-requirements","title":"Software and hardware requirements","sourceType":"official-documentation","location":"https://docs.mattermost.com/deployment-guide/software-hardware-requirements.html","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"mattermost-backup","title":"Backup and disaster recovery","sourceType":"official-documentation","location":"https://docs.mattermost.com/deployment-guide/backup-disaster-recovery.html","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# Mattermost no Setup MNO

## Quando usar

Use para colaboração por canais, mensagens e integrações quando a organização
quer controlar os dados. Não escolha apenas como substituto visual de outro
chat: retenção, busca, chamadas, compliance e operação variam por edição.

## Arquitetura no Setup MNO

O catálogo limita esta entrada a amd64. O instalador executa a edição Team em
nó único, com volumes de dados, configuração, logs e plugins, usando uma base
no PostgreSQL compartilhado. A imagem usa tag móvel.

## Pré-requisitos

Exige domínio, TLS, PostgreSQL saudável, SMTP, armazenamento e memória
dimensionados por usuários e chamadas. Defina política de cadastro, retenção,
plugins, backup e acesso administrativo antes de convidar a equipe.

## Fluxo seguro

Confirme arquitetura e capacidade, execute pelo Instalador Seguro e crie o
primeiro administrador individual. Restrinja criação de equipes e contas,
configure email e revise plugins e webhooks. Chamadas exigem requisitos de rede
e HTTPS adicionais.

## Primeiro acesso e integrações

Teste canal privado, usuário comum, upload, notificação e webhook descartável.
SSO, bots e plugins devem usar contas de serviço e tokens de menor privilégio,
com rotação e proprietário definidos.

## Backup, atualização e rollback

Recuperação requer banco, configuração e arquivos locais compatíveis. Preserve
todos antes de atualizar, fixe versão, leia notas de compatibilidade e ensaie a
restauração. Voltar a imagem sem reverter migrações não é rollback seguro.

## Validação

Valide login, mensagens, anexos, busca, email, webhook, persistência e uma
restauração descartável. Meça memória com carga representativa.

## Diagnóstico

Separe proxy, aplicação, PostgreSQL, armazenamento, email e plugin. Não envie
mensagens, anexos, tokens, dados pessoais ou configuração ao Assistente.

## Riscos e limites

Tag móvel, banco compartilhado, limite baixo de memória e ausência de ARM no
catálogo impedem assumir prontidão ampla. Alta disponibilidade e chamadas não
são homologadas por este documento.
