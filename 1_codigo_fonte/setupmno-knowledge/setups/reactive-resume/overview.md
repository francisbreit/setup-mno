---
{
  "schemaVersion": 1,
  "documentId": "setup-reactive-resume-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "5b5d817456368b5665f1dfb956699c8ee69086388d9cf2cd8a0797c3eabf2440",
  "documentType": "setup",
  "title": "Reactive Resume no Setup MNO",
  "setupId": "reactive-resume",
  "setupVersion": "7.48.13",
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
    "reactive-resume",
    "curriculo",
    "postgres",
    "redis"
  ],
  "sources": [
    {
      "sourceId": "reactive-resume-installer",
      "title": "Instalador Reactive Resume",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/reactiveresume.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "reactive-resume-docs",
      "title": "Documentação oficial do Reactive Resume",
      "sourceType": "official-documentation",
      "location": "https://docs.rxresu.me/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "reactive-resume-quickstart",
      "title": "Quickstart oficial do Reactive Resume",
      "sourceType": "official-documentation",
      "location": "https://docs.rxresu.me/getting-started/quickstart",
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
# Reactive Resume no Setup MNO

## Quando usar

Use para criação e hospedagem de currículos com controle próprio dos dados. Avalie se o usuário realmente precisa de contas e compartilhamento público ou apenas de exportação local.

## Arquitetura no Setup MNO

O instalador combina a aplicação, banco e Redis dedicado conforme o script. A imagem flutuante e a evolução entre versões maiores exigem fixação e teste de migração.

## Pré-requisitos

O catálogo declara cerca de 512 MB de RAM, abaixo de referências comuns para aplicação, banco e renderização de PDF juntos; valide sob carga.

Exige domínio HTTPS, banco, Redis, storage para ativos e serviço de geração de PDF compatível. Currículos contêm dados pessoais e precisam de retenção e consentimento claros.

## Fluxo seguro

Mantenha cadastro controlado, URLs públicas deliberadas e credenciais de email ou storage fora do Assistente. Use Redis dedicado e contas de banco com menor privilégio.

## Primeiro acesso e integrações

Crie currículo fictício, teste exportação em PDF e compartilhamento privado. Só configure email ou storage externo após revisar saída de dados.

## Backup e atualização

Preserve banco, uploads e configuração, teste restauração e geração de PDF. Registre a versão antes de migrar entre releases maiores.

## Validação

Confirme login, persistência, PDF, remoção de compartilhamento, backup e restore. Teste que um currículo privado não é acessível anonimamente.

## Riscos e limites

Dados pessoais, links públicos e cadeia de renderização de PDF elevam o risco. Versões incompatíveis podem exigir migração de banco e configuração.

## Diagnóstico

Separe proxy, aplicação, banco, Redis, storage, email e renderizador. Use currículo e endereço fictícios.
