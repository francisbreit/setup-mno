# WhatsApp Marketing Completo

> BLUEPRINT HOMOLOGADO. Arquitetura validada de ponta a ponta para produção no Setup MNO.

## Objetivo

Fornecer uma arquitetura de alta performance e resiliência para marketing, disparo de campanhas com pausas inteligentes anti-bloqueio, chatbots no Typebot e atendimento humano centralizado no Chatwoot.

## Arquitetura

O Mautic organiza contatos, segmentações e campanhas. O n8n recebe os eventos e coordena o enfileiramento no RabbitMQ (Fila Quorum com persistência em disco) e aplica delays humanizados (5 a 15s). A Evolution API gerencia a conexão WhatsApp (Baileys), o Typebot executa os chatbots interativos e o Chatwoot recebe o atendimento humano (Handoff).

## Componentes

| Ordem | Setup | Papel |
|---|---|---|
| 1 | CHATWOOTORIG (DESBLOQUEADO) + EVOLUTIONN 2.0 + RABBITMQ + MINIO* | Comunicação, atendimento, mensageria Quorum e storage S3 |
| 2 | MAUTIC 7 WHATSAPP MKT | Contatos, segmentos, campanhas e canal WhatsApp/SMS |
| 3 | N8N V2 - FILA (QUEUE) | Orquestração de eventos, filas e controle de cadência |
| 4 | TYPEBOT + MINIO* | Fluxos conversacionais e qualificação interativa |

## Pré-requisitos

- Ambiente Setup MNO saudável em arquitetura x86_64 (amd64) ou ARM64.
- Mínimo de 8 GB de RAM (12 a 16 GB recomendado para produção).
- Subdomínios apontados no Cloudflare / DNS para os 5 serviços.

## Roteiro de Instalação e Configuração

O roteiro oficial compreende 15 passos integrados:
1. Instalação do Combo de Comunicação (Chatwoot, Evolution, RabbitMQ, MinIO);
2. Instalação do Mautic 7 WhatsApp Mkt;
3. Instalação do n8n v2 em Modo Fila (Queue);
4. Instalação do Typebot + MinIO;
5. Primeiro acesso e criação de conta no Chatwoot;
6. Obtenção do Token de Acesso de Perfil no Chatwoot;
7. Criação do Platform App 'N8N' no Superadmin do Chatwoot;
8. Configuração da Evolution API e conexão do WhatsApp via QR Code;
9. Criação da Fila Quorum 'Atendimento' no RabbitMQ;
10. Configurações de fuso horário e parâmetros no Mautic 7;
11. Configuração do n8n, importação dos workflows e credenciais RabbitMQ;
12. Integração da Evolution API com o Typebot;
13. Configuração do Plugin Twilio no Mautic (token 207811) e teste de mensagem simples;
14. Importação do chatbot 'aniversario' no Typebot Builder;
15. Disparo de campanha interativa com chatbot e transbordo para o Chatwoot.

## Validação e Checklist

- **Texto Simples:** Envio com intervalo seguro via RabbitMQ -> Evolution API.
- **Chatbot Interativo:** Resposta automática do Typebot via WhatsApp.
- **Handoff:** Transbordo imediato para a caixa de entrada do Chatwoot quando o cliente solicita atendente.

## Rollback

1. Desativar os 2 workflows no n8n (toggle Active = false);
2. Pausar campanhas e plugin Twilio no Mautic;
3. Drenar mensagens na fila Quorum do RabbitMQ;
4. Desconectar a instância Baileys se necessário.
