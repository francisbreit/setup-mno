# Automação de Negócios

> GUIA BETA. Pode ser seguido manualmente, mas ainda não foi homologado de ponta a ponta. Valide cada etapa antes de avançar.

## Objetivo

Orientar como separar documentação, automações leves e workflows avançados sem criar execução automática pelo Copiloto.

## Arquitetura

O BookStack mantém o processo humano. O Activepieces representa integrações leves. O n8n Queue representa fluxos avançados, concorrência e retries controlados.

## Componentes

| Ordem | Setup | Responsabilidade |
|---|---|---|
| 1 | BOOKSTACK | Procedimentos e responsáveis |
| 2 | ACTIVEPIECES | Integrações leves |
| 3 | N8N V2 - FILA (QUEUE) | Processamento avançado |

## Pré-requisitos

- Responsável definido para cada processo.
- Dados controlados e endpoints de teste.
- Critérios de idempotência, retry e timeout documentados.

## Ordem de instalação

Registre os procedimentos primeiro. Instale o motor leve antes do motor de fila, crie as contas administrativas, cadastre credenciais de teste e documente explicitamente qual componente é responsável por cada processo. Importe workflows somente depois de revisar nós, retries e idempotência.

## Validação

Teste sucesso, falha transitória e repetição do mesmo evento. Nenhuma automação deve duplicar efeitos após retry.

## Riscos e limites

Dois motores podem criar duplicação de responsabilidade. A estimativa de recursos é editorial e não representa medição de produção.

## Rollback

Suspenda os gatilhos, preserve o evento original e restaure o último export revisado antes de reativar o processo.

## Downloads, vídeos e PDFs

- O ZIP deste Blueprint está disponível no Control Center.
- Vídeo sobre separação dos workflows: em preparação.

## Homologação futura

Exige matriz real de processos, responsáveis, volumes, integrações, testes de idempotência e evidências de restauração.
