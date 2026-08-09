---
{
  "schemaVersion": 1,
  "documentId": "setup-cognee-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "41841b9ff75d934b1f88a3f1e242ac88ffa9ebb2ce3a90ceff00d39eb27efbe4",
  "documentType": "setup",
  "title": "Cognee no Setup MNO",
  "setupId": "cognee",
  "setupVersion": "7.7.39",
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
    "cognee",
    "rag",
    "grafo",
    "memoria"
  ],
  "sources": [
    {
      "sourceId": "cognee-installer",
      "title": "Instalador Cognee",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/cognee.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "cognee-official-1",
      "title": "Documentação oficial de Cognee",
      "sourceType": "official-documentation",
      "location": "https://docs.cognee.ai/api-reference/introduction",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "cognee-official-2",
      "title": "Documentação oficial de Cognee",
      "sourceType": "official-documentation",
      "location": "https://docs.cognee.ai/setup-configuration/overview",
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
# Cognee no Setup MNO

## Quando usar

Use para experimentar ingestão e recuperação de conhecimento estruturado para aplicações de IA. A recomendação deve considerar finalidade, dados tratados, manutenção e alternativa mais simples; a existência no catálogo não significa homologação automática.

## Arquitetura no Setup MNO

O instalador expõe a API self-hosted do Cognee por uma rota do Setup e persiste os dados declarados pelo script. A aplicação depende de provedor de modelo e pode usar backends de dados conforme configuração.

## Pré-requisitos

Exige chave do provedor, domínio HTTPS, conjunto de teste sem dados sensíveis e orçamento de tokens. Defina política de exclusão e quais fontes podem ser ingeridas.

## Fluxo seguro

Execute somente pelo Instalador Seguro, confirme o resumo antes do deploy e não publique portas administrativas adicionais. Credenciais permanecem fora do Assistente e operações reais continuam sujeitas à confirmação humana.

## Primeiro acesso e integrações

Valide o endpoint de saúde e use um pequeno documento fictício nos fluxos de adição, processamento e busca. Mantenha autenticação habilitada e aplique chaves por segredo fora do chat.

## Backup e atualização

Preserve os volumes e qualquer banco externo usado pelo Cognee. Exporte configuração e registre modelo e embedding; uma restauração só é aceita quando a mesma consulta recupera evidência equivalente.

## Validação

Confirme HTTPS, autenticação, persistência após recriação controlada, saúde das réplicas e o fluxo funcional mínimo com dados fictícios. Registre versões efetivas e evidências sem segredos; só promova após um teste de restauração aplicável.

## Riscos e limites

Qualidade de RAG não é garantia de verdade. Custos e retenção dependem do provedor. O setup precisa de homologação específica de backends, autenticação e versões antes de dados reais.

## Diagnóstico

Separe autenticação, provedor LLM, embedding, ingestão, armazenamento e busca. Registre IDs fictícios e mensagens de erro sanitizadas, não o conteúdo original ou chaves.
