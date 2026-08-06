---
{
  "schemaVersion": 1,
  "documentId": "setup-changedetection-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "38fd7617479dfe2f928eb22c91093600d11ac410fa6ea40229d05cb63dac420d",
  "documentType": "setup",
  "title": "ChangeDetection.io no Setup MNO",
  "setupId": "changedetection",
  "setupVersion": "7.7.27",
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
    "changedetection",
    "monitoramento",
    "mudancas",
    "alertas"
  ],
  "sources": [
    {
      "sourceId": "changedetection-installer",
      "title": "Instalador ChangeDetection.io",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/changedetection.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "changedetection-repo",
      "title": "Repositório oficial ChangeDetection.io",
      "sourceType": "official-documentation",
      "location": "https://github.com/dgtlmoon/changedetection.io",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "changedetection-wiki",
      "title": "Wiki oficial ChangeDetection.io",
      "sourceType": "official-documentation",
      "location": "https://github.com/dgtlmoon/changedetection.io/wiki",
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
# ChangeDetection.io no Setup MNO

## Quando usar

Use para observar alterações em páginas e emitir alertas. Não use para contornar autenticação, termos de uso, robots, paywalls ou limites do site monitorado.

## Arquitetura no Setup MNO

O instalador usa `ChangeDetection.io na tag latest`, uma réplica, volume persistente, rota e limite aproximado de 512 MB. Navegação JavaScript pode exigir serviço adicional não presente no fluxo atual.

## Pré-requisitos

Exige domínio, volume, destino de notificações e autorização para consultar os alvos. Estime frequência, retenção e necessidade de navegador headless.

## Fluxo seguro

Ative autenticação própria, limite acesso público e não armazene cookies ou credenciais além do necessário. Tags flutuantes devem ser substituídas por versão testada em mudanças planejadas.

## Primeiro acesso e integrações

Cadastre URL pública descartável, ajuste seletor e frequência e force uma mudança controlada. Teste notificação sem incluir conteúdo sensível.

## Backup e atualização

Preserve o volume de dados e exporte configurações quando suportado. Registre imagem e configuração antes da atualização, teste em cópia e restaure ambos no rollback.

## Validação

Confirme login, coleta, diferença, filtro, alerta, retenção, persistência e comportamento diante de timeout e bloqueio. Avalie consumo ao usar navegador.

## Riscos e limites

Sem autenticação verificada, o painel pode expor URLs, históricos e credenciais. Coleta agressiva pode bloquear IP, violar políticas ou causar carga. `latest` é não determinístico.

## Diagnóstico

Separe DNS/TLS do alvo, proxy, bloqueio antibot, seletor, renderização, armazenamento e notificação. Use alvos de teste e remova URLs privadas.
