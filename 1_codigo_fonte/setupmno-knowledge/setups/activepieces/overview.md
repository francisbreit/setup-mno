---
{
  "schemaVersion": 1,
  "documentId": "setup-activepieces-overview",
  "documentVersion": "1.0.2",
  "contentSHA256": "b4c9183125e1b2fd66edc8299110a50b79173d55534b83429e73edee3a1954c7",
  "documentType": "setup",
  "title": "Activepieces no Setup MNO",
  "setupId": "activepieces",
  "setupVersion": "7.4.0",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-07-30",
  "sourceType": "setup-mno",
  "risk": "medium",
  "language": "pt-BR",
  "tags": ["activepieces", "automacao", "workflows"],
  "sources": [
    {
      "sourceId": "activepieces-installer",
      "title": "Instalador Activepieces",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/activepieces.sh",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    },
    {
      "sourceId": "activepieces-catalog",
      "title": "Entrada Activepieces no catálogo",
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
# Activepieces no Setup MNO

## Quando usar

Use para automações visuais entre aplicativos quando a equipe procura uma
alternativa open-source a serviços de integração. Para fluxos já padronizados
em n8n, compare conectores, governança e custo de migração antes de trocar.

## Arquitetura no Setup MNO

O instalador cria a aplicação em redes interna e externa, usa o PostgreSQL
base e mantém uma dependência Redis associada ao setup. Há persistência para o
cache da aplicação e exposição compatível com instalação tradicional ou
Cloudflare Tunnel.

## Pré-requisitos

Exige infraestrutura-base saudável, banco disponível, memória compatível com o
catálogo e domínio definido. O usuário escolhe criação editável no Portainer ou
implantação direta pelo Docker.

## Fluxo seguro

O Instalador Seguro coleta o domínio e a opção de deploy, prepara DNS ou túnel,
cria o banco lógico, gera segredos de aplicação e implanta a stack. Segredos
não devem ser copiados para o Assistente.

## Validação

Confirme réplicas saudáveis, acesso à interface e capacidade de salvar um
fluxo de teste sem erro de banco. Falhas de execução devem ser separadas de
falhas de acesso e de persistência.

## Riscos e limites

Automações sem limites podem consumir recursos ou chamar serviços externos em
excesso. Backup deve cobrir banco e dados persistentes. Uma troca de versão
precisa preservar chaves de criptografia geradas pelo instalador.

## Diagnóstico

Se a interface não abrir, verifique primeiro estado da réplica e rota. Se
abrir mas não salvar, investigue a base. Se o fluxo não executar, verifique a
dependência Redis e os logs pelo fluxo humano autorizado.
