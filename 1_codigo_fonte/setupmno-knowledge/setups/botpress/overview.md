---
{
  "schemaVersion": 1,
  "documentId": "setup-botpress-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "b5d023da853d96834b4206807005751c122d7cc6aed6a9678c7b8b323d21c7ed",
  "documentType": "setup",
  "title": "Botpress no Setup MNO",
  "setupId": "botpress",
  "setupVersion": "7.19.0",
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
    "botpress",
    "chatbot",
    "legado",
    "descontinuado"
  ],
  "sources": [
    {
      "sourceId": "botpress-installer",
      "title": "Instalador Botpress",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/botpress.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "botpress-official-1",
      "title": "Documentação oficial de Botpress",
      "sourceType": "official-documentation",
      "location": "https://botpress.com/docs/studio/guides/advanced/v12/",
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
# Botpress no Setup MNO

## Quando usar

Use para consultar ou recuperar uma instalação histórica do Botpress v12, nunca iniciar um novo projeto. A recomendação deve considerar finalidade, dados tratados, manutenção e alternativa mais simples; a existência no catálogo não significa homologação automática.

## Arquitetura no Setup MNO

O instalador usa a imagem self-hosted histórica com PostgreSQL e Redis compartilhados. A arquitetura está limitada a amd64 e contém dependências flutuantes e padrões anteriores às regras atuais de isolamento.

## Pré-requisitos

Exige aceite formal do risco, inventário de dados, backup do banco e plano de migração. O editor informa que v12 e as versões self-hosted foram encerradas e não estão disponíveis para novos deployments.

## Fluxo seguro

Execute somente pelo Instalador Seguro, confirme o resumo antes do deploy e não publique portas administrativas adicionais. Credenciais permanecem fora do Assistente e operações reais continuam sujeitas à confirmação humana.

## Primeiro acesso e integrações

Não faça novo deploy por padrão. Em uma instância legada autorizada, restrinja a rota, altere credenciais, valide exportação dos bots e planeje migração para alternativa mantida.

## Backup e atualização

Exporte bots e conteúdo, preserve banco e arquivos persistentes e documente a versão efetiva. Restaure somente em ambiente isolado para comprovar que o backup é utilizável.

## Validação

Confirme HTTPS, autenticação, persistência após recriação controlada, saúde das réplicas e o fluxo funcional mínimo com dados fictícios. Registre versões efetivas e evidências sem segredos; só promova após um teste de restauração aplicável.

## Riscos e limites

Promoção bloqueada: o Botpress self-hosted foi oficialmente descontinuado. A imagem antiga, Redis compartilhado, tag flutuante e ausência de manutenção tornam este setup inadequado para produção nova.

## Diagnóstico

Confirme primeiro se a pergunta se refere ao produto Cloud atual ou ao v12 legado. Para o legado, colete versão, estado do banco e logs sanitizados; não recomende reinstalação como correção.
