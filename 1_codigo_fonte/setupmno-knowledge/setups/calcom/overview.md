---
{
  "schemaVersion": 1,
  "documentId": "setup-calcom-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "f5628fd6361bf3f0eb73ca18ac5afd2cfde862345eef6fe5f23426184bb8584a",
  "documentType": "setup",
  "title": "Cal.com no Setup MNO",
  "setupId": "calcom",
  "setupVersion": "7.7.3",
  "architectures": [
    "amd64"
  ],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": [
    "calcom",
    "agenda",
    "agendamento",
    "calendario"
  ],
  "sources": [
    {
      "sourceId": "calcom-installer",
      "title": "Instalador Cal.com",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/calcom.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "cal-repo",
      "title": "Repositório oficial Cal.com",
      "sourceType": "official-documentation",
      "location": "https://github.com/calcom/cal.com",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "cal-selfhost",
      "title": "Documentação oficial de self-hosting Cal.com",
      "sourceType": "official-documentation",
      "location": "https://cal.com/docs/self-hosting/introduction",
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
# Cal.com no Setup MNO

## Quando usar

Use para páginas de agendamento, disponibilidade, calendários e integrações de videoconferência. Não prometa integrações OAuth sem registrar aplicativos e URLs de retorno em cada provedor.

## Arquitetura no Setup MNO

O catálogo oferece apenas amd64. O instalador usa `Cal.com na versão 3.7.11`, PostgreSQL compartilhado, SMTP e proxy. Ele define `NEXT_PUBLIC_DISABLE_SIGNUP=false` e `NODE_TLS_REJECT_UNAUTHORIZED=0`; a versão e esses controles são dívida crítica antes de produção.

## Pré-requisitos

Exige domínio HTTPS, banco, SMTP, segredos NextAuth e credenciais dos calendários. Planeje fusos, callbacks OAuth e 1 GB ou mais conforme uso.

## Fluxo seguro

Não exponha produção com cadastro aberto nem validação TLS desabilitada. Trate senha SMTP e segredos no YAML como credenciais, restrinja registro e valide atualização progressiva em cópia isolada.

## Primeiro acesso e integrações

Crie conta administrativa controlada, conecte um calendário de teste, publique um tipo de evento fictício e verifique conflito, fuso e email. Não use calendários reais antes de validar escopos OAuth.

## Backup e atualização

Preserve PostgreSQL e configuração/segredos. Antes de sair da linha 3.7.11, consulte migrações, use versões intermediárias quando exigido e mantenha dump restaurável. Rollback depende do banco pré-migração.

## Validação

Confirme HTTPS válido, cadastro bloqueado conforme política, login, calendário, reserva, cancelamento, fuso, SMTP e callbacks. Verifique que TLS não está globalmente desativado.

## Riscos e limites

Instalador defasado, signup aberto, TLS de Node desabilitado, segredos em YAML e ausência de ARM tornam o estado atual inadequado para produção sem correção.

## Diagnóstico

Separe proxy/TLS, NextAuth, banco, SMTP, OAuth, fuso e webhooks. Remova emails, tokens, agendas e identificadores dos registros enviados ao Assistente.
