---
{
  "schemaVersion": 1,
  "documentId": "setup-evoai-evolution-minio-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "aeb00df427633e42003ffa4986847278bac9a4341c920b0698d8e81ba6f5584e",
  "documentType": "setup",
  "title": "EvoAI com Evolution e MinIO no Setup MNO",
  "setupId": "evoai-evolution-minio",
  "setupVersion": "7.37.2",
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
    "evolution-api",
    "minio",
    "ia"
  ],
  "sources": [
    {
      "sourceId": "evoai-evolution-minio-installer",
      "title": "Instalador EvoAI com Evolution e MinIO",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/evoai_evo2_minio.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "evoai-evolution-minio-official-1",
      "title": "Documentação oficial de EvoAI com Evolution e MinIO",
      "sourceType": "official-documentation",
      "location": "https://github.com/EvolutionAPI",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "evoai-evolution-minio-official-2",
      "title": "Documentação oficial de EvoAI com Evolution e MinIO",
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
# EvoAI com Evolution e MinIO no Setup MNO

## Quando usar

Use para avaliar agentes de IA conectados à mensageria e a armazenamento de objetos em um combo integrado. A recomendação deve considerar finalidade, dados tratados, manutenção e alternativa mais simples; a existência no catálogo não significa homologação automática.

## Arquitetura no Setup MNO

O combo coordena EvoAI, Evolution API, Redis e MinIO com rotas e persistência próprias. A reutilização de serviços existentes e as credenciais cruzadas tornam a ordem de instalação e o inventário anterior obrigatórios.

## Pré-requisitos

Exige servidor dimensionado, domínios, provedor LLM, credenciais de serviço do MinIO, instância de teste e política de retenção de mensagens e objetos.

## Fluxo seguro

Execute somente pelo Instalador Seguro, confirme o resumo antes do deploy e não publique portas administrativas adicionais. Credenciais permanecem fora do Assistente e operações reais continuam sujeitas à confirmação humana.

## Primeiro acesso e integrações

Crie bucket e conta de serviço restrita, valide a Evolution com número de teste e então habilite um agente sem ferramentas destrutivas. Confirme que nenhum objeto fica público.

## Backup e atualização

Preserve bancos, Redis, configuração dos agentes e bucket, incluindo política de acesso. Teste a restauração coordenada e a compatibilidade do schema antes de atualizar qualquer substack.

## Validação

Confirme HTTPS, autenticação, persistência após recriação controlada, saúde das réplicas e o fluxo funcional mínimo com dados fictícios. Registre versões efetivas e evidências sem segredos; só promova após um teste de restauração aplicável.

## Riscos e limites

IA pode produzir conteúdo incorreto e a integração WhatsApp pode sofrer bloqueios. O combo ainda precisa de homologação de procedência, imagens, isolamento e fluxo Portainer; não o apresente como produção pronta.

## Diagnóstico

Separe MinIO, Redis, Evolution, EvoAI e provedor de modelo. Use objetos e mensagens fictícios e remova URLs assinadas, telefones, prompts e chaves dos logs.
