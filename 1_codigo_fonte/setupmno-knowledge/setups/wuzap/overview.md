---
{
  "schemaVersion": 1,
  "documentId": "setup-wuzap-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "e79e9080b6b51ffc59592a83c3edae9b90c522633252d18fbbe37d8498274e39",
  "documentType": "setup",
  "title": "WuzAPI no Setup MNO",
  "setupId": "wuzap",
  "setupVersion": "7.7.27",
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
    "wuzapi",
    "wuzap",
    "whatsapp",
    "api"
  ],
  "sources": [
    {
      "sourceId": "wuzap-installer",
      "title": "Instalador WuzAPI",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/wuzap.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "wuzapi-official",
      "title": "Repositório oficial do WuzAPI",
      "sourceType": "official-documentation",
      "location": "https://github.com/asternic/wuzapi",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "wuzapi-image",
      "title": "Imagem Docker do WuzAPI",
      "sourceType": "official-documentation",
      "location": "https://hub.docker.com/r/asternic/wuzapi",
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
# WuzAPI no Setup MNO

## Quando usar

Use para uma API REST leve de WhatsApp Multi-Device quando termos, consentimento e responsabilidade forem aceitos. Não confunda o nome de catálogo WUZAP com um produto oficial da Meta.

## Arquitetura no Setup MNO

O instalador usa a imagem WuzAPI e conecta banco e persistência conforme o script. O serviço se comunica diretamente com a infraestrutura do WhatsApp e mantém sessões e mídia.

## Pré-requisitos

O catálogo declara cerca de 1 GB de RAM; múltiplos dispositivos, mídia e banco aumentam consumo e storage.

Exige domínio HTTPS, token administrativo forte, Postgres, storage e política de mensagens e arquivos. Defina usuários, dispositivos e webhooks autorizados.

## Fluxo seguro

Proteja toda a API, limite webhooks e use conta de teste. Tokens, QR, sessões, números, mídias e mensagens não devem ser enviados ao Assistente.

## Primeiro acesso e integrações

Cadastre usuário de teste, pareie dispositivo controlado e valide envio, recebimento e webhook. Confirme autorização antes de automatizar mensagens.

## Backup e atualização

Preserve banco, arquivos e estado de sessão com cópia cifrada. Registre versão e mantenha novo pareamento como contingência de restauração.

## Validação

Confirme HTTPS, token obrigatório, isolamento por usuário, persistência, webhook e reconexão. Teste bloqueio de chamada sem autenticação.

## Riscos e limites

Automação não oficial pode sofrer bloqueio e envolver dados pessoais. Token amplo ou webhook exposto permite acesso indevido a mensagens.

## Diagnóstico

Separe API, token, usuário, sessão, Postgres, arquivos, webhook e rede externa. Use conta e payload sintéticos.
