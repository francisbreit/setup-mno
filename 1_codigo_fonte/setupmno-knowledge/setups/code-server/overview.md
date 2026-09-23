---
{
  "schemaVersion": 1,
  "documentId": "setup-code-server-overview",
  "documentVersion": "1.0.2",
  "contentSHA256": "e601ed8e4adeacee82f6d08a3a10252d426d7f5f338ee7daa18c7b9f005fe3bc",
  "documentType": "setup",
  "title": "Code Server no Setup MNO",
  "setupId": "code-server",
  "setupVersion": "7.48.20",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-07-30",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["code-server", "ide", "desenvolvimento"],
  "sources": [
    {
      "sourceId": "code-server-installer",
      "title": "Instalador Code Server",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/codeserver.sh",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    },
    {
      "sourceId": "code-server-catalog",
      "title": "Entrada Code Server no catálogo",
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
# Code Server no Setup MNO

## Quando usar

Use para oferecer um ambiente de desenvolvimento acessível pelo navegador.
Não use como terminal administrativo irrestrito nem como substituto do
Instalador Seguro.

## Arquitetura no Setup MNO

A aplicação mantém configuração e workspace em volume persistente, recebe
extensões de runtime definidas pelo setup e participa das redes interna e
externa.

## Pré-requisitos

Exige domínio, memória, armazenamento e política de quem pode editar código.
Projetos e chaves de acesso precisam de gestão própria, sem serem incorporados
à imagem ou ao Assistente.

## Fluxo seguro

O instalador coleta as senhas pelo Whiptail, confirma o modo de deploy, cria o
volume e publica a aplicação. Senhas administrativas nunca devem ser
repetidas, registradas ou enviadas ao chat.

## Validação

Confirme autenticação, abertura do workspace, criação de arquivo descartável e
persistência após nova sessão. Avalie extensões antes de instalar em ambiente
produtivo.

## Riscos e limites

Uma IDE remota pode executar código com o acesso concedido ao container.
Restrinja usuários, extensões e segredos presentes no workspace. Backup deve
cobrir o volume, mas excluir credenciais transitórias quando possível.

## Diagnóstico

Falha antes do login aponta para rota ou réplica. Falha no workspace aponta
para volume ou permissão. Nunca solicite arquivos de configuração contendo
tokens para diagnosticar pelo Assistente.
