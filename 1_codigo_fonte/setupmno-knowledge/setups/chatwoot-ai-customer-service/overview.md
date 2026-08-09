---
{
  "schemaVersion": 1,
  "documentId": "setup-chatwoot-ai-customer-service-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "ee66e872d4a624814cdcabac12c3f1d4f334248b99dd1aa1f785bcaf1c12c03d",
  "documentType": "setup",
  "title": "Chatwoot AI Customer Service no Setup MNO",
  "setupId": "chatwoot-ai-customer-service",
  "setupVersion": "7.7.40",
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
    "chatwoot",
    "evolution-api",
    "n8n",
    "ia",
    "atendimento"
  ],
  "sources": [
    {
      "sourceId": "chatwoot-ai-customer-service-installer",
      "title": "Instalador Chatwoot AI Customer Service",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/chatwoot_ai_customer_service.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "chatwoot-ai-customer-service-official-1",
      "title": "Documentação oficial de Chatwoot AI Customer Service",
      "sourceType": "official-documentation",
      "location": "https://developers.chatwoot.com/self-hosted/deployment/architecture",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "chatwoot-ai-customer-service-official-2",
      "title": "Documentação oficial de Chatwoot AI Customer Service",
      "sourceType": "official-documentation",
      "location": "https://doc.evolution-api.com/",
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
# Chatwoot AI Customer Service no Setup MNO

## Quando usar

Use para montar um laboratório integrado de atendimento, WhatsApp, automação e modelos de IA. A recomendação deve considerar finalidade, dados tratados, manutenção e alternativa mais simples; a existência no catálogo não significa homologação automática.

## Arquitetura no Setup MNO

O combo cria várias stacks: Chatwoot, Evolution API, Redis dedicados, n8n, LiteLLM, Qdrant e dependências opcionais como RabbitMQ, MinIO e Ollama. Usa PostgreSQL do Setup e múltiplos domínios; o catálogo estima carga alta.

## Pré-requisitos

Exige servidor dimensionado, domínios, SMTP, credenciais separadas, política de dados e escolha explícita do provedor de IA. Inventarie stacks já existentes para evitar colisões.

## Fluxo seguro

Execute somente pelo Instalador Seguro, confirme o resumo antes do deploy e não publique portas administrativas adicionais. Credenciais permanecem fora do Assistente e operações reais continuam sujeitas à confirmação humana.

## Primeiro acesso e integrações

Valide cada componente isoladamente, depois integre por credenciais de serviço com menor privilégio. Use conversas e números de teste; a ativação de IA ou automações não autoriza respostas automáticas em produção.

## Backup e atualização

Preserve bancos do Chatwoot, Evolution e LiteLLM, volumes dos Redis e armazenamento de objetos quando usado. Registre configuração do n8n e faça restore coordenado antes de qualquer atualização.

## Validação

Confirme HTTPS, autenticação, persistência após recriação controlada, saúde das réplicas e o fluxo funcional mínimo com dados fictícios. Registre versões efetivas e evidências sem segredos; só promova após um teste de restauração aplicável.

## Riscos e limites

É um combo experimental e de alto impacto. Há imagens flutuantes, criação direta de bancos e componentes externos. Conexões não oficiais de WhatsApp podem sofrer bloqueios; revise termos, privacidade e consentimento.

## Diagnóstico

Diagnostique por camada: DNS/TLS, réplicas, banco, filas, armazenamento, Evolution, Chatwoot, n8n e provedor LLM. Nunca envie conversas, telefones, tokens ou chaves nos logs.
