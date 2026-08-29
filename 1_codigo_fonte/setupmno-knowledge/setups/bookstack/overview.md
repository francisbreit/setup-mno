---
{
  "schemaVersion": 1,
  "documentId": "setup-bookstack-overview",
  "documentVersion": "1.0.2",
  "contentSHA256": "780b1048e00efbec77f596fea63a3412e2e7b700de013b90724fd8cd73793e2e",
  "documentType": "setup",
  "title": "BookStack no Setup MNO",
  "setupId": "bookstack",
  "setupVersion": "7.40.0",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-07-30",
  "sourceType": "setup-mno",
  "risk": "medium",
  "language": "pt-BR",
  "tags": ["bookstack", "wiki", "documentacao"],
  "sources": [
    {
      "sourceId": "bookstack-installer",
      "title": "Instalador BookStack",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/bookstack.sh",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    },
    {
      "sourceId": "bookstack-catalog",
      "title": "Entrada BookStack no catálogo",
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
# BookStack no Setup MNO

## Quando usar

Use para documentação organizada em livros, capítulos e páginas, com
colaboração e permissões. Para notas pessoais sem estrutura editorial, uma
ferramenta mais simples pode exigir menos administração.

## Arquitetura no Setup MNO

O setup cria a aplicação com volume de configuração e usa uma base MySQL
preparada pelo próprio fluxo quando necessário. Aplicação e banco compartilham
a rede interna; somente a interface recebe publicação.

## Pré-requisitos

Exige infraestrutura-base saudável, domínio, memória e armazenamento para
anexos. A decisão de backup deve incluir tanto o banco quanto o volume da
aplicação.

## Fluxo seguro

O instalador coleta domínio e modo de deploy, garante a base, cria o banco
lógico, gera a chave interna, prepara volume e implanta. Nenhuma chave gerada
deve ser reproduzida no Assistente.

## Validação

Confirme acesso, criação de página, upload de arquivo de teste e leitura após
nova sessão. Valide também a conexão com a base antes de considerar a
instalação concluída.

## Riscos e limites

Restaurar somente banco ou somente arquivos cria inconsistência. Atualizações
precisam preservar chave de aplicação, dados e anexos. Controle permissões para
evitar exposição documental.

## Diagnóstico

Erro global de inicialização pode indicar base indisponível. Página acessível
sem anexos aponta para persistência. Preserve logs no fluxo autorizado e nunca
cole conteúdo documental do cliente no chat.
