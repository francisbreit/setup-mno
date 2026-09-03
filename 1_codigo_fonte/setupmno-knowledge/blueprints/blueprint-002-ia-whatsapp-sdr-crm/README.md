# Agente IA WhatsApp SDR 24/7 + Follow-up + CRM

> BLUEPRINT HOMOLOGADO. Arquitetura validada de ponta a ponta para produção no Setup MNO.

## Objetivo

Fornecer uma arquitetura de alta conversão para atendimento autônomo 24/7 com acolhimento imediato de leads no WhatsApp, transcrição e resposta a mensagens de voz, qualificação inteligente com IA SDR, cadência de follow-up anti-vácuo, sincronização no Krayin CRM e transbordo humano no Chatwoot.

## Arquitetura

O lead entra em contato pelo WhatsApp conectado via Evolution API v2. O n8n intercepta o webhook, transcreve áudios se necessário e aciona a persona do Agente SDR de IA. O lead é qualificado em tempo real. Se parar de responder, o motor de follow-up dispara lembretes educados (2h, 24h e 72h). Ao atingir qualificação ou solicitar atendimento, a oportunidade é cadastrada no Krayin CRM e o atendimento é transferido para o Chatwoot com uma nota privada contendo o resumo da negociação.

## Componentes

| Ordem | Setup | Papel |
|---|---|---|
| 1 | CHATWOOTORIG (DESBLOQUEADO) + EVOLUTIONN 2.0 + RABBITMQ + MINIO* | Atendimento multicanal, mensageria Quorum e storage S3 |
| 2 | KRAYIN CRM | Funil de vendas, estágios de qualificação e base de contatos |
| 3 | N8N V2 - FILA (QUEUE) | Orquestrador de IA, transcrição Whisper e motor de follow-up |
| 4 | TYPEBOT + MINIO* | Triagens interativas rápidas reaproveitando o storage MinIO |
| 5 | MAUTIC 7 WHATSAPP MKT | Gestão de contatos da base e campanhas ativas complementares |

## Pré-requisitos

- Setup MNO ativo em arquitetura x86_64 (amd64) ou ARM64 (Oracle Cloud / VPS).
- Mínimo de 8 GB de RAM (12 a 16 GB recomendado para o ecossistema completo).
- Subdomínios apontados via Cloudflare Tunnel para os serviços da stack.
- Chave de API de LLM (OpenAI GPT-4o-mini, Groq Llama-3 ou Ollama local).

## Roteiro de Implantação e Configuração

O roteiro oficial compreende 12 passos integrados:
1. Execução do instalador inteligente do Blueprint ou confirmação de uso dos serviços existentes;
2. Instalação e provisionamento do Krayin CRM;
3. Instalação ou conexão ao n8n em modo fila (Queue Mode);
4. Conexão da instância WhatsApp na Evolution API via QR Code;
5. Criação da caixa de entrada de API no Chatwoot para transbordo com notas privadas;
6. Configuração dos estágios do pipeline comercial no Krayin CRM;
7. Cadastro de credenciais de IA e RabbitMQ no n8n;
8. Importação do Workflow 01: Receptor, Áudio e Agente SDR IA;
9. Importação do Workflow 02: Motor de Follow-up Anti-Vácuo;
10. Importação do Workflow 03: Sincronizador REST com o Krayin CRM;
11. Importação do Workflow 04: Handoff Humanizado para o Chatwoot;
12. Teste E2E completo com áudio, texto, follow-up e transbordo.

## Validação e Checklist

- **Atendimento de Texto e Áudio:** Resposta em menos de 8 segundos com transcrição e persona SDR.
- **Follow-up Anti-Vácuo:** Disparo programado de lembrete cordial após 2 horas de inatividade.
- **Handoff e CRM:** Registro da oportunidade no Krayin CRM e transferência da conversa para operador no Chatwoot.

## Rollback

1. Desativar os workflows no n8n (toggle Active = false);
2. Pausar o webhook da Evolution API apontando para o n8n;
3. Drenar mensagens pendentes no RabbitMQ;
4. Retomar o atendimento humano manual pelo Chatwoot.
