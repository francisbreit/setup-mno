---
{
  "schemaVersion": 1,
  "documentId": "setup-mautic-6-whatsapp-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "52c3e2896408e7ac2602ff232f1c23abca563e270b63c61d09b769c47b823d6b",
  "documentType": "setup",
  "title": "Mautic 6 WhatsApp Marketing no Setup MNO",
  "setupId": "mautic-6-whatsapp",
  "setupVersion": "7.49.0",
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
    "mautic",
    "whatsapp",
    "marketing",
    "v6",
    "customizado"
  ],
  "sources": [
    {
      "sourceId": "mautic-6-whatsapp-installer",
      "title": "Instalador Mautic 6 WhatsApp Marketing",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/mautic6whatsmkt.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "mautic-6-whatsapp-official-1",
      "title": "Documentação oficial de Mautic 6 WhatsApp Marketing",
      "sourceType": "official-documentation",
      "location": "https://docs.mautic.org/en/6.0/getting_started/how_to_install_mautic.html",
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
# Mautic 6 WhatsApp Marketing no Setup MNO

## Quando usar

Use para avaliar uma variante customizada de Mautic 6 com integrações adicionais de mensagens. A recomendação deve considerar finalidade, dados tratados, manutenção e alternativa mais simples; a existência no catálogo não significa homologação automática.

## Arquitetura no Setup MNO

O instalador usa uma imagem customizada em alguns serviços, banco compatível e workers ou crons do Mautic 6. A extensão de WhatsApp não faz parte do núcleo oficial e precisa de validação independente.

## Pré-requisitos

Exige auditoria da imagem e plugin, licença, capacidade, consentimento verificável, SMTP e provedor de mensageria autorizado. Defina limites e opt-out antes de conectar produção.

## Fluxo seguro

Execute somente pelo Instalador Seguro, confirme o resumo antes do deploy e não publique portas administrativas adicionais. Credenciais permanecem fora do Assistente e operações reais continuam sujeitas à confirmação humana.

## Primeiro acesso e integrações

Valide primeiro Mautic padrão com contato fictício, depois o conector em canal de teste. Restrinja tokens por serviço e mantenha disparos automáticos desativados até homologação.

## Backup e atualização

Preserve banco, mídia, plugins, temas e artefato customizado por digest. Teste restore do conjunto e compatibilidade do conector antes de atualizar.

## Validação

Confirme HTTPS, autenticação, persistência após recriação controlada, saúde das réplicas e o fluxo funcional mínimo com dados fictícios. Registre versões efetivas e evidências sem segredos; só promova após um teste de restauração aplicável.

## Riscos e limites

Promoção bloqueada até homologar procedência e conformidade da customização. WhatsApp e e-mail possuem políticas externas e risco de bloqueio; IA ou automação não autoriza campanha.

## Diagnóstico

Separe Mautic, banco, cron, SMTP e conector. Reproduza com contato e mensagem sintéticos e remova lista, telefone, token e conteúdo dos logs.
