---
{
  "schemaVersion": 1,
  "documentId": "setup-mautic-4-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "1a6ddf3082df0f3e3f5080a79e666e94f2c34c039818db064f7d1228627cb0f0",
  "documentType": "setup",
  "title": "Mautic 4 Padrão no Setup MNO",
  "setupId": "mautic-4",
  "setupVersion": "7.8.3",
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
    "mautic",
    "marketing",
    "email",
    "legado",
    "v4"
  ],
  "sources": [
    {
      "sourceId": "mautic-4-installer",
      "title": "Instalador Mautic 4 Padrão",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/mauticpadrao.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "mautic-4-official-1",
      "title": "Documentação oficial de Mautic 4 Padrão",
      "sourceType": "official-documentation",
      "location": "https://docs.mautic.org/en/4.x/getting_started/how_to_install_mautic.html",
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
# Mautic 4 Padrão no Setup MNO

## Quando usar

Use para manter uma instalação histórica do Mautic 4 enquanto se prepara migração para linha suportada. A recomendação deve considerar finalidade, dados tratados, manutenção e alternativa mais simples; a existência no catálogo não significa homologação automática.

## Arquitetura no Setup MNO

O instalador usa a composição Mautic 4 com banco MySQL ou compatível e serviços de cron definidos no script. É uma versão principal antiga e deve permanecer separada de Mautic 6 e 7.

## Pré-requisitos

Exige backup completo, inventário de plugins, temas, crons, fila e SMTP, além de plano de migração. Confirme matriz de suporte e caminho oficial antes de qualquer atualização.

## Fluxo seguro

Execute somente pelo Instalador Seguro, confirme o resumo antes do deploy e não publique portas administrativas adicionais. Credenciais permanecem fora do Assistente e operações reais continuam sujeitas à confirmação humana.

## Primeiro acesso e integrações

Não recomende novo deploy por padrão. Em legado, restrinja administração, revise usuários e teste somente uma campanha e contato fictícios enquanto valida exportação e migração.

## Backup e atualização

Preserve banco, configuração, mídia, plugins e temas. Execute backup antes de pausar filas e teste restore na mesma versão; depois faça ensaio da migração em cópia.

## Validação

Confirme HTTPS, autenticação, persistência após recriação controlada, saúde das réplicas e o fluxo funcional mínimo com dados fictícios. Registre versões efetivas e evidências sem segredos; só promova após um teste de restauração aplicável.

## Riscos e limites

Promoção bloqueada até comprovar suporte e segurança da linha 4. Plugins podem impedir upgrade. Marketing exige consentimento, reputação de domínio e cumprimento de privacidade e antispam.

## Diagnóstico

Separe web, banco, cron, fila, SMTP e plugin. Use contato e domínio de teste e nunca envie lista, credencial SMTP, token ou conteúdo de campanha ao Assistente.
