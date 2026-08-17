---
{
  "schemaVersion": 1,
  "documentId": "setup-mautic-7-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "7308d73ab5dbfe7e81158888fc4402924ef2b72509c9362c6d504347b78dcfe5",
  "documentType": "setup",
  "title": "Mautic 7 Padrão no Setup MNO",
  "setupId": "mautic-7",
  "setupVersion": "7.19.8",
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
    "mautic",
    "marketing",
    "email",
    "v7"
  ],
  "sources": [
    {
      "sourceId": "mautic-7-installer",
      "title": "Instalador Mautic 7 Padrão",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/mautic7padrao.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "mautic-7-official-1",
      "title": "Documentação oficial de Mautic 7 Padrão",
      "sourceType": "official-documentation",
      "location": "https://docs.mautic.org/en/7.0/getting_started/how_to_install_mautic.html",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "mautic-7-official-2",
      "title": "Documentação oficial de Mautic 7 Padrão",
      "sourceType": "official-documentation",
      "location": "https://docs.mautic.org/en/7.1/getting_started/how_to_update_mautic.html",
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
# Mautic 7 Padrão no Setup MNO

## Quando usar

Use para executar automação de marketing na linha atual Mautic 7 com workers e agendamentos separados. A recomendação deve considerar finalidade, dados tratados, manutenção e alternativa mais simples; a existência no catálogo não significa homologação automática.

## Arquitetura no Setup MNO

O instalador usa banco Percona compatível e serviços Mautic 7 para web, workers e tarefas agendadas. A composição é pesada e deve manter todos os serviços na mesma release.

## Pré-requisitos

Exige capacidade elevada, domínio, SMTP ou API de envio, DNS de e-mail, consentimento, banco e plano de crons. Verifique requisitos e notas da release exata.

## Fluxo seguro

Execute somente pelo Instalador Seguro, confirme o resumo antes do deploy e não publique portas administrativas adicionais. Credenciais permanecem fora do Assistente e operações reais continuam sujeitas à confirmação humana.

## Primeiro acesso e integrações

Crie administrador forte, valide remetente e configure um contato fictício. Teste segmento, campanha, processamento assíncrono e descadastro antes de importar dados.

## Backup e atualização

Preserve banco, configuração, mídia, plugins e temas. Faça backup consistente, ensaie restore e siga o guia oficial de atualização; rollback exige imagem e schema compatíveis.

## Validação

Confirme HTTPS, autenticação, persistência após recriação controlada, saúde das réplicas e o fluxo funcional mínimo com dados fictícios. Registre versões efetivas e evidências sem segredos; só promova após um teste de restauração aplicável.

## Riscos e limites

Entregabilidade, consentimento e reputação continuam sob responsabilidade do operador. Plugins podem não suportar a nova linha. Atualização parcial entre web e workers é insegura.

## Diagnóstico

Separe web, banco, messenger, cron, SMTP e plugin. Observe filas e horários com dados fictícios e sanitize endereços, campanhas e credenciais.
