---
{
  "schemaVersion": 1,
  "documentId": "setup-chatwoot-evolution-rabbitmq-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "df2cc372e7107636f242da9b335fbdaafec6e1a6a34ac221fee0d5096031dc3d",
  "documentType": "setup",
  "title": "Chatwoot com Evolution e RabbitMQ no Setup MNO",
  "setupId": "chatwoot-evolution-rabbitmq",
  "setupVersion": "7.7.10",
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
    "rabbitmq",
    "whatsapp"
  ],
  "sources": [
    {
      "sourceId": "chatwoot-evolution-rabbitmq-installer",
      "title": "Instalador Chatwoot com Evolution e RabbitMQ",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/chatwootn_evo2_rabbitmq_redisevo.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "chatwoot-evolution-rabbitmq-official-1",
      "title": "Documentação oficial de Chatwoot com Evolution e RabbitMQ",
      "sourceType": "official-documentation",
      "location": "https://developers.chatwoot.com/self-hosted/deployment/architecture",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "chatwoot-evolution-rabbitmq-official-2",
      "title": "Documentação oficial de Chatwoot com Evolution e RabbitMQ",
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
# Chatwoot com Evolution e RabbitMQ no Setup MNO

## Quando usar

Use para integrar atendimento Chatwoot, mensageria Evolution API e filas RabbitMQ sem armazenamento S3 dedicado. A recomendação deve considerar finalidade, dados tratados, manutenção e alternativa mais simples; a existência no catálogo não significa homologação automática.

## Arquitetura no Setup MNO

O combo instala Chatwoot com Redis, Evolution API com Redis e RabbitMQ em stacks relacionadas, usando PostgreSQL do Setup e rotas externas separadas. A operação depende da ordem e das credenciais coletadas.

## Pré-requisitos

Exige domínios distintos, SMTP, chaves fortes, banco saudável, capacidade mínima e consentimento para tratamento de mensagens. Confirme que os nomes das stacks não colidem com instalações existentes.

## Fluxo seguro

Execute somente pelo Instalador Seguro, confirme o resumo antes do deploy e não publique portas administrativas adicionais. Credenciais permanecem fora do Assistente e operações reais continuam sujeitas à confirmação humana.

## Primeiro acesso e integrações

Conclua primeiro os painéis administrativos, crie credenciais de serviço e valide uma mensagem de teste. Não use conta ou conversa real antes de confirmar filas, webhooks e política de retenção.

## Backup e atualização

Copie bancos de Chatwoot e Evolution, dados dos dois Redis e fila RabbitMQ. O rollback deve restaurar versões compatíveis em ordem inversa, sem apagar volumes automaticamente.

## Validação

Confirme HTTPS, autenticação, persistência após recriação controlada, saúde das réplicas e o fluxo funcional mínimo com dados fictícios. Registre versões efetivas e evidências sem segredos; só promova após um teste de restauração aplicável.

## Riscos e limites

O instalador contém tags flutuantes e padrões legados de credenciais e Portainer. A conexão WhatsApp pode não ser oficial; bloqueios do provedor e mudanças de API ficam fora do controle do Setup.

## Diagnóstico

Verifique DNS/TLS, estado das stacks, PostgreSQL, Redis, RabbitMQ, Evolution e só então Chatwoot. Correlacione mensagens fictícias por horário e remova telefones e tokens dos registros.
