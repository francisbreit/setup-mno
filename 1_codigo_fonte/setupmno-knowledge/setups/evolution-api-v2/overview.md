---
{
  "schemaVersion": 1,
  "documentId": "setup-evolution-api-v2-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "c243b3b8196d83baa18036366d0c6486cf39f5a1e703e9b3f9947d1697853e9e",
  "documentType": "setup",
  "title": "Evolution API v2 no Setup MNO",
  "setupId": "evolution-api-v2",
  "setupVersion": "7.48.18",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["evolution-api", "whatsapp", "mensageria", "redis", "postgresql"],
  "sources": [
    {"sourceId":"evolution-v2-installer","title":"Instalador Evolution API v2","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/evolution2api.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"evolution-v2-docker-docs","title":"Evolution API v2 com Docker","sourceType":"official-documentation","location":"https://docs.evolutionfoundation.com.br/evolution-api/install/docker","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"evolution-v2-redis-docs","title":"Redis na Evolution API v2","sourceType":"official-documentation","location":"https://docs.evolutionfoundation.com.br/evolution-api/requirements/redis","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# Evolution API v2 no Setup MNO

## Quando usar

Use para conectar sistemas autorizados a canais de WhatsApp, receber eventos e
integrar atendimento ou automação. Antes de escolher o provedor baseado em
WhatsApp Web, avalie estabilidade, consentimento, políticas da Meta e risco de
bloqueio. Para operação regulada ou em grande escala, considere a API oficial.

## Arquitetura no Setup MNO

O instalador cria uma aplicação Evolution, um Redis dedicado para cache e um
banco lógico no PostgreSQL base. A aplicação e o cache ficam em stacks
separadas e usam as redes internas do Setup; a API recebe uma rota pública pelo
Traefik ou pelo túnel Cloudflare.

## Pré-requisitos

Exige infraestrutura-base saudável, PostgreSQL, domínio exclusivo, RAM livre e
uma chave global forte. Defina previamente o canal, o controlador dos dados, a
política de retenção, o volume esperado de mensagens e o sistema consumidor dos
eventos. Não envie chaves ou conteúdo de conversas ao Assistente.

## Fluxo seguro

O Instalador Seguro coleta domínio, identificação da empresa, chave global e
modo Portainer ou Docker. Ele cria banco e cache antes da aplicação. Depois do
deploy, crie uma instância de teste, habilite apenas os eventos necessários e
conecte o número somente após revisar permissões e política de uso.

## Primeiro acesso e integrações

Valide a API com uma instância descartável e dados não sensíveis. n8n, Typebot,
Chatwoot, webhooks, RabbitMQ e storage compatível com S3 são integrações
possíveis, mas cada uma precisa de credenciais próprias, escopo mínimo,
timeouts, retentativas e prevenção de eventos em ciclo.

## Backup e atualização

O plano de recuperação deve cobrir o banco da Evolution, dados persistentes de
instância e a configuração do Redis quando ela for necessária para a retomada.
Antes de atualizar, registre a versão, leia as notas oficiais, preserve backup
restaurável e teste o pareamento e os webhooks em uma instância isolada.

## Validação

Confirme réplica saudável, acesso autenticado, criação e reconexão da instância,
envio e recebimento controlados, entrega do webhook e ausência de repetição. Um
teste de interface sozinho não comprova mensageria nem recuperação.

## Riscos e limites

Automação via canal não oficial pode perder sessão ou sofrer restrições do
provedor. Webhooks sem autenticação, chave global reutilizada e logs contendo
mensagens ampliam o impacto de incidente. A entrada é instalável, mas não é
homologação automática de cada provedor ou integração externa.

## Diagnóstico

Separe falha de rota, autenticação, banco, Redis, sessão e destino do webhook.
Use estado agregado, códigos sanitizados e horário do evento; nunca cole QR
Code, chave, telefone, payload de cliente ou credencial no chat.
