---
{
  "schemaVersion": 1,
  "documentId": "setup-n8n-main-overview",
  "documentVersion": "1.0.2",
  "contentSHA256": "efb3f6835d88de467a6f1e7ace5fe188a08434b6438131525eb9b2735de89cfe",
  "documentType": "setup",
  "title": "n8n sem fila no Setup MNO",
  "setupId": "n8n-main",
  "setupVersion": "7.2.10",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-07-30",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["n8n", "automacao", "sem-fila"],
  "sources": [
    {
      "sourceId": "n8n-main-installer",
      "title": "Instalador n8n sem fila",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/n8nmain.sh",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    },
    {
      "sourceId": "n8n-main-catalog",
      "title": "Entrada n8n sem fila no catálogo",
      "sourceType": "setup-mno",
      "location": "setupmno-control/catalog.json",
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
# n8n sem fila no Setup MNO

## Quando usar

Use a variante sem fila para uma operação simples, com execução regular em uma
única unidade de aplicação. Para maior paralelismo e separação de workers,
avalie as variantes de fila do catálogo.

## Arquitetura no Setup MNO

A aplicação usa um banco lógico no PostgreSQL base, volume persistente para
dados auxiliares e uma rota de administração. Execuções permanecem no processo
principal, sem Redis de fila.

## Pré-requisitos

Exige PostgreSQL, infraestrutura-base, domínio, SMTP quando necessário e
capacidade coerente com a carga. Estime quantidade, duração e concorrência dos
workflows antes de escolher a variante.

## Fluxo seguro

O instalador coleta domínio e SMTP, cria o banco, gera chave de criptografia,
prepara volume e implanta via Portainer ou Docker. Preserve a chave em
atualizações e nunca a envie ao chat.

## Validação

Confirme login, persistência e execução de um workflow descartável. Teste
webhook apenas com dados não sensíveis e diferencie resposta pública de
execução interna.

## Riscos e limites

Um fluxo pesado pode bloquear outras execuções na variante sem fila.
Credenciais de integrações ficam sob proteção do n8n e dependem da chave de
criptografia. Backup deve cobrir banco e dados necessários.

## Diagnóstico

Interface indisponível aponta para réplica ou rota. Workflow parado pode ser
capacidade, credencial de integração ou nó específico. Use nomes genéricos e
erros sanitizados ao consultar o Assistente.
