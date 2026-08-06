---
{
  "schemaVersion": 1,
  "documentId": "setup-mautic-6-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "b0760d6b339c173a4af1260a7dc469ca64f2bd01df4c8a873e253b604459c5e0",
  "documentType": "setup",
  "title": "Mautic 6 Padrão no Setup MNO",
  "setupId": "mautic-6",
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
    "mautic",
    "marketing",
    "email",
    "v6"
  ],
  "sources": [
    {
      "sourceId": "mautic-6-installer",
      "title": "Instalador Mautic 6 Padrão",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/mautic6padrao.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "mautic-6-official-1",
      "title": "Documentação oficial de Mautic 6 Padrão",
      "sourceType": "official-documentation",
      "location": "https://docs.mautic.org/en/6.0/getting_started/how_to_install_mautic.html",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "mautic-6-official-2",
      "title": "Documentação oficial de Mautic 6 Padrão",
      "sourceType": "official-documentation",
      "location": "https://docs.mautic.org/en/6.0/getting_started/how_to_update_mautic.html",
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
# Mautic 6 Padrão no Setup MNO

## Quando usar

Use para executar automação de marketing e campanhas de e-mail na linha Mautic 6. A recomendação deve considerar finalidade, dados tratados, manutenção e alternativa mais simples; a existência no catálogo não significa homologação automática.

## Arquitetura no Setup MNO

O instalador cria ou reutiliza banco compatível e entrega serviços web e de processamento agendado com imagens Mautic 6. A composição usa múltiplas réplicas funcionais e exige crons coerentes.

## Pré-requisitos

Exige capacidade elevada, domínio, SMTP ou transportador, DNS de e-mail, banco, consentimento e política de retenção. Revise plugins e requisitos da versão exata.

## Fluxo seguro

Execute somente pelo Instalador Seguro, confirme o resumo antes do deploy e não publique portas administrativas adicionais. Credenciais permanecem fora do Assistente e operações reais continuam sujeitas à confirmação humana.

## Primeiro acesso e integrações

Conclua o assistente com administrador forte, configure remetente validado e use contato fictício. Teste segmento, campanha, cron e descadastro antes de importar qualquer lista.

## Backup e atualização

Preserve banco, configuração, mídia, plugins e temas. Pause filas de forma planejada, gere backup consistente e ensaie restore e migrações antes de trocar a imagem.

## Validação

Confirme HTTPS, autenticação, persistência após recriação controlada, saúde das réplicas e o fluxo funcional mínimo com dados fictícios. Registre versões efetivas e evidências sem segredos; só promova após um teste de restauração aplicável.

## Riscos e limites

Reputação, entregabilidade e conformidade não são garantidas pelo deploy. Plugins e transportes variam por versão. A tag precisa permanecer controlada e campanhas exigem aprovação humana.

## Diagnóstico

Separe web, banco, cron, fila, SMTP, DNS de e-mail e plugin. Use contato de teste e métricas agregadas, removendo endereços, conteúdo e credenciais.
