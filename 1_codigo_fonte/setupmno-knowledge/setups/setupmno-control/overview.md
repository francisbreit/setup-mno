---
{
  "schemaVersion": 1,
  "documentId": "setup-setupmno-control-overview",
  "documentVersion": "1.0.2",
  "contentSHA256": "81494c8e951dffb7d06f8cd0fd1a562742dd91a4a00ed9dae98f78f84a3a4a14",
  "documentType": "setup",
  "title": "Setup MNO Control Center",
  "setupId": "setupmno-control",
  "setupVersion": "4.96.0",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-07-30",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": ["setupmno-control", "devops", "assistente"],
  "sources": [
    {
      "sourceId": "setupmno-control-installer",
      "title": "Instalador do Control Center",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/setupmno_control.sh",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    },
    {
      "sourceId": "setupmno-control-readme",
      "title": "Arquitetura do Control Center",
      "sourceType": "setup-mno",
      "location": "setupmno-control/README.md",
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
# Setup MNO Control Center

## Quando usar

Use para visualizar estado sanitizado do ambiente, consultar o Assistente e
acessar o Instalador Seguro autenticado. O painel não substitui Portainer nem
oferece administração Docker genérica.

## Arquitetura no Setup MNO

Painel, agente de leitura, terminal e conector do Assistente são stacks
separadas. Somente agente e terminal recebem acessos estritamente necessários.
O painel permanece sem socket Docker e sem mount do host.

## Pré-requisitos

Exige infraestrutura-base, domínio, memória mínima do modo escolhido e pacote
runtime consistente. OpenAI e Ollama são opcionais; diagnóstico básico deve
permanecer disponível.

## Fluxo seguro

O instalador constrói imagens no Whiptail, executa gates de compatibilidade,
cria secrets e implanta stacks isoladas. O terminal expõe apenas o instalador
original após autenticação e limita sessões concorrentes.

## Validação

Confirme autenticação, versões separadas, catálogo runtime, métricas, terminal
desktop e touch, Assistente básico e fallback. Conectores opcionais exigem
testes válidos e inválidos sem vazamento no payload.

## Riscos e limites

Adicionar shell ou comando Docker ao Assistente quebra a arquitetura. Estado
runtime inconsistente exige fallback marcado como desatualizado. Nenhuma ação
real pode ser executada em nome do usuário durante o Beta.

## Diagnóstico

Identifique primeiro qual stack falhou. Painel sem dados difere de terminal
indisponível e provedor de IA fora do ar. O fallback local deve permanecer
visível e registrar a ocorrência na auditoria.
