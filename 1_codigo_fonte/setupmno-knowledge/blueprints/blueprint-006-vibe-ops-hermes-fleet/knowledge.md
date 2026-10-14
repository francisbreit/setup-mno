---
{"schemaVersion":1,"documentId":"blueprint-006-vibe-ops-knowledge","documentVersion":"1.0.0","contentSHA256":"7b32672b3155ef10e2364673792d525fc3bc6d9e59148a0d24872d353775f3c6","documentType":"blueprint","blueprintId":"blueprint-006-vibe-ops-hermes-fleet","fictitious":false,"deployable":true,"title":"Blueprint 006 — Vibe Ops & SRE Autônomo com Hermes Agent + n8n","setupVersion":"7.49.0","architectures":["amd64","arm64"],"category":"architecture","status":"homologated","updatedAt":"2026-09-06","sourceType":"maintainer-authored","risk":"medium","language":"pt-BR","tags":["blueprint","vibe-ops","hermes-agent","n8n","sre","devops","ia","swarm"],"sources":[{"sourceId":"blueprint-006-manifest","title":"Manifesto canônico do Blueprint 006","sourceType":"setup-mno","location":"setupmno-knowledge/blueprints/blueprint-006-vibe-ops-hermes-fleet/blueprint.json","license":"maintainer-owned","verifiedAt":"2026-09-06"}],"homologation":{"verifiedAt":"2026-09-06","verifiedPorts":[],"verifiedImages":[]}}
---
# Blueprint 006 — Vibe Ops & SRE Autônomo com Hermes Agent + n8n

## Estado de homologação

Este Blueprint possui homologação oficial e de produção no Setup MNO, validado ponta a ponta com 5 etapas assistidas, testes em WSL2 e VPS, revisão de segurança com política fail-closed e procedimento de rollback verificado.

## Objetivo

Fornecer uma arquitetura homologada e resiliente para operação de servidores Docker Swarm e orquestração de infraestrutura através de linguagem natural via WhatsApp, Telegram ou painel n8n, integrando o Hermes Agent ao MNO Fleet Hub e Sentinel com estrita política de segurança fail-closed e zero portas abertas.

## Topologia

A Torre Master centraliza o Setup MNO Control Center, o inventário da frota e o daemon MNO Sentinel em goroutine Go (0 MB de overhead adicional). Os nós operários (workers) rodam as cargas de trabalho em Docker Swarm na rede overlay interna. O Hermes Agent executa chamadas de ferramentas padronizadas (Tool Calling) contra a Fleet API (/api/fleet/tools/schema.json), enquanto o n8n v2 em modo fila processa webhooks e mensagens com enfileiramento transacional no RabbitMQ. Toda a exposição externa ocorre via Cloudflare Tunnel criptografado com zero portas abertas.

## Componentes

- HERMES AGENT: comandante SRE autônomo com capacidades de raciocínio, tool calling e diagnóstico de servidores.
- N8N V2 - FILA (QUEUE): orquestrador transacional de fluxos para webhooks de telemetria, filas RabbitMQ e integração com Fleet Hub.

## Pré-requisitos

Servidor VPS ou ambiente local WSL2 Ubuntu 24.04 com Docker Swarm ativo, no mínimo 4 GB de memória RAM (recomendado 8 GB para concorrência com workers), rede overlay interna provisionada, PostgreSQL central e RabbitMQ para mensageria assíncrona do n8n. Subdomínios protegidos configurados no Cloudflare Tunnel.

## Ordem segura

1. Provisionar o Hermes Agent e configurar as credenciais do provedor LLM (OpenAI, Groq ou endpoint local).
2. Provisionar o n8n v2 em modo fila com suporte a PostgreSQL e RabbitMQ.
3. Importar a especificação de ferramentas da Fleet API (/api/fleet/tools/schema.json) no Hermes Agent.
4. Importar e ativar os fluxos de auto-remediação e webhook do Sentinel no painel do n8n.
5. Executar consulta de diagnóstico do cluster em linguagem natural e verificar execução controlada fail-closed.

## Validação

O cenário de validação compreende a verificação da convergência dos containers (1/1 réplicas ativas), teste de invocação das 6 ferramentas de Tool Calling com tempo de resposta inferior a 120ms, recepção e enriquecimento de alertas do Sentinel via webhook no n8n e controle de concorrência com idempotência comprovada em logs de auditoria.

## Riscos e limites

Comandos acionados por agentes de IA nunca devem executar mutações destrutivas sem confirmação humana explícita. O agente opera estritamente em modo consultivo e diagnóstico. É proibido expor portas administrativas ou tokens de API em redes públicas sem autenticação forte.

## Rollback

Desativar os workflows no n8n com toggle Active = false, pausar ou escalar o serviço do Hermes Agent para 0 réplicas com docker service scale combo_vibe_ops_hermes=0, purgar mensagens acumuladas nas filas do RabbitMQ e preservar a integridade da baseline do cluster Swarm e dos dados persistentes.
