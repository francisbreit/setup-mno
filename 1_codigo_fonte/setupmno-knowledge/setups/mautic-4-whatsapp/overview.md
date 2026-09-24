---
{
  "schemaVersion": 1,
  "documentId": "setup-mautic-4-whatsapp-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "4d8e064af8a83359ed312647854c165872ff7cf7fb6c9039740f5c0eff61e651",
  "documentType": "setup",
  "title": "Mautic 4 WhatsApp Marketing no Setup MNO",
  "setupId": "mautic-4-whatsapp",
  "setupVersion": "7.48.25",
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
    "whatsapp",
    "marketing",
    "legado",
    "customizado"
  ],
  "sources": [
    {
      "sourceId": "mautic-4-whatsapp-installer",
      "title": "Instalador Mautic 4 WhatsApp Marketing",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/mautic4whatsmkt.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "mautic-4-whatsapp-official-1",
      "title": "Documentação oficial de Mautic 4 WhatsApp Marketing",
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
# Mautic 4 WhatsApp Marketing no Setup MNO

## Quando usar

Use para preservar uma variante histórica customizada de Mautic 4 com recursos adicionais de marketing. A recomendação deve considerar finalidade, dados tratados, manutenção e alternativa mais simples; a existência no catálogo não significa homologação automática.

## Arquitetura no Setup MNO

O instalador usa uma imagem customizada e a composição Mautic 4 com banco e workers ou crons. A variante não é uma distribuição oficial do Mautic e acopla uma linha legada a integrações externas.

## Pré-requisitos

Exige auditoria da imagem e código customizados, licença, backup, consentimento dos contatos, SMTP e provedor autorizado de mensagens. Não instale sem plano de migração.

## Fluxo seguro

Execute somente pelo Instalador Seguro, confirme o resumo antes do deploy e não publique portas administrativas adicionais. Credenciais permanecem fora do Assistente e operações reais continuam sujeitas à confirmação humana.

## Primeiro acesso e integrações

Trate como não homologado. Restrinja acesso, use contatos e canais de teste e confirme opt-in e opt-out antes de qualquer campanha. Não atribua suporte oficial à customização.

## Backup e atualização

Preserve banco, mídia, plugins, temas e código customizado identificado por digest. Teste restore completo e exportação de campanhas antes de migrar.

## Validação

Confirme HTTPS, autenticação, persistência após recriação controlada, saúde das réplicas e o fluxo funcional mínimo com dados fictícios. Registre versões efetivas e evidências sem segredos; só promova após um teste de restauração aplicável.

## Riscos e limites

Promoção bloqueada: linha 4 antiga, imagem customizada e mensageria podem criar risco de segurança, entrega e bloqueio. O Setup não autoriza disparos nem garante conformidade.

## Diagnóstico

Diferencie Mautic, customização, cron, SMTP e conector WhatsApp. Suspenda somente o fluxo autorizado e sanitize contatos, mensagens, chaves e listas.
