---
{
  "schemaVersion": 1,
  "documentId": "setup-pihole-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "9f44cca1a3acfb18665037350f0bc2260975d9d8941610bc3ad64e7785fe1269",
  "documentType": "setup",
  "title": "Pi-hole no Setup MNO",
  "setupId": "pihole",
  "setupVersion": "7.7.36",
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
    "pihole",
    "dns",
    "rede",
    "bloqueio"
  ],
  "sources": [
    {
      "sourceId": "pihole-installer",
      "title": "Instalador Pi-hole",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/pihole.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "pihole-docker",
      "title": "Docker oficial Pi-hole",
      "sourceType": "official-documentation",
      "location": "https://docs.pi-hole.net/docker/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "pihole-config",
      "title": "Configuração Docker Pi-hole",
      "sourceType": "official-documentation",
      "location": "https://docs.pi-hole.net/docker/configuration/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "pihole-upgrade",
      "title": "Atualização Docker Pi-hole",
      "sourceType": "official-documentation",
      "location": "https://docs.pi-hole.net/docker/upgrading/",
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
# Pi-hole no Setup MNO

## Quando usar

Use como DNS filtrante para uma rede controlada. Uma falha pode interromper toda resolução; não altere DNS de clientes ou roteador sem fallback e janela.

## Arquitetura no Setup MNO

O instalador usa `Pi-hole na tag latest`, publica portas DNS e web no host, monta volume e limita 256 MB, enquanto o catálogo indica 128 MB. Portas 53/80/443 podem conflitar com systemd-resolved, Traefik ou outros serviços.

## Pré-requisitos

Exige IP estável, gate de conflito de portas TCP/UDP, upstream DNS, fallback independente, volume e acesso administrativo. DHCP/NTP requerem capacidades extras e não devem ser ativados implicitamente.

## Fluxo seguro

Use senha web forte, restrinja admin, não opere recursor aberto e limite `FTLCONF_dns_listeningMode`. Não mude DNS real durante smoke test; valide primeiro com cliente temporário.

## Primeiro acesso e integrações

Aponte somente cliente descartável, valide consultas permitidas/bloqueadas, fallback e painel. Teste retorno ao DNS anterior antes de migrar a rede.

## Backup e atualização

Preserve `/etc/pihole` e exporte configuração Teleporter. Antes de atualizar a imagem, registre versão, faça backup e mantenha DNS alternativo; rollback restaura volume e imagem.

## Validação

Confirme TCP/UDP 53, upstream, cache, bloqueio, senha, persistência, conflito de portas e recuperação quando o serviço para.

## Riscos e limites

Erro derruba DNS da rede; porta DNS padrão é crítica. `latest`, listening mode amplo e falta de fallback podem criar indisponibilidade ou resolver consultas externas.

## Diagnóstico

Separe cliente, rota, porta DNS padrão, upstream, FTL, lista e cache. Use domínios públicos de teste e nunca altere DNS global sem autorização.
