---
{"schemaVersion":1,"documentId":"blueprint-001-whatsapp-marketing-knowledge","documentVersion":"1.0.0","contentSHA256":"17a4c3899f63591f34d2dfa5fb6d4f41a5d853dfb7d8c8540de76873932cd422","documentType":"blueprint","blueprintId":"blueprint-001-whatsapp-marketing-completo","fictitious":false,"deployable":true,"title":"Blueprint 001 — WhatsApp Marketing Completo","setupVersion": "7.47.0","architectures":["amd64","arm64"],"category":"architecture","status":"homologated","updatedAt":"2026-09-02","sourceType":"maintainer-authored","risk":"medium","language":"pt-BR","tags":["blueprint","whatsapp","marketing","mautic","n8n","typebot"],"sources":[{"sourceId":"blueprint-001-manifest","title":"Manifesto canônico do Blueprint 001","sourceType":"setup-mno","location":"setupmno-knowledge/blueprints/blueprint-001-whatsapp-marketing-completo/blueprint.json","license":"maintainer-owned","verifiedAt":"2026-08-31"}],"homologation":{"verifiedAt":"2026-08-31","verifiedPorts":[],"verifiedImages":[]}}
---
# Blueprint 001 — WhatsApp Marketing Completo

## Estado de homologação

Este é um guia Beta revisado para orientar a montagem manual. Ele ainda não possui homologação técnica de ponta a ponta, não executa deploy e exige validação humana em cada etapa.

## Objetivo

Montar uma arquitetura de campanhas de WhatsApp com segmentação no Mautic, orquestração e atrasos no n8n, filas RabbitMQ, conexão pela Evolution API, fluxos Typebot e atendimento humano no Chatwoot.

## Topologia

O Mautic representa a origem das campanhas. O n8n recebe os eventos, aplica o processamento controlado e utiliza a mensageria do combo principal. A Evolution API representa o canal não oficial, o Typebot representa os fluxos conversacionais e o Chatwoot concentra o atendimento humano. O MinIO é compartilhado conforme o manifesto, com separação lógica por bucket e identidade de acesso.

## Componentes

- CHATWOOTORIG (DESBLOQUEADO) + EVOLUTIONN 2.0 + RABBITMQ + MINIO*: atendimento, canal, fila e armazenamento compartilhado.
- MAUTIC 7 WHATSAPP MKT: contatos, segmentos, campanhas e mensagens.
- N8N V2 - FILA (QUEUE): webhooks, processamento, atrasos e controle da fila.
- TYPEBOT + MINIO*: construção dos fluxos conversacionais reutilizando o MinIO existente.

## Pré-requisitos

A estimativa preliminar é de 20 GB de RAM mínima e 24 GB recomendada, em amd64 ou arm64. É necessário validar capacidade real, domínios, persistência, backups, responsáveis, política de consentimento, limites do canal e credenciais protegidas antes de qualquer homologação.

## Ordem segura

1. Preparar e validar o combo Chatwoot, Evolution API, RabbitMQ e MinIO.
2. Preparar o Mautic customizado e o canal WhatsApp/SMS.
3. Preparar o n8n em fila e revisar os workflows antes de ativar gatilhos.
4. Preparar o Typebot reutilizando o MinIO com isolamento lógico.
5. Executar somente testes com destinatários e dados de laboratório autorizados.

## Validação

O cenário de validação deve rastrear uma mensagem de texto do Mautic ao destinatário controlado, localizar um fluxo Typebot pelo identificador documentado e transferir uma conversa de teste para a caixa prevista do Chatwoot. Cada evento deve ocorrer uma única vez e produzir evidência auditável.

## Riscos e limites

O conteúdo ainda não homologa APIs, templates, endpoints ou políticas. Campanhas podem gerar duplicidade, bloqueio do canal, perda de consentimento ou exposição de dados se idempotência, fila, rate limit e segregação de acesso não forem validados. O guia Beta não deve ser apresentado como homologado para produção.

## Rollback

Interromper campanhas e gatilhos de laboratório, drenar ou isolar somente as filas do teste, preservar exports sanitizados e restaurar a baseline pelo Instalador Seguro. Nenhum volume ou dado persistente deve ser removido automaticamente.
