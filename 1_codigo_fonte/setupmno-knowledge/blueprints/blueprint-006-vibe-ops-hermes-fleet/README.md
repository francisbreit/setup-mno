# Vibe Ops & SRE Autônomo com Hermes Agent + n8n

> BLUEPRINT HOMOLOGADO. Arquitetura validada de ponta a ponta para produção no Setup MNO.

## Objetivo

Fornecer uma arquitetura homologada e resiliente para operação de servidores Docker Swarm e orquestração de infraestrutura através de linguagem natural via WhatsApp, Telegram ou painel n8n, integrando o Hermes Agent ao MNO Fleet Hub e Sentinel com estrita política de segurança fail-closed e zero portas abertas.

## Arquitetura

O ecossistema opera de maneira distribuída e atômica:
1. **Torre Master:** Centraliza o Setup MNO Control Center, o inventário seguro do Fleet Hub e o daemon MNO Sentinel;
2. **Nós Workers:** Executam as aplicações conteinerizadas em Docker Swarm na rede overlay interna isolada;
3. **MNO Sentinel:** Monitora continuamente métricas de CPU, RAM e disco com goroutines de baixíssimo consumo em Go (0 MB de overhead adicional);
4. **Hermes Agent:** Agente autônomo com capacidade de Tool Calling que consome a Fleet Tools API para diagnósticos e proposição de ações;
5. **n8n v2 em Modo Fila (Queue):** Intermedia webhooks, controla filas RabbitMQ e executa workflows transacionais com trava de concorrência.

## Componentes

| Ordem | Setup | Papel |
|---|---|---|
| 1 | HERMES AGENT | Comandante SRE autônomo com capacidades de raciocínio, tool calling e orquestração de infraestrutura |
| 2 | N8N V2 - FILA (QUEUE) | Orquestrador transacional de fluxos para webhooks de telemetria, filas RabbitMQ e integração com Fleet Hub |

## Pré-requisitos

- Servidor VPS ou ambiente de desenvolvimento local WSL2 Ubuntu com Docker Swarm ativo.
- Mínimo de 4 GB de memória RAM dedicada (recomendado 8 GB para execução estável com n8n e workers).
- Conexão criptografada via Cloudflare Tunnel para comunicação entre nós sem exposição de portas públicas.
- Chave de API de provedor de linguagem (OpenAI, Groq ou endpoint local vLLM/Ollama).

## Roteiro de Implantação e Configuração

O roteiro oficial compreende 5 etapas assistidas:
1. Provisionamento do Hermes Agent e configuração das chaves de API do provedor LLM;
2. Provisionamento do n8n v2 em modo fila com suporte a PostgreSQL e RabbitMQ;
3. Vinculação da especificação canônica de ferramentas (/api/fleet/tools/schema.json);
4. Importação e ativação dos workflows oficiais de Vibe Ops e triagem do Sentinel no n8n;
5. Teste operacional com validação de diagnósticos em linguagem natural e simulação de incidentes.

## Validação e Checklist

- **Convergência de Serviços:** Serviços em estado running (1/1) na rede interna overlay.
- **Tool Calling:** Sucesso na invocação estruturada das ferramentas da Fleet API com resposta em menos de 120ms.
- **Triagem do Sentinel:** Recepção imediata de webhooks de alerta com enriquecimento de diagnóstico e despacho seguro.

## Rollback

1. Desativar os fluxos de auto-remediação no painel do n8n (toggle Active = false);
2. Escalar o serviço do Hermes Agent para 0 réplicas;
3. Drenar e purgar filas de mensagens pendentes no RabbitMQ;
4. Preservar o estado do cluster Swarm e os volumes persistentes.
