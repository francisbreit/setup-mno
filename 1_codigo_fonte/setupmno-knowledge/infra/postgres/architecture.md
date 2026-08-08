---
{
  "schemaVersion": 1,
  "documentId": "infra-postgres-architecture",
  "documentVersion": "1.0.2",
  "contentSHA256": "f609d697c64a72f1c9c5dafc8ca7fc44b1f1bc18f816edda190868c7727277fa",
  "documentType": "infrastructure",
  "title": "PostgreSQL como serviço-base do Setup MNO",
  "topicId": "postgres",
  "setupVersion": "7.7.31",
  "architectures": ["amd64", "arm64"],
  "category": "architecture",
  "status": "reviewed",
  "updatedAt": "2026-07-30",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": ["postgres", "banco-de-dados", "persistencia"],
  "sources": [
    {
      "sourceId": "postgres-base-script",
      "title": "Criação do PostgreSQL na infraestrutura base",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/dockerswarm.sh",
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
# PostgreSQL como serviço-base do Setup MNO

## Papel no Setup MNO

O PostgreSQL central é preparado pela infraestrutura base e atende setups que
criam bancos lógicos próprios. Scripts de aplicação verificam sua presença
antes de criar o banco necessário e implantar a stack.

## Princípios

Persistência e credenciais não pertencem ao Assistente. O conhecimento pode
explicar dependências e ordem de instalação, mas nunca reproduz senha,
connection string, conteúdo de banco ou comando de mutação. Cada nova
aplicação deve possuir banco logicamente separado.

## Validação

O diagnóstico usa apenas disponibilidade agregada do serviço e estado de
réplicas. Ausência da base, falha de inicialização e erro específico da
aplicação devem ser tratados como hipóteses distintas.

## Riscos e limites

Recriação, migração e restauração podem afetar múltiplos setups. Qualquer
intervenção exige backup verificado, janela de manutenção e operador humano. O
Assistente deve interromper recomendações quando não houver evidência de
recuperação segura.
