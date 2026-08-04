---
{
  "schemaVersion": 1,
  "documentId": "setup-wiki-js-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "72f961b161b780e5114794ba874f8c2f6e760e427c79cd35cf0a1a36feeecaa5",
  "documentType": "setup",
  "title": "Wiki.js no Setup MNO",
  "setupId": "wiki-js",
  "setupVersion": "7.7.16",
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
    "wiki-js",
    "wiki",
    "documentacao",
    "postgres"
  ],
  "sources": [
    {
      "sourceId": "wiki-js-installer",
      "title": "Instalador Wiki.js",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/wikijs.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "wikijs-docker",
      "title": "Instalação oficial Docker do Wiki.js",
      "sourceType": "official-documentation",
      "location": "https://docs.requarks.io/install/docker",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "wikijs-docs",
      "title": "Documentação oficial do Wiki.js",
      "sourceType": "official-documentation",
      "location": "https://docs.requarks.io/",
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
# Wiki.js no Setup MNO

## Quando usar

Use para documentação colaborativa com Markdown, autenticação e controle de acesso. Defina taxonomia, proprietários e revisão; uma wiki sem governança acumula conteúdo obsoleto.

## Arquitetura no Setup MNO

O instalador usa a imagem oficial e banco previsto pelo Setup. Conteúdo, usuários e configuração residem no banco; assets e integrações podem exigir persistência adicional.

## Pré-requisitos

O catálogo declara cerca de 1 GB de RAM; Postgres, busca, renderização e autenticação externa adicionam consumo.

Exige domínio HTTPS, Postgres, conta dedicada, email e provedores de autenticação opcionais. Planeje backup, busca e política de publicação.

## Fluxo seguro

Crie grupos de menor privilégio, mantenha páginas privadas por padrão e proteja integrações Git ou LDAP. Não envie páginas internas ou tokens ao Assistente.

## Primeiro acesso e integrações

Crie administrador, grupo restrito e página fictícia. Valide leitura, edição, histórico e busca antes de importar documentação.

## Backup e atualização

Preserve banco e configuração de integrações; teste restauração de páginas, usuários e histórico. Fixe versão e leia migrações.

## Validação

Confirme HTTPS, login, grupos, página privada, histórico, busca, backup e restore. Teste acesso anônimo.

## Riscos e limites

Documentação pode conter segredos e procedimentos sensíveis. Grupos incorretos, sync Git e tag flutuante ampliam exposição.

## Diagnóstico

Separe proxy, aplicação, banco, autenticação, busca e integração. Use página e repositório fictícios.
