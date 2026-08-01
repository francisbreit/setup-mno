---
{
  "schemaVersion": 1,
  "documentId": "infra-cloudflare-architecture",
  "documentVersion": "1.0.2",
  "contentSHA256": "9931d16c63011ecfba4803261cf7e2445844518d84af72b437f2009b22ab99f2",
  "documentType": "infrastructure",
  "title": "Cloudflare no acesso tradicional e por túnel",
  "topicId": "cloudflare",
  "setupVersion": "7.2.5",
  "architectures": ["amd64", "arm64"],
  "category": "networking",
  "status": "reviewed",
  "updatedAt": "2026-07-30",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["cloudflare", "dns", "tunnel"],
  "sources": [
    {
      "sourceId": "cloudflare-generator-script",
      "title": "Gerador de configuração Cloudflare",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/geracloudflare.sh",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    },
    {
      "sourceId": "cloudflare-base-script",
      "title": "Fluxos tradicional e Cloudflare Tunnel",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/dockerswarm.sh",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    }
  ],
  "homologation": {
    "verifiedAt": null,
    "verifiedPorts": [],
    "verifiedImages": []
  }
}
---
# Cloudflare no acesso tradicional e por túnel

## Papel no Setup MNO

O Setup MNO suporta publicação tradicional e publicação por túnel. O fluxo
selecionado determina como registros e ingressos são preparados, mantendo o
serviço de aplicação dentro das redes controladas pelo Swarm.

## Princípios

Tokens e identificadores de conta nunca entram na base de conhecimento nem no
contexto enviado à LLM. O Assistente pode explicar diferenças entre os modos,
mas não cria registros, não altera túnel e não solicita que o usuário cole
credenciais no chat.

## Validação

O diagnóstico diferencia resolução ausente, ingresso de túnel incompatível,
serviço interno indisponível e rota da aplicação incorreta. A resposta deve
trabalhar apenas com estados sanitizados e orientar a coleta pelo Instalador
Seguro quando faltarem evidências.

## Riscos e limites

Uma alteração errada pode interromper diversos domínios ou expor um serviço
interno. Nenhuma correção de DNS ou túnel é executada pelo Assistente. Mudanças
devem ser confirmadas por um operador e possuir rollback da configuração
anterior.
