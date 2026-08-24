---
{
  "schemaVersion": 1,
  "documentId": "setup-evo-nexus-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "2fb1f922c6fcd2d60edcb3624050de0cb3f5cbef67deffe38d15b1bc12c39e49",
  "documentType": "setup",
  "title": "Evo Nexus no Setup MNO",
  "setupId": "evo-nexus",
  "setupVersion": "7.33.3",
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
    "evo-nexus",
    "ia",
    "evolution-api",
    "plataforma"
  ],
  "sources": [
    {
      "sourceId": "evo-nexus-installer",
      "title": "Instalador Evo Nexus",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/evonexus.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "evo-nexus-official-1",
      "title": "Documentação oficial de Evo Nexus",
      "sourceType": "official-documentation",
      "location": "https://github.com/EvolutionAPI/evo-nexus",
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
# Evo Nexus no Setup MNO

## Quando usar

Use para avaliar uma plataforma experimental de negócios orientada por IA relacionada ao ecossistema Evolution. A recomendação deve considerar finalidade, dados tratados, manutenção e alternativa mais simples; a existência no catálogo não significa homologação automática.

## Arquitetura no Setup MNO

O instalador provisiona a aplicação e suas dependências declaradas no script atrás do proxy do Setup. O próprio repositório descreve o projeto como independente e não oficial, portanto não se presume suporte da Evolution API.

## Pré-requisitos

Exige ambiente de laboratório, domínio, credenciais de teste, capacidade e revisão do código e licença. Não conecte contas de produção até homologar cada integração e mecanismo de autenticação.

## Fluxo seguro

Execute somente pelo Instalador Seguro, confirme o resumo antes do deploy e não publique portas administrativas adicionais. Credenciais permanecem fora do Assistente e operações reais continuam sujeitas à confirmação humana.

## Primeiro acesso e integrações

Crie um tenant fictício, restrinja o cadastro e valide uma integração por vez. Mantenha ferramentas autônomas e webhooks sem privilégios destrutivos.

## Backup e atualização

Preserve banco, volumes e configuração exportável; antes de atualizar, registre o commit ou versão real. Teste rollback em stack separada, pois migrações do projeto podem mudar rapidamente.

## Validação

Confirme HTTPS, autenticação, persistência após recriação controlada, saúde das réplicas e o fluxo funcional mínimo com dados fictícios. Registre versões efetivas e evidências sem segredos; só promova após um teste de restauração aplicável.

## Riscos e limites

Projeto experimental e não oficial. Recursos, APIs e imagens podem mudar sem compatibilidade. Não apresente como produto homologado ou como componente mantido pela Evolution Foundation.

## Diagnóstico

Confirme versão, logs de inicialização, banco e cada conector. Se a falha envolver Evolution ou LLM, isole o componente; não compartilhe mensagens, tokens ou dados de clientes.
