---
{"schemaVersion":1,"documentId":"blueprint-002-ia-whatsapp-sdr-crm-knowledge","documentVersion":"1.0.0","contentSHA256":"b73e0cd017957a293ef6428d1f59361ff55deaab810c094c5758c4c8d2be1274","documentType":"blueprint","blueprintId":"blueprint-002-ia-whatsapp-sdr-crm","fictitious":false,"deployable":true,"title":"Blueprint 002 \u2014 Agente IA WhatsApp SDR 24/7 + Follow-up + CRM","setupVersion": "7.48.3","architectures":["amd64","arm64"],"category":"architecture","status":"homologated","updatedAt":"2026-09-03","sourceType":"maintainer-authored","risk":"medium","language":"pt-BR","tags":["blueprint","whatsapp","ia","sdr","crm","krayincrm","chatwoot","n8n","follow-up"],"sources":[{"sourceId":"blueprint-002-manifest","title":"Manifesto can\u00f4nico do Blueprint 002","sourceType":"setup-mno","location":"setupmno-knowledge/blueprints/blueprint-002-ia-whatsapp-sdr-crm/blueprint.json","license":"maintainer-owned","verifiedAt":"2026-09-03"}],"homologation":{"verifiedAt":"2026-09-03","verifiedPorts":[],"verifiedImages":[]}}
---
# Blueprint 002 — Agente IA WhatsApp SDR 24/7 + Follow-up + CRM

## Estado de homologação

Este Blueprint possui homologação oficial e de produção no Setup MNO, validado ponta a ponta com 12 etapas, relatórios de teste E2E, revisão de segurança para proteção anti-ban e procedimento de rollback testado.

## Objetivo

Fornecer um ecossistema completo e autônomo para vendas e atendimento no WhatsApp com acolhimento 24/7 de novos leads sem tempo de espera, transcrição e compreensão de áudios via Whisper, qualificação consultiva com agente SDR treinado, cadência de follow-up anti-vácuo para reengajar contatos frios, registro e avanço automático de etapas no funil do Krayin CRM e transbordo transparente para atendentes humanos no Chatwoot com resumo da conversa.

## Topologia

A Evolution API conecta o WhatsApp empresarial e envia eventos para o n8n. O n8n processa mensagens de texto e áudio através do LangChain e modelos LLM. O Krayin CRM recebe os dados estruturados de contatos e negócios. O Chatwoot gerencia a caixa de entrada compartilhada para os vendedores humanos assumirem o atendimento quando necessário.

## Componentes

- CHATWOOTORIG (DESBLOQUEADO) + EVOLUTIONN 2.0 + RABBITMQ + MINIO*: atendimento multicanal, mensageria e armazenamento compartilhado.
- KRAYIN CRM: gestão de relacionamento, pipelines de vendas e histórico de clientes.
- N8N V2 - FILA (QUEUE): orquestração do agente de IA, cadência de follow-up e integração entre ferramentas.
- TYPEBOT + MINIO*: formulários e triagens conversacionais complementares.
- MAUTIC 7 WHATSAPP MKT: campanhas ativas e nutrição de leads da base.

## Pré-requisitos

A estimativa preliminar é de 8 GB de RAM mínima e 16 GB recomendada, em amd64 ou arm64. É necessário validar subdomínios no Cloudflare Tunnel, chaves de API dos provedores LLM (OpenAI, Groq ou Ollama) e credenciais protegidas antes de colocar em produção.

## Ordem segura

1. Preparar e validar o combo Chatwoot, Evolution API, RabbitMQ e MinIO ou confirmar stack preexistente.
2. Provisionar o Krayin CRM definindo credenciais administrativas e funil de vendas.
3. Conectar a instância WhatsApp na Evolution API e escanear o QR Code.
4. Conectar o n8n em modo fila e cadastrar credenciais de IA e mensageria.
5. Importar e ativar os 4 workflows na sequência: Receptor SDR, Follow-up Anti-Vácuo, Sincronizador CRM e Handoff Chatwoot.
6. Realizar teste ponta a ponta com áudio, texto e validação de transbordo humano.

## Validação

O cenário de validação deve rastrear uma mensagem de áudio e texto recebida pelo WhatsApp, verificar a transcrição pelo Whisper e a resposta empática da IA em menos de 8 segundos, certificar o disparo do lembrete de follow-up em caso de inatividade e comprovar o cadastro da oportunidade no Krayin CRM juntamente com o transbordo para a caixa de entrada do Chatwoot.

## Riscos e limites

Respostas de IA exigem delimitador de contexto para impedir alucinações ou prompt injection. O envio de mensagens deve respeitar o envio de presença digitando e intervalo humanizado para mitigar risco de banimento no WhatsApp. A cadência de follow-up deve limitar-se a 3 contatos antes de arquivamento.

## Rollback

Interromper os workflows de IA no n8n com toggle Active = false, pausar webhooks direcionados ao n8n na Evolution API, drenar eventuais mensagens retidas na fila do RabbitMQ e restaurar o atendimento manual no Chatwoot diretamente pela caixa de entrada principal.
