---
{
  "schemaVersion": 1,
  "documentId": "setup-joplin-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "338296410968690a4f9a3213044e603710ddc6990a4d4a993cde240a761fe949",
  "documentType": "setup",
  "title": "Joplin Server no Setup MNO",
  "setupId": "joplin",
  "setupVersion": "7.2.11",
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
    "joplin",
    "notas",
    "sincronizacao",
    "sqlite"
  ],
  "sources": [
    {
      "sourceId": "joplin-installer",
      "title": "Instalador Joplin Server",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/joplin.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "joplin-server",
      "title": "Especificação oficial Joplin Server",
      "sourceType": "official-documentation",
      "location": "https://joplinapp.org/help/apps/joplin_server_business/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "joplin-repo",
      "title": "Repositório oficial Joplin",
      "sourceType": "official-documentation",
      "location": "https://github.com/laurent22/joplin",
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
# Joplin Server no Setup MNO

## Quando usar

Use para sincronizar notas Joplin entre clientes quando privacidade, recursos e recuperação estiverem planejados. Não trate o servidor como editor web completo nem como substituto de backup dos clientes.

## Arquitetura no Setup MNO

O instalador usa `Joplin Server na tag latest`, SQLite em volume e limite de 256 MB. A especificação oficial indica SQLite apenas para desenvolvimento, PostgreSQL 16.8+ em produção e 4 GB mínimos, 8 GB recomendados.

## Pré-requisitos

Para produção, exige domínio HTTPS, PostgreSQL compatível, volume e memória muito acima do catálogo atual. Defina usuários, retenção, E2EE nos clientes e backup.

## Fluxo seguro

Não homologue o fluxo SQLite/256 MB para produção. Proteja contas, limite cadastro e mantenha criptografia ponta a ponta configurada nos clientes quando necessária.

## Primeiro acesso e integrações

Com caderno fictício, sincronize dois clientes, crie conflito controlado e teste anexos e E2EE. Confirme URL e relógio.

## Backup e atualização

Preserve banco, volume e exportações JEX dos clientes. Faça dump consistente antes de atualizar; teste restore e ressincronização em ambiente isolado.

## Validação

Confirme login, sincronização bidirecional, anexo, conflito, E2EE, persistência e restauração. Meça RAM com carga representativa.

## Riscos e limites

SQLite e 256 MB divergem criticamente dos requisitos oficiais de produção. `latest` e migrações podem causar indisponibilidade; E2EE não elimina a necessidade de backup.

## Diagnóstico

Separe cliente, rede, relógio, servidor, banco, anexo e criptografia. Use notas fictícias; nunca compartilhe chaves mestras ou conteúdo.
