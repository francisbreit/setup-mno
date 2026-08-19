---
{
  "schemaVersion": 1,
  "documentId": "setup-ntfy-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "ba6c99dea6ac9e1f97b835b0dd54683a864e7adf480a19477686945c608d58b8",
  "documentType": "setup",
  "title": "ntfy no Setup MNO",
  "setupId": "ntfy",
  "setupVersion": "7.24.1",
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
    "ntfy",
    "notificacoes",
    "push",
    "acl"
  ],
  "sources": [
    {
      "sourceId": "ntfy-installer",
      "title": "Instalador ntfy",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/ntfy.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "ntfy-install",
      "title": "Instalação oficial ntfy",
      "sourceType": "official-documentation",
      "location": "https://docs.ntfy.sh/install/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "ntfy-config",
      "title": "Configuração e controle de acesso ntfy",
      "sourceType": "official-documentation",
      "location": "https://github.com/binwiederhier/ntfy/blob/main/docs/config.md",
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
# ntfy no Setup MNO

## Quando usar

Use para notificações push por tópicos em integrações controladas. Nomes de tópicos não são segredos e não substituem autenticação ou autorização.

## Arquitetura no Setup MNO

O instalador usa `ntfy na tag latest`, volume, comando `serve`, rota e limite de 1 GB. Não há configuração evidente de `auth-file` ou `auth-default-access`; por padrão o servidor permite leitura e escrita a todos.

## Pré-requisitos

Exige domínio HTTPS, volume, política de tópicos, usuários/tokens e compatibilidade móvel. Para iOS, avalie o fluxo de upstream APNS descrito pelo projeto.

## Fluxo seguro

Não exponha o estado padrão. Configure `auth-file`, `auth-default-access: deny-all`, usuários e ACL por tópico; proteja tokens e evite conteúdo sensível em título/corpo.

## Primeiro acesso e integrações

Crie usuário e tópico fictícios, teste publish/subscribe autorizado e negado, web e app móvel. Verifique retenção e expiração.

## Backup e atualização

Preserve config, cache quando necessário e banco de autenticação. Antes de atualizar, fixe tag e teste ACL; rollback restaura imagem e dados/configuração.

## Validação

Confirme autenticação, deny-all, ACL, token, entrega, retenção, WebSocket/SSE, persistência e comportamento offline.

## Riscos e limites

Configuração padrão aberta permite ler e publicar em qualquer tópico. Mensagens podem expor dados; `latest` e push móvel têm dependências externas.

## Diagnóstico

Separe cliente, ACL, token, tópico, cache, upstream móvel e proxy. Use mensagens fictícias e nunca cole tokens.
