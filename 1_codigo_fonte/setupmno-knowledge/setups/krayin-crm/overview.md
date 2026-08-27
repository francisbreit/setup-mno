---
{
  "schemaVersion": 1,
  "documentId": "setup-krayin-crm-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "591f209881bbf53fee3a960feb266f9639d5699a0c8f468ac633c86d3ae73654",
  "documentType": "setup",
  "title": "Krayin CRM no Setup MNO",
  "setupId": "krayin-crm",
  "setupVersion": "7.37.1",
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
    "krayin-crm",
    "crm",
    "laravel",
    "vendas"
  ],
  "sources": [
    {
      "sourceId": "krayin-crm-installer",
      "title": "Instalador Krayin CRM",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/krayincrm.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "krayin-crm-official-1",
      "title": "Documentação oficial de Krayin CRM",
      "sourceType": "official-documentation",
      "location": "https://devdocs.krayincrm.com/2.2/introduction/installation.html",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "krayin-crm-official-2",
      "title": "Documentação oficial de Krayin CRM",
      "sourceType": "official-documentation",
      "location": "https://github.com/krayin/laravel-crm",
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
# Krayin CRM no Setup MNO

## Quando usar

Use para gerenciar leads, contatos, oportunidades e atividades comerciais em um CRM open source. A recomendação deve considerar finalidade, dados tratados, manutenção e alternativa mais simples; a existência no catálogo não significa homologação automática.

## Arquitetura no Setup MNO

O instalador entrega Krayin atrás do proxy e o conecta ao banco definido pelo script. A aplicação Laravel mantém arquivos e configuração persistentes; jobs e e-mail precisam ser verificados conforme a versão instalada.

## Pré-requisitos

Exige domínio, SMTP, banco, perfis de acesso e política de dados pessoais. Confirme requisitos de PHP e banco da release e dimensione pelo menos a memória recomendada pelo projeto.

## Fluxo seguro

Execute somente pelo Instalador Seguro, confirme o resumo antes do deploy e não publique portas administrativas adicionais. Credenciais permanecem fora do Assistente e operações reais continuam sujeitas à confirmação humana.

## Primeiro acesso e integrações

Conclua o instalador, substitua qualquer credencial de demonstração e crie perfis por função. Teste lead, oportunidade, atividade e envio para endereço fictício.

## Backup e atualização

Preserve banco, uploads, configuração e chave da aplicação. Antes de atualizar, valide guia de upgrade, dependências e migrações e execute restore completo em cópia isolada.

## Validação

Confirme HTTPS, autenticação, persistência após recriação controlada, saúde das réplicas e o fluxo funcional mínimo com dados fictícios. Registre versões efetivas e evidências sem segredos; só promova após um teste de restauração aplicável.

## Riscos e limites

CRM concentra dados pessoais e comerciais. Extensões podem ter licenças ou compatibilidade distintas. Credenciais padrão documentadas pelo projeto nunca devem permanecer em produção.

## Diagnóstico

Separe aplicação, banco, fila, e-mail, permissões e extensão. Reproduza com contato fictício e remova nomes, e-mails, valores e tokens dos logs.
