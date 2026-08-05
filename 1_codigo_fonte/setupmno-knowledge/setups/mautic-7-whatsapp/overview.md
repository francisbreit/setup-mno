---
{
  "schemaVersion": 1,
  "documentId": "setup-mautic-7-whatsapp-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "eb8fec64fc9796075620a3a92185dec000d73d137a416612df0944c344048adc",
  "documentType": "setup",
  "title": "Mautic 7 WhatsApp Marketing no Setup MNO",
  "setupId": "mautic-7-whatsapp",
  "setupVersion": "7.7.20",
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
    "v7",
    "customizado"
  ],
  "sources": [
    {
      "sourceId": "mautic-7-whatsapp-installer",
      "title": "Instalador Mautic 7 WhatsApp Marketing",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/mautic7whatsmkt.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "mautic-7-whatsapp-official-1",
      "title": "Documentação oficial de Mautic 7 WhatsApp Marketing",
      "sourceType": "official-documentation",
      "location": "https://docs.mautic.org/en/7.0/getting_started/how_to_install_mautic.html",
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
# Mautic 7 WhatsApp Marketing no Setup MNO

## Quando usar

Use para avaliar uma variante customizada de Mautic 7 para campanhas multicanal. A recomendação deve considerar finalidade, dados tratados, manutenção e alternativa mais simples; a existência no catálogo não significa homologação automática.

## Arquitetura no Setup MNO

O instalador coordena banco, web, workers e crons usando uma imagem customizada para a variante. A integração de WhatsApp não é parte do núcleo oficial do Mautic e precisa de auditoria própria.

## Pré-requisitos

Exige capacidade elevada, auditoria da imagem, consentimento, provedor autorizado, SMTP, DNS de e-mail e política de limites e descadastro. Não conecte listas reais antes da homologação.

## Fluxo seguro

Execute somente pelo Instalador Seguro, confirme o resumo antes do deploy e não publique portas administrativas adicionais. Credenciais permanecem fora do Assistente e operações reais continuam sujeitas à confirmação humana.

## Primeiro acesso e integrações

Valide Mautic e filas com contato fictício e depois um canal de teste. Mantenha campanhas pausadas, credenciais por serviço e aprovação humana para ativação.

## Backup e atualização

Preserve banco, mídia, plugins, temas e digest da imagem customizada. Teste restore, migrações e comportamento do conector em ambiente isolado antes de atualizar.

## Validação

Confirme HTTPS, autenticação, persistência após recriação controlada, saúde das réplicas e o fluxo funcional mínimo com dados fictícios. Registre versões efetivas e evidências sem segredos; só promova após um teste de restauração aplicável.

## Riscos e limites

Promoção bloqueada até homologar imagem, plugin e conformidade. Automação multicanal amplifica erros e bloqueios; o Setup não executa nem autoriza campanhas em nome do usuário.

## Diagnóstico

Separe web, banco, worker, cron, SMTP e mensageria. Use dados sintéticos e nunca inclua contatos, telefones, tokens, listas ou conteúdo de campanha na evidência.
