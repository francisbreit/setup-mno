---
{
  "schemaVersion": 1,
  "documentId": "setup-evolution-crm-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "80c54e4eded529eb9480898d5e424e4acf8e6c1143c117008d2a4dd907d58dff",
  "documentType": "setup",
  "title": "Evolution CRM no Setup MNO",
  "setupId": "evolution-crm",
  "setupVersion": "7.19.5",
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
    "evolution-crm",
    "crm",
    "atendimento",
    "ia"
  ],
  "sources": [
    {
      "sourceId": "evolution-crm-installer",
      "title": "Instalador Evolution CRM",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/evocrm.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "evolution-crm-official-1",
      "title": "Documentação oficial de Evolution CRM",
      "sourceType": "official-documentation",
      "location": "https://github.com/EvolutionAPI/evo-crm-community",
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
# Evolution CRM no Setup MNO

## Quando usar

Use para avaliar a edição comunitária do CRM de atendimento assistido por IA do ecossistema Evolution. A recomendação deve considerar finalidade, dados tratados, manutenção e alternativa mais simples; a existência no catálogo não significa homologação automática.

## Arquitetura no Setup MNO

O instalador entrega a aplicação CRM e dependências declaradas no script, com uso intensivo de recursos segundo o catálogo. A integração com canais, IA e bancos aumenta a superfície de credenciais e dados pessoais.

## Pré-requisitos

Exige capacidade elevada, domínio, política de acesso, provedor LLM e canais de teste. Revise licença, release e requisitos atuais do repositório antes da instalação.

## Fluxo seguro

Execute somente pelo Instalador Seguro, confirme o resumo antes do deploy e não publique portas administrativas adicionais. Credenciais permanecem fora do Assistente e operações reais continuam sujeitas à confirmação humana.

## Primeiro acesso e integrações

Crie administrador único, desative cadastro público e conecte apenas um canal fictício. Configure funções por menor privilégio e mantenha sugestões de IA sujeitas a revisão humana.

## Backup e atualização

Preserve banco, anexos, configuração de canais e agentes. Exporte dados e teste restore de um tenant fictício; atualização exige baseline de versão e migrações registradas.

## Validação

Confirme HTTPS, autenticação, persistência após recriação controlada, saúde das réplicas e o fluxo funcional mínimo com dados fictícios. Registre versões efetivas e evidências sem segredos; só promova após um teste de restauração aplicável.

## Riscos e limites

Carga alta e projeto em evolução. IA não substitui operador e integrações de mensageria podem ter requisitos externos. Não use `latest` ou credenciais genéricas sem homologação.

## Diagnóstico

Diferencie falta de recursos, banco, canal, provedor LLM e aplicação. Colete métricas agregadas e erros sanitizados, nunca conversas, contatos, anexos ou chaves.
