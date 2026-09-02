---
{
  "schemaVersion": 1,
  "documentId": "setup-jellyfin-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "5646641592a1a3f63717cfc18a8334ea5de31bd8457221e812d63345b2886aba",
  "documentType": "setup",
  "title": "Jellyfin no Setup MNO",
  "setupId": "jellyfin",
  "setupVersion": "7.43.1",
  "architectures": [
    "amd64",
    "arm64"
  ],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": [
    "jellyfin",
    "midia",
    "streaming",
    "transcodificacao"
  ],
  "sources": [
    {
      "sourceId": "jellyfin-installer",
      "title": "Instalador Jellyfin",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/jellyfin.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "jellyfin-official-1",
      "title": "Documentação oficial de Jellyfin",
      "sourceType": "official-documentation",
      "location": "https://jellyfin.org/docs/general/installation/container/",
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
# Jellyfin no Setup MNO

## Quando usar

Use para organizar e transmitir uma biblioteca de mídia própria em ambiente self-hosted. A recomendação deve considerar finalidade, dados tratados, manutenção e alternativa mais simples; a existência no catálogo não significa homologação automática.

## Arquitetura no Setup MNO

O instalador entrega Jellyfin com volumes de configuração, cache e mídia conforme o script e rota web pelo Setup. Transcodificação por hardware depende de dispositivos e permissões do host que não são universais, especialmente em WSL2.

## Pré-requisitos

Exige armazenamento, direitos sobre a mídia, domínio HTTPS e estimativa de transcodificações simultâneas. Defina caminhos persistentes, permissões e se haverá aceleração por hardware.

## Fluxo seguro

Execute somente pelo Instalador Seguro, confirme o resumo antes do deploy e não publique portas administrativas adicionais. Credenciais permanecem fora do Assistente e operações reais continuam sujeitas à confirmação humana.

## Primeiro acesso e integrações

Crie o administrador, desative acesso anônimo e adicione primeiro uma biblioteca de teste somente leitura. Valide reprodução direta antes de habilitar transcodificação ou acesso remoto.

## Backup e atualização

Preserve configuração, metadados e cache útil; a biblioteca original deve ter proteção própria. Registre caminhos internos, pois a restauração exige que eles permaneçam equivalentes.

## Validação

Confirme HTTPS, autenticação, persistência após recriação controlada, saúde das réplicas e o fluxo funcional mínimo com dados fictícios. Registre versões efetivas e evidências sem segredos; só promova após um teste de restauração aplicável.

## Riscos e limites

CPU, GPU, codec e largura de banda determinam capacidade. Contêiner em Windows ou macOS não tem suporte oficial completo para alguns recursos. O Setup não concede direitos sobre conteúdo.

## Diagnóstico

Separe escaneamento, permissões, reprodução direta, transcodificação e rede. Use arquivo de teste e logs sanitizados; não exponha nomes de mídia, usuários ou caminhos privados.
