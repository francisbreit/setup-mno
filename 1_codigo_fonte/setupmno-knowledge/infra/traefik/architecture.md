---
{
  "schemaVersion": 1,
  "documentId": "infra-traefik-architecture",
  "documentVersion": "1.0.2",
  "contentSHA256": "cd2843917f40e4fe8b1621d0db0a5b13f07f93ff2d6c65b0ede9de7f0914ed30",
  "documentType": "infrastructure",
  "title": "Traefik e publicação segura dos setups",
  "topicId": "traefik",
  "setupVersion": "7.2.15",
  "architectures": ["amd64", "arm64"],
  "category": "networking",
  "status": "reviewed",
  "updatedAt": "2026-07-30",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["traefik", "roteamento", "tls"],
  "sources": [
    {
      "sourceId": "traefik-setup-script",
      "title": "Definição do Traefik na infraestrutura base",
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
# Traefik e publicação segura dos setups

## Papel no Setup MNO

O Traefik recebe as rotas declaradas pelas stacks e publica somente os
serviços autorizados. Ele centraliza redirecionamento seguro, certificados e
integração com as redes externas do Swarm.

## Princípios

O painel web nunca recebe o socket Docker. Labels pertencem às stacks que
precisam de rota, enquanto componentes internos permanecem sem rota pública.
Alterações de roteamento devem conservar isolamento, autenticação e
compatibilidade com o modo tradicional e com Cloudflare Tunnel.

## Validação

Uma análise segura verifica se o serviço de entrada está saudável, se a stack
de destino participa da rede correta e se existe uma rota coerente. Falhas de
certificado, resolução e serviço indisponível devem ser diferenciadas antes de
qualquer recomendação.

## Riscos e limites

Labels incorretas podem publicar componentes internos ou causar colisão entre
rotas. O Assistente não deve inventar domínios, nomes de serviço ou alterações
de middleware; deve indicar o componente provável e encaminhar a correção ao
fluxo humano apropriado.
