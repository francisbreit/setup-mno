---
{"schemaVersion":1,"documentId":"blueprint-001-whatsapp-marketing-knowledge","documentVersion":"0.1.0","contentSHA256":"cb4823bbdfab4ea0a11e1e1ad6f41d42c042e0ec2cb62fdaaaade93800333a0d","documentType":"blueprint","blueprintId":"blueprint-001-whatsapp-marketing-completo","fictitious":true,"deployable":false,"title":"Blueprint 001 — WhatsApp Marketing Completo (homologação)","setupVersion":"6.2.0","architectures":["amd64","arm64"],"category":"architecture","status":"reviewed","updatedAt":"2026-07-31","sourceType":"homologation-test","risk":"high","language":"pt-BR","tags":["blueprint","whatsapp","marketing","mautic","n8n","typebot"],"sources":[{"sourceId":"blueprint-001-manifest","title":"Manifesto canônico fictício do Blueprint 001","sourceType":"setup-mno","location":"setupmno-knowledge/blueprints/blueprint-001-whatsapp-marketing-completo/blueprint.json","license":"maintainer-owned","verifiedAt":"2026-07-31"}],"homologation":{"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}}
---
# Blueprint 001 — WhatsApp Marketing Completo

## Estado de homologação

Este documento é uma fixture fictícia de homologação do RAG. Ele percorre o mesmo pipeline reservado a um Blueprint real, mas não representa uma solução homologada, não autoriza deploy e não comprova funcionamento das integrações descritas.

## Objetivo

Simular uma arquitetura de campanhas de WhatsApp com segmentação no Mautic, orquestração e atrasos no n8n, filas RabbitMQ, conexão pela Evolution API, fluxos Typebot e atendimento humano no Chatwoot.

## Topologia

O Mautic representa a origem das campanhas. O n8n recebe os eventos, aplica o processamento controlado e utiliza a mensageria do combo principal. A Evolution API representa o canal não oficial, o Typebot representa os fluxos conversacionais e o Chatwoot concentra o atendimento humano. O MinIO é compartilhado conforme o manifesto, com separação lógica por bucket e identidade de acesso.

## Componentes

- CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ + MINIO*: atendimento, canal, fila e armazenamento compartilhado.
- MAUTIC 7 WHATSAPP MKT: contatos, segmentos, campanhas e mensagens.
- N8N V2 - FILA (QUEUE): webhooks, processamento, atrasos e controle da fila.
- TYPEBOT + MINIO*: construção dos fluxos conversacionais reutilizando o MinIO existente.

## Pré-requisitos

A estimativa fictícia é de 20 GB de RAM mínima e 24 GB recomendada, em amd64 ou arm64. É necessário validar capacidade real, domínios, persistência, backups, responsáveis, política de consentimento, limites do canal e credenciais protegidas antes de qualquer homologação.

## Ordem segura

1. Preparar e validar o combo Chatwoot, Evolution API, RabbitMQ e MinIO.
2. Preparar o Mautic customizado e o canal WhatsApp/SMS.
3. Preparar o n8n em fila e revisar os workflows antes de ativar gatilhos.
4. Preparar o Typebot reutilizando o MinIO com isolamento lógico.
5. Executar somente testes com destinatários e dados de laboratório autorizados.

## Validação

O cenário de homologação deve rastrear uma mensagem de texto do Mautic ao destinatário de laboratório, localizar um fluxo Typebot pelo identificador fictício e transferir uma conversa de teste para a caixa prevista do Chatwoot. Cada evento deve ocorrer uma única vez e produzir evidência auditável.

## Riscos e limites

O conteúdo não confirma APIs, templates, endpoints ou políticas reais. Campanhas podem gerar duplicidade, bloqueio do canal, perda de consentimento ou exposição de dados se idempotência, fila, rate limit e segregação de acesso não forem validados. A fixture nunca deve ser apresentada como pronta para produção.

## Rollback

Interromper campanhas e gatilhos de laboratório, drenar ou isolar somente as filas do teste, preservar exports sanitizados e restaurar a baseline pelo Instalador Seguro. Nenhum volume ou dado persistente deve ser removido automaticamente.
