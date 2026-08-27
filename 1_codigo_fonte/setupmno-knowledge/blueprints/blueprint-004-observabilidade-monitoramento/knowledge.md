---
{"schemaVersion":1,"documentId":"blueprint-004-observabilidade-knowledge","documentVersion":"0.2.0","contentSHA256":"780b13926c02e36d0e263d0406f63062449c2e0247b6958809b00b9d7d64764f","documentType":"blueprint","blueprintId":"blueprint-004-observabilidade-monitoramento","fictitious":false,"deployable":false,"title":"Blueprint 004 — Observabilidade e Monitoramento","setupVersion": "7.36.0","architectures":["amd64","arm64"],"category":"architecture","status":"reviewed","updatedAt":"2026-08-02","sourceType":"maintainer-authored","risk":"medium","language":"pt-BR","tags":["blueprint","observabilidade","monitoramento","beszel","grafana","prometheus","uptimekuma"],"sources":[{"sourceId":"blueprint-004-manifest","title":"Manifesto canônico do Blueprint 004","sourceType":"setup-mno","location":"setupmno-knowledge/blueprints/blueprint-004-observabilidade-monitoramento/blueprint.json","license":"maintainer-owned","verifiedAt":"2026-08-02"}],"homologation":{"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}}
---
# Blueprint 004 — Observabilidade e Monitoramento

## Estado de homologação

Este é um guia Beta revisado para orientar a montagem manual. Ele não executa deploy e ainda exige validar retenção, capacidade e canais de alerta no ambiente de destino.

## Objetivo

Montar uma arquitetura em camadas para visibilidade leve do host, séries temporais e dashboards detalhados, além de verificação externa de disponibilidade.

## Topologia

O Beszel fornece uma visão leve de recursos e saúde. Prometheus e Grafana representam coleta, retenção, consultas e dashboards detalhados. Uptime Kuma representa verificações externas e alertas independentes da camada de métricas.

## Componentes

- BESZEL: visibilidade leve dos hosts autorizados.
- GRAFANA/PROMETHEUS MONITOR: métricas, séries temporais e dashboards.
- UPTIMEKUMA: disponibilidade externa e alertas de laboratório.

## Pré-requisitos

A estimativa preliminar é de 4 GB de RAM mínima e 8 GB recomendada, em amd64 ou arm64. Quantidade de hosts, frequência de coleta, cardinalidade, retenção, canais de alerta e armazenamento precisam ser medidos antes da homologação.

## Ordem segura

1. Preparar o Beszel e registrar uma baseline com host descartável autorizado.
2. Definir métricas, retenção e fontes antes de preparar Prometheus e Grafana.
3. Adicionar no Uptime Kuma somente alvos de laboratório.
4. Simular uma indisponibilidade e revisar emissão e encerramento do alerta.

## Validação

Uma métrica de laboratório deve receber amostras no intervalo documentado. Um alvo descartável deve gerar apenas o alerta esperado e encerrar depois da recuperação. A retenção deve possuir responsável, limite e estimativa de armazenamento.

## Riscos e limites

Coleta excessiva pode consumir disco e memória. Alta cardinalidade pode degradar consultas. Alertas mal configurados podem gerar ruído ou deixar falhas sem notificação. O guia ainda não representa uma política operacional homologada.

## Rollback

Suspender os alertas do laboratório, remover somente os alvos temporários e restaurar dashboards, fontes e retenção da baseline anterior.
