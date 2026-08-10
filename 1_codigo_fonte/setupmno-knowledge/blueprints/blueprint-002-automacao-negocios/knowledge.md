---
{"schemaVersion":1,"documentId":"blueprint-002-automacao-negocios-knowledge","documentVersion":"0.2.0","contentSHA256":"4c69df3e8935a6afe0bf90d03a30fd9a1c037d86a21becbe27a3ae5c2635b8a8","documentType":"blueprint","blueprintId":"blueprint-002-automacao-negocios","fictitious":false,"deployable":false,"title":"Blueprint 002 — Automação de Negócios","setupVersion": "7.8.5","architectures":["amd64","arm64"],"category":"architecture","status":"reviewed","updatedAt":"2026-08-02","sourceType":"maintainer-authored","risk":"medium","language":"pt-BR","tags":["blueprint","automacao","workflow","activepieces","n8n","bookstack"],"sources":[{"sourceId":"blueprint-002-manifest","title":"Manifesto canônico do Blueprint 002","sourceType":"setup-mno","location":"setupmno-knowledge/blueprints/blueprint-002-automacao-negocios/blueprint.json","license":"maintainer-owned","verifiedAt":"2026-08-02"}],"homologation":{"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}}
---
# Blueprint 002 — Automação de Negócios

## Estado de homologação

Este é um guia Beta revisado para orientar a montagem manual. Ele não executa deploy e ainda exige validação de processos, integrações e capacidade no ambiente de destino.

## Objetivo

Montar uma plataforma de automação em que procedimentos são documentados no BookStack, processos leves ficam no Activepieces e workflows avançados ou enfileirados ficam no n8n.

## Topologia

O BookStack funciona como referência humana dos processos e critérios de aceite. Activepieces e n8n são motores separados: cada automação deve ter um único responsável pela execução principal para evitar duplicidade e conflitos de manutenção.

## Componentes

- BOOKSTACK: procedimentos, responsáveis e critérios de aceite.
- ACTIVEPIECES: automações leves e integrações simplificadas.
- N8N V2 - FILA (QUEUE): workflows avançados, concorrência e processamento por filas.

## Pré-requisitos

A estimativa preliminar é de 12 GB de RAM mínima e 16 GB recomendada, com suporte amd64 e arm64. Antes da homologação real, é preciso medir volume, simultaneidade, retenção, banco, filas, endpoints, responsáveis e impacto de falhas.

## Ordem segura

1. Documentar o processo, o dono e o critério de sucesso no BookStack.
2. Preparar automações leves no Activepieces com dados de laboratório.
3. Preparar workflows avançados no n8n com filas, retries e idempotência.
4. Ativar um único gatilho controlado e observar o resultado antes da expansão.

## Validação

Cada automação deve apontar para uma especificação revisável. Uma falha transitória simulada não pode duplicar efeitos, e a matriz de responsabilidades deve comprovar que apenas um motor executa a decisão principal.

## Riscos e limites

Dois motores atuando sobre o mesmo evento podem duplicar ações. Retentativas sem idempotência podem repetir efeitos externos. O guia não fornece credenciais, carga real nem garantia de compatibilidade das integrações.

## Rollback

Suspender gatilhos e filas do processo de laboratório, restaurar os exports sanitizados e reativar somente depois de confirmar manualmente a versão e o responsável corretos.
