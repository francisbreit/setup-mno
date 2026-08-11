---
{
  "schemaVersion": 1,
  "documentId": "setup-waha-api-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "60a87be27778f4a70636619a94341b579ad9904cc44f4b209620374bfbf76b0f",
  "documentType": "setup",
  "title": "WAHA API no Setup MNO",
  "setupId": "waha-api",
  "setupVersion": "7.12.2",
  "architectures": [
    "amd64",
    "arm64"
  ],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": [
    "waha",
    "whatsapp",
    "api",
    "mensageria"
  ],
  "sources": [
    {
      "sourceId": "waha-api-installer",
      "title": "Instalador WAHA API",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/waha.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "waha-install",
      "title": "Instalação oficial do WAHA",
      "sourceType": "official-documentation",
      "location": "https://waha.devlike.pro/docs/how-to/install/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "waha-config",
      "title": "Configuração oficial do WAHA",
      "sourceType": "official-documentation",
      "location": "https://waha.devlike.pro/docs/how-to/config/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    }
  ],
  "homologation": {
    "verifiedAt": null,
    "verifiedPorts": [],
    "verifiedImages": []
  }
}
---
# WAHA API no Setup MNO

## Quando usar

Use para integração WhatsApp HTTP quando termos da plataforma, consentimento e responsabilidade operacional estiverem aceitos. Não prometa estabilidade equivalente a uma API oficial da Meta.

## Arquitetura no Setup MNO

O instalador usa a variante GOWS do WAHA e um Redis dedicado conforme o script. Sessões, mídia e chaves de API são dados sensíveis e persistentes.

## Pré-requisitos

O catálogo declara cerca de 2 GB de RAM; sessões simultâneas, engine e mídias podem elevar o consumo.

Exige domínio HTTPS, autenticação de dashboard e API, storage de sessões, Redis e política de mensagens. Confirme arquitetura e variante de imagem efetiva.

## Fluxo seguro

Troque credenciais padrão, use API key forte, limite webhooks e execute somente mensagens consentidas. QR, sessão, mídia e tokens não devem ser enviados ao Assistente.

## Primeiro acesso e integrações

Conecte número de teste, envie mensagem autorizada e valide webhook assinado ou autenticado. Não use conta comercial real antes de testar reconexão e limites.

## Backup e atualização

Preserve sessões e configuração com cópia cifrada, sem expor chaves. Atualize em janela controlada e mantenha processo de novo pareamento como rollback.

## Validação

Confirme HTTPS, autenticação, Redis dedicado, sessão, envio, recebimento, webhook e reconexão. Teste bloqueio de chamada sem API key.

## Riscos e limites

Automação não oficial pode sofrer bloqueios e violar termos ou consentimento. Uma chave exposta permite enviar e ler mensagens.

## Diagnóstico

Separe engine, sessão, QR, API, Redis, webhook e rede da plataforma. Use conta e mensagens de teste.
