---
{
  "schemaVersion": 1,
  "documentId": "setup-home-assistant-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "bcac7c9ead11dd2654b4a5ebfacaf2e5a4a75e4017e047a0274fa4cd0c275ed6",
  "documentType": "setup",
  "title": "Home Assistant no Setup MNO",
  "setupId": "home-assistant",
  "setupVersion": "7.42.0",
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
    "home-assistant",
    "automacao-residencial",
    "iot",
    "container"
  ],
  "sources": [
    {
      "sourceId": "home-assistant-installer",
      "title": "Instalador Home Assistant",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/homeassistant.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "ha-container",
      "title": "Instalação Home Assistant Container",
      "sourceType": "official-documentation",
      "location": "https://www.home-assistant.io/installation/linux#install-home-assistant-container",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "ha-backup",
      "title": "Arquitetura de backup Home Assistant",
      "sourceType": "official-documentation",
      "location": "https://developers.home-assistant.io/docs/core/platform/backup/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "ha-supervisor",
      "title": "Arquitetura Supervisor Home Assistant",
      "sourceType": "official-documentation",
      "location": "https://developers.home-assistant.io/docs/supervisor/",
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
# Home Assistant no Setup MNO

## Quando usar

Use para automação residencial e integração de dispositivos quando o operador entende redes IoT e segurança física. A instalação Container entrega Home Assistant Core, não Supervisor, add-ons ou a experiência completa do Home Assistant OS.

## Arquitetura no Setup MNO

O instalador usa `Home Assistant na tag stable`, volume de configuração e rota em Swarm. O catálogo anuncia 2 GB, enquanto o script limita cerca de 1 GB; descoberta local, USB, Bluetooth e multicast podem não funcionar como em host network.

## Pré-requisitos

Exige domínio ou acesso local seguro, volume, rede IoT planejada, backups e inventário de dispositivos. Hardware pass-through e descoberta precisam de validação específica em VPS, WSL2 e Swarm.

## Fluxo seguro

Isole IoT, use MFA, não publique sem TLS e restrinja tokens de integrações. Não entregue socket Docker nem dispositivos amplos. Trate automações físicas como alto impacto.

## Primeiro acesso e integrações

Com dispositivo ou entidade de teste, valide onboarding, fuso, integração, automação e notificação. Documente recursos ausentes por ser Container e não Supervisor.

## Backup e atualização

Use backup suportado pelo Core e cópia do diretório de configuração, incluindo segredos protegidos. Antes de atualizar `stable`, registre versão e teste restore; preserve automações críticas em estado seguro.

## Validação

Confirme login/MFA, persistência, automação fictícia, WebSocket, histórico e backup. Teste explicitamente descoberta e hardware necessário no ambiente alvo.

## Riscos e limites

Automação pode afetar acesso, energia e segurança física. Diferenças de Container/Swarm, limite de RAM divergente e tag `stable` podem causar expectativa falsa ou indisponibilidade.

## Diagnóstico

Separe Core, integração, rede/multicast, hardware, banco, proxy e automação. Nunca envie tokens, localização, câmeras ou rotina doméstica ao Assistente.
