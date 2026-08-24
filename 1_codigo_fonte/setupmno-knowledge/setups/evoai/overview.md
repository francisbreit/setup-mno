---
{
  "schemaVersion": 1,
  "documentId": "setup-evoai-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "99a8d8a01baad7d83fc12430fc0d7ee9479d772f8679d394a0c80923f6b98d57",
  "documentType": "setup",
  "title": "EvoAI no Setup MNO",
  "setupId": "evoai",
  "setupVersion": "7.33.4",
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
    "evoai",
    "ia",
    "agentes",
    "evolution-api"
  ],
  "sources": [
    {
      "sourceId": "evoai-installer",
      "title": "Instalador EvoAI",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/evoai.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "evoai-official-1",
      "title": "Documentação oficial de EvoAI",
      "sourceType": "official-documentation",
      "location": "https://github.com/EvolutionAPI",
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
# EvoAI no Setup MNO

## Quando usar

Use para experimentar agentes de IA integrados ao ecossistema Evolution API. A recomendação deve considerar finalidade, dados tratados, manutenção e alternativa mais simples; a existência no catálogo não significa homologação automática.

## Arquitetura no Setup MNO

O instalador cria a aplicação EvoAI conforme a composição interna do Setup, com rota web e persistência declarada. A solução pode depender de banco, Evolution API e provedor de modelos.

## Pré-requisitos

Exige provedor LLM, credenciais separadas, instância Evolution de teste, domínio HTTPS e política de dados. Defina limites de custo, ferramentas permitidas e aprovação humana.

## Fluxo seguro

Execute somente pelo Instalador Seguro, confirme o resumo antes do deploy e não publique portas administrativas adicionais. Credenciais permanecem fora do Assistente e operações reais continuam sujeitas à confirmação humana.

## Primeiro acesso e integrações

Cadastre primeiro um agente sem ferramentas destrutivas e conecte uma instância de teste. Valide respostas com mensagens sintéticas e mantenha envio automático desativado até revisão.

## Backup e atualização

Preserve banco, configuração dos agentes e fluxos; documente modelo, prompts e versão. Faça rollback para baseline completa, não apenas da imagem, quando houver migração de schema.

## Validação

Confirme HTTPS, autenticação, persistência após recriação controlada, saúde das réplicas e o fluxo funcional mínimo com dados fictícios. Registre versões efetivas e evidências sem segredos; só promova após um teste de restauração aplicável.

## Riscos e limites

Respostas de IA podem errar e conexões WhatsApp podem ser não oficiais. Não existe autorização implícita para enviar mensagens ou executar ações. Procedência e manutenção da imagem exigem homologação.

## Diagnóstico

Separe falha do EvoAI, provedor, banco e Evolution. Colete códigos e horários sanitizados sem prompt privado, telefone, mensagem, token ou chave.
