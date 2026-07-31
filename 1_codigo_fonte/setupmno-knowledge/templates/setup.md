---
{
  "schemaVersion": 1,
  "documentId": "setup-exemplo-overview",
  "documentVersion": "0.1.0",
  "contentSHA256": "substitua-pelo-hash-informado-pelo-linter",
  "documentType": "setup",
  "title": "Exemplo de setup",
  "setupId": "exemplo",
  "setupVersion": "6.0.0",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "draft",
  "updatedAt": "2026-07-30",
  "sourceType": "setup-mno",
  "risk": "medium",
  "language": "pt-BR",
  "tags": ["exemplo", "setup"],
  "sources": [
    {
      "sourceId": "setup-exemplo-script",
      "title": "Instalador do setup de exemplo",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/exemplo.sh",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    }
  ],
  "homologation": {
    "verifiedAt": null,
    "verifiedPorts": [],
    "verifiedImages": []
  }
}
---
# Exemplo

## Quando usar

Descreva o problema atendido e os cenários em que outra solução é melhor.

## Arquitetura no Setup MNO

Descreva serviços, dependências, redes, persistência e exposição sem incluir
credenciais ou dados de clientes.

## Pré-requisitos

Liste recursos, serviços-base e decisões que o usuário deve tomar.

## Fluxo seguro

Explique o fluxo do Instalador Seguro sem fornecer comandos destrutivos.

## Validação

Defina sinais objetivos de saúde e de acesso.

## Riscos e limites

Registre consumo, impacto, limitações e estratégia de rollback.

## Diagnóstico

Oriente verificações consultivas e o próximo passo humano.
