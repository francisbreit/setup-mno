---
{
  "schemaVersion": 1,
  "documentId": "setup-chatwoot-original-evolution-rabbitmq-minio-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "b9e9ee6f2454afa79e59ebd86d6d829967e13ca29a060852fff8d972165e9233",
  "documentType": "setup",
  "title": "Chatwoot Original com Evolution, RabbitMQ e MinIO no Setup MNO",
  "setupId": "chatwoot-original-evolution-rabbitmq-minio",
  "setupVersion": "7.22.2",
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
    "minio"
  ],
  "sources": [
    {
      "sourceId": "chatwoot-original-evolution-rabbitmq-minio-installer",
      "title": "Instalador Chatwoot Original com Evolution, RabbitMQ e MinIO",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/chatwooto_evo2_rabbitmq_minio.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "chatwoot-original-evolution-rabbitmq-minio-official-1",
      "title": "Documentação oficial de Chatwoot Original com Evolution, RabbitMQ e MinIO",
      "sourceType": "official-documentation",
      "location": "https://developers.chatwoot.com/self-hosted/deployment/architecture",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "chatwoot-original-evolution-rabbitmq-minio-official-2",
      "title": "Documentação oficial de Chatwoot Original com Evolution, RabbitMQ e MinIO",
      "sourceType": "official-documentation",
      "location": "https://min.io/docs/minio/container/index.html",
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
# Chatwoot Original com Evolution, RabbitMQ e MinIO no Setup MNO

## Quando usar

Use para unificar atendimento, integração WhatsApp, fila e armazenamento de anexos em um combo histórico. A recomendação deve considerar finalidade, dados tratados, manutenção e alternativa mais simples; a existência no catálogo não significa homologação automática.

## Arquitetura no Setup MNO

O combo coordena Chatwoot, Redis, Evolution API, Redis, RabbitMQ e MinIO, com PostgreSQL do Setup e várias rotas. Pode reutilizar dependências detectadas no ambiente e por isso o inventário prévio é obrigatório.

## Pré-requisitos

Exige capacidade, domínios, SMTP, credenciais únicas, política de retenção e cópias dos bancos e objetos. Valide nomes, redes e serviços existentes antes do instalador.

## Fluxo seguro

Execute somente pelo Instalador Seguro, confirme o resumo antes do deploy e não publique portas administrativas adicionais. Credenciais permanecem fora do Assistente e operações reais continuam sujeitas à confirmação humana.

## Primeiro acesso e integrações

Configure MinIO com conta de serviço restrita, depois filas, Evolution e Chatwoot. Use conversa fictícia com anexo inofensivo para provar o fluxo ponta a ponta.

## Backup e atualização

Inclua bancos, ambos os Redis, RabbitMQ e buckets do MinIO. Registre contas e políticas sem copiar segredos para a documentação; restaure todo o grafo em ensaio isolado.

## Validação

Confirme HTTPS, autenticação, persistência após recriação controlada, saúde das réplicas e o fluxo funcional mínimo com dados fictícios. Registre versões efetivas e evidências sem segredos; só promova após um teste de restauração aplicável.

## Riscos e limites

Há tags flutuantes, componentes acoplados e comportamento legado de reutilização. Uma atualização parcial pode quebrar contratos. WhatsApp não oficial e anexos de clientes exigem revisão legal e de privacidade.

## Diagnóstico

Teste persistência e saúde de cada dependência antes da aplicação. Diferencie falha no envio, webhook, fila, objeto e atendimento e sempre sanitize números, mensagens e credenciais.
