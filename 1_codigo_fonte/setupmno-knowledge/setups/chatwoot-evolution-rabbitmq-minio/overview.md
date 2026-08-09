---
{
  "schemaVersion": 1,
  "documentId": "setup-chatwoot-evolution-rabbitmq-minio-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "ff03bfd55b9634d037980031df8e7dd12a37f787d914c0ff547b07271bf96779",
  "documentType": "setup",
  "title": "Combo Chatwoot, Evolution API, RabbitMQ e MinIO no Setup MNO",
  "setupId": "chatwoot-evolution-rabbitmq-minio",
  "setupVersion": "7.7.40",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": ["chatwoot", "evolution-api", "rabbitmq", "minio", "whatsapp", "combo"],
  "sources": [
    {"sourceId":"chatwoot-evolution-combo-installer","title":"Instalador do combo Chatwoot, Evolution, RabbitMQ e MinIO","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/chatwootn_evo2_rabbitmq_minio.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"chatwoot-docker-docs","title":"Deploy oficial do Chatwoot com Docker","sourceType":"official-documentation","location":"https://developers.chatwoot.com/self-hosted/deployment/docker","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"evolution-combo-docs","title":"Evolution API v2 com Docker","sourceType":"official-documentation","location":"https://docs.evolutionfoundation.com.br/evolution-api/install/docker","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"minio-combo-docs","title":"Documentação oficial MinIO em contêiner","sourceType":"official-documentation","location":"https://min.io/docs/minio/container/index.html","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# Combo Chatwoot, Evolution API, RabbitMQ e MinIO no Setup MNO

## Quando usar

Use quando a solução precisa reunir atendimento omnichannel, conexão WhatsApp,
eventos assíncronos e storage de mídia sob uma operação única. Não use como
atalho para um projeto sem responsáveis: o combo exige governança de dados,
mensageria, backup, canais e capacidade.

## Arquitetura no Setup MNO

O instalador orquestra MinIO, dois Redis dedicados, RabbitMQ, Chatwoot web e
worker, e Evolution API. As dependências são criadas em stacks separadas. Banco
PostgreSQL, redes base, rotas públicas e buckets conectam os componentes. A
ordem de criação importa para migrações, filas e storage.

## Pré-requisitos

Exige vários domínios, PostgreSQL saudável, margem mínima compatível com a faixa
pesada do catálogo, SMTP, credenciais distintas, política da Meta, buckets,
retenção e responsáveis por cada serviço. Planeje crescimento de conversas,
mídias, filas e logs, não apenas RAM de repouso.

## Fluxo seguro

O Instalador Seguro coleta MinIO, RabbitMQ, Chatwoot, SMTP, Evolution e modo de
deploy; cria storage e buckets, caches, fila, atendimento e API. Revise todos os
dados antes da confirmação. Depois, mantenha menor privilégio por componente e
não reutilize credenciais administrativas entre integrações.

## Primeiro acesso e integrações

Valide em camadas: storage e buckets, RabbitMQ, banco e caches, Chatwoot web e
worker, Evolution e somente então o canal entre eles. Use uma caixa de entrada e
uma instância de teste. Configure webhooks e eventos necessários, com prevenção
de loop e idempotência.

## Backup e atualização

Backup consistente cobre bancos do Chatwoot e Evolution, volumes, objetos do
MinIO, configurações de RabbitMQ, segredos e dados necessários dos Redis. As
imagens do combo não seguem todas a versão oficial mais recente. Atualize um
componente por vez em homologação e execute migrações oficiais quando exigidas.

## Validação

Confirme saúde de cada stack, migrações, login no Chatwoot, worker consumindo
jobs, fila RabbitMQ, bucket restrito, pareamento da Evolution, mídia e mensagem
de ponta a ponta. Teste falha temporária e retomada sem duplicação antes de
considerar o combo operacional.

## Riscos e limites

Status crítico pela quantidade de componentes, exposição de painéis e defasagem
potencial das imagens. Portas de RabbitMQ publicadas no host precisam de revisão
de conflito e firewall. O canal baseado em WhatsApp Web tem risco adicional de
sessão e política. Quatro gigabytes são ponto de partida, não garantia.

## Diagnóstico

Siga a dependência: DNS e TLS, banco e volume, Redis, MinIO, RabbitMQ, Chatwoot,
Evolution e integração. Registre horário e correlação sanitizada. Nunca envie
conversa, telefone, chave global, credencial SMTP, bucket real ou senha da fila.
