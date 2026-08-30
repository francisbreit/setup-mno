---
{
  "schemaVersion": 1,
  "documentId": "setup-heyform-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "07f1b794610eea834147cd9e7397529066f481fad13ce7cf8252d67d50737a9f",
  "documentType": "setup",
  "title": "HeyForm no Setup MNO",
  "setupId": "heyform",
  "setupVersion": "7.42.0",
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
    "heyform",
    "formularios",
    "pesquisa",
    "mongodb"
  ],
  "sources": [
    {
      "sourceId": "heyform-installer",
      "title": "Instalador HeyForm",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/heyform.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "heyform-official-1",
      "title": "Documentação oficial de HeyForm",
      "sourceType": "official-documentation",
      "location": "https://docs.heyform.net/open-source/self-hosting",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "heyform-official-2",
      "title": "Documentação oficial de HeyForm",
      "sourceType": "official-documentation",
      "location": "https://github.com/heyform/heyform",
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
# HeyForm no Setup MNO

## Quando usar

Use para criar formulários e coletar respostas em uma edição comunitária self-hosted. A recomendação deve considerar finalidade, dados tratados, manutenção e alternativa mais simples; a existência no catálogo não significa homologação automática.

## Arquitetura no Setup MNO

O instalador entrega HeyForm com as dependências definidas pelo script. A documentação oficial usa MongoDB e KeyDB ou equivalente, além de proxy HTTPS; persistência e chaves devem ser verificadas no deployment real.

## Pré-requisitos

Exige domínio, HTTPS, volumes, chave da aplicação e política de consentimento. Defina retenção, exportação e proteção contra cadastro ou submissões abusivas.

## Fluxo seguro

Execute somente pelo Instalador Seguro, confirme o resumo antes do deploy e não publique portas administrativas adicionais. Credenciais permanecem fora do Assistente e operações reais continuam sujeitas à confirmação humana.

## Primeiro acesso e integrações

Crie o administrador, restrinja criação de contas e publique um formulário fictício. Valide submissão, exportação e eventual upload ou webhook com dados de teste.

## Backup e atualização

Preserve banco, cache persistente quando necessário e arquivos enviados. Mantenha exportação independente e teste restore antes de trocar imagens ou schema.

## Validação

Confirme HTTPS, autenticação, persistência após recriação controlada, saúde das réplicas e o fluxo funcional mínimo com dados fictícios. Registre versões efetivas e evidências sem segredos; só promova após um teste de restauração aplicável.

## Riscos e limites

Formulários podem coletar dados pessoais e arquivos hostis. A tag flutuante e dependências compartilhadas reduzem reprodutibilidade. Aplique limites e validação de uploads.

## Diagnóstico

Separe página pública, autenticação, aplicação, MongoDB, cache e webhook. Use submissões fictícias; não copie respostas reais, tokens ou arquivos ao Assistente.
