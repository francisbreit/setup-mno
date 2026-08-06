---
{
  "schemaVersion": 1,
  "documentId": "setup-actual-budget-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "518ff11ff4e7673c5bc8638787ad625c30f24463017ffcbb0984b8d7b0a4398d",
  "documentType": "setup",
  "title": "Actual Budget no Setup MNO",
  "setupId": "actual-budget",
  "setupVersion": "7.7.24",
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
    "actual-budget",
    "financas",
    "orcamento",
    "sincronizacao"
  ],
  "sources": [
    {
      "sourceId": "actual-budget-installer",
      "title": "Instalador Actual Budget",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/actualbudget.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "actual-docs",
      "title": "Instalação oficial do Actual Budget",
      "sourceType": "official-documentation",
      "location": "https://actualbudget.org/docs/install/docker/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "actual-restore",
      "title": "Backup e restauração do Actual Budget",
      "sourceType": "official-documentation",
      "location": "https://actualbudget.org/docs/backup-restore/restore/",
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
# Actual Budget no Setup MNO

## Quando usar

Use para orçamento pessoal com método de envelopes, contas, transações e sincronização entre clientes. Não trate como sistema contábil empresarial, conciliação bancária garantida ou substituto de aconselhamento financeiro.

## Arquitetura no Setup MNO

O instalador entrega `Actual Server na tag latest`, uma réplica no manager, volume persistente e rota pelo Traefik ou túnel. O catálogo estima 256 MB. A tag flutuante reduz reprodutibilidade; confirme a versão efetiva antes de atualizar.

## Pré-requisitos

Exige domínio, HTTPS, volume persistente e política de backup. Defina quem administrará o servidor, quais clientes sincronizarão e como arquivos importados serão protegidos.

## Fluxo seguro

Use o Instalador Seguro, não publique porta administrativa adicional e conclua a configuração de acesso no primeiro uso. Não envie saldos, transações, chaves ou arquivos bancários ao Assistente.

## Primeiro acesso e integrações

Crie o arquivo de orçamento, valide login e sincronização em dois clientes e teste uma importação pequena. Integrações bancárias e importadores dependem do país e devem ser avaliados separadamente.

## Backup e atualização

Preserve o volume do servidor e mantenha exportações independentes e cifradas. Antes de trocar a imagem, registre a versão, gere backup restaurável e teste restauração isolada; rollback combina imagem anterior e dados compatíveis.

## Validação

Confirme HTTPS, autenticação, criação e sincronização de uma transação fictícia, persistência após recriação e exportação. Verifique logs sem dados financeiros.

## Riscos e limites

Dados financeiros exigem controle de acesso e retenção rigorosos. `latest` pode introduzir migração não planejada. O Setup não comprova compatibilidade de importadores nem recuperação até um restore real.

## Diagnóstico

Separe falha de DNS/TLS, login, sincronização, armazenamento e cliente. Use orçamento fictício, horários e erros sanitizados; nunca compartilhe transações reais.
