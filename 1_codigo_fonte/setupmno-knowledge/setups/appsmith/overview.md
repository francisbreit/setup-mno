---
{
  "schemaVersion": 1,
  "documentId": "setup-appsmith-overview",
  "documentVersion": "1.0.2",
  "contentSHA256": "1dd7d7e3315f5fb6af2378e9b739669d558bb52f2f70b4df7fe4e5359f9ea7fd",
  "documentType": "setup",
  "title": "Appsmith no Setup MNO",
  "setupId": "appsmith",
  "setupVersion": "7.14.3",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-07-30",
  "sourceType": "setup-mno",
  "risk": "medium",
  "language": "pt-BR",
  "tags": ["appsmith", "low-code", "dashboards"],
  "sources": [
    {
      "sourceId": "appsmith-installer",
      "title": "Instalador Appsmith",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/appsmith.sh",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    },
    {
      "sourceId": "appsmith-catalog",
      "title": "Entrada Appsmith no catálogo",
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
# Appsmith no Setup MNO

## Quando usar

Use para painéis administrativos e ferramentas internas conectadas a bancos e
APIs. Para portais públicos ou aplicações com requisitos específicos de
produto, avalie uma arquitetura dedicada.

## Arquitetura no Setup MNO

O setup implanta uma aplicação com volume persistente próprio nas redes interna
e externa. A rota pública é adicionada no modo tradicional; no modo de túnel,
o ingresso é administrado pelo fluxo Cloudflare.

## Pré-requisitos

Exige infraestrutura-base saudável, domínio e memória compatível com o
catálogo. Antes de conectar fontes externas, defina responsáveis e permissões
de menor privilégio.

## Fluxo seguro

O instalador coleta o domínio e a opção Portainer ou Docker, prepara DNS ou
túnel, cria o volume e implanta a stack. Credenciais de fontes de dados são
configuradas na própria aplicação, não no chat.

## Validação

Confirme réplica saudável, acesso à interface, persistência após reinício
controlado e conexão a uma fonte de teste. Não use dados produtivos no primeiro
smoke test.

## Riscos e limites

Um painel pode concentrar acesso a várias bases. Permissões excessivas
transformam uma falha no Appsmith em impacto amplo. Proteja contas
administrativas e inclua o volume no plano de backup.

## Diagnóstico

Falha de acesso aponta primeiro para réplica e rota. Erro ao carregar dados
aponta para credencial, rede ou permissão da fonte. O Assistente deve trabalhar
com o tipo do erro, nunca com a credencial usada.
