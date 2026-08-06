---
{
  "schemaVersion": 1,
  "documentId": "setup-chatwoot-original-unlocked-evolution-rabbitmq-minio-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "d381426d3de27a2de1a40e47506b85599b1bd0dee4debffe4b0327ee1ab9c358",
  "documentType": "setup",
  "title": "Chatwoot Original Desbloqueado com Evolution, RabbitMQ e MinIO no Setup MNO",
  "setupId": "chatwoot-original-unlocked-evolution-rabbitmq-minio",
  "setupVersion": "7.7.25",
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
    "minio",
    "desbloqueado"
  ],
  "sources": [
    {
      "sourceId": "chatwoot-original-unlocked-evolution-rabbitmq-minio-installer",
      "title": "Instalador Chatwoot Original Desbloqueado com Evolution, RabbitMQ e MinIO",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/chatwootorig_desbloq__evo2_rabbitmq_minio.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "chatwoot-original-unlocked-evolution-rabbitmq-minio-official-1",
      "title": "Documentação oficial de Chatwoot Original Desbloqueado com Evolution, RabbitMQ e MinIO",
      "sourceType": "official-documentation",
      "location": "https://developers.chatwoot.com/self-hosted/deployment/architecture",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "chatwoot-original-unlocked-evolution-rabbitmq-minio-official-2",
      "title": "Documentação oficial de Chatwoot Original Desbloqueado com Evolution, RabbitMQ e MinIO",
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
# Chatwoot Original Desbloqueado com Evolution, RabbitMQ e MinIO no Setup MNO

## Quando usar

Use para preservar um combo histórico customizado de atendimento e WhatsApp para análise e migração. A recomendação deve considerar finalidade, dados tratados, manutenção e alternativa mais simples; a existência no catálogo não significa homologação automática.

## Arquitetura no Setup MNO

O instalador combina Chatwoot customizado, Evolution API, Redis, RabbitMQ e MinIO, reutilizando serviços quando os encontra. Mantém credenciais em arquivos operacionais legados e apresenta grande superfície de estado.

## Pré-requisitos

Exige aprovação técnica e jurídica da customização, backups completos, domínios, SMTP e inventário dos serviços compartilhados. Não aplique sobre produção sem compreender o que significa a variante desbloqueada.

## Fluxo seguro

Execute somente pelo Instalador Seguro, confirme o resumo antes do deploy e não publique portas administrativas adicionais. Credenciais permanecem fora do Assistente e operações reais continuam sujeitas à confirmação humana.

## Primeiro acesso e integrações

Trate a variante como não homologada. Restrinja os painéis, troque credenciais padrão e valide somente com uma conta de teste. Não atribua suporte oficial do Chatwoot a componentes modificados.

## Backup e atualização

Preserve PostgreSQL, Redis, RabbitMQ e objetos do MinIO, incluindo políticas e contas de serviço. Teste a restauração do conjunto em namespace isolado antes de alterar qualquer imagem.

## Validação

Confirme HTTPS, autenticação, persistência após recriação controlada, saúde das réplicas e o fluxo funcional mínimo com dados fictícios. Registre versões efetivas e evidências sem segredos; só promova após um teste de restauração aplicável.

## Riscos e limites

Promoção bloqueada até auditoria do código customizado, procedência das imagens e licenças. O uso compartilhado do MinIO e padrões antigos de segredo ampliam impacto e dificultam rollback parcial.

## Diagnóstico

Identifique qual substack falhou e se foi criada ou reutilizada. Não faça limpeza ampla; reúna versões, réplicas e erros sanitizados, mantendo credenciais e dados de atendimento fora do Assistente.
