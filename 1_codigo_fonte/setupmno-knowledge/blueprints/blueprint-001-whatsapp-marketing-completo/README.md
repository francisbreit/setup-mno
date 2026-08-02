# WhatsApp Marketing Completo

> GUIA BETA. Pode ser seguido manualmente, mas ainda não foi homologado de ponta a ponta. Valide cada etapa antes de avançar.

## Objetivo

Orientar a montagem de uma arquitetura de marketing e atendimento por WhatsApp com campanhas, fila de mensagens, fluxo conversacional e atendimento humano.

## Arquitetura

O Mautic organiza contatos e campanhas. O n8n recebe os eventos e coordena o processamento. O RabbitMQ representa a fila de negócio, a Evolution API representa a conexão não oficial com WhatsApp, o Typebot representa os fluxos e o Chatwoot representa o atendimento humano.

## Componentes

| Ordem | Setup | Papel |
|---|---|---|
| 1 | CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ + MINIO* | Comunicação, atendimento, mensageria e objetos |
| 2 | MAUTIC 7 WHATSAPP MKT | Contatos, segmentos e campanhas |
| 3 | N8N V2 - FILA (QUEUE) | Orquestração e controle de processamento |
| 4 | TYPEBOT + MINIO* | Fluxos conversacionais |

## Pré-requisitos

- Ambiente Setup MNO saudável em uma das arquiteturas declaradas.
- Capacidade validada com margem operacional.
- Dados controlados para a primeira validação.
- Consentimento, opt-out e política vigente do provedor revisados pelo responsável.

## Ordem de instalação

Instale os quatro itens na ordem da tabela. Pare entre as etapas e confirme a saúde do item anterior. Crie as contas administrativas, conecte Chatwoot e Evolution, cadastre credenciais e webhooks no n8n, publique o fluxo Typebot e execute uma jornada completa antes de ativar campanhas. O Typebot deve reutilizar o MinIO existente com bucket e identidade exclusivos; o guia não distribui credenciais.

## Contrato de configuração

O nome lógico da instância, o nome da fila e os identificadores referenciados nos fluxos precisam seguir uma convenção documentada. Credenciais são criadas no ambiente de destino e nunca são distribuídas no ZIP.

## Validação

Execute testes independentes para texto simples, fluxo conversacional, fila, prevenção de duplicação e transferência para atendimento humano. Registre horário, resultado esperado e evidência sanitizada.

## Riscos e limites

A estimativa de memória é preliminar. APIs não oficiais podem sofrer bloqueios ou mudanças. Disparos exigem autorização do público, limites conservadores e revisão das políticas aplicáveis. Este material não comprova compatibilidade operacional.

## Rollback

Desative primeiro campanhas e workflows. Preserve apenas exports sanitizados e retorne à configuração anterior pelo fluxo autorizado do Setup MNO.

## Downloads, vídeos e PDFs

- O ZIP deste Blueprint está disponível no Control Center.
- Vídeo de visão geral: em preparação.
- PDF com checklist de integrações: em preparação.

## Homologação futura

Acrescente transcrições revisadas, versões confirmadas e evidências de homologação antes de conceder o selo de produção.
