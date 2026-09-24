---
{
  "schemaVersion": 1,
  "documentId": "setup-vikunja-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "3514a24f824a594e1b6896b838a2a691ec1fc6d64e6435843cc61bffbaea58ae",
  "documentType": "setup",
  "title": "Vikunja no Setup MNO",
  "setupId": "vikunja",
  "setupVersion": "7.48.26",
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
    "vikunja",
    "tarefas",
    "kanban",
    "sqlite"
  ],
  "sources": [
    {
      "sourceId": "vikunja-installer",
      "title": "Instalador Vikunja",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/vikunja.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "vikunja-install",
      "title": "Instalação oficial do Vikunja",
      "sourceType": "official-documentation",
      "location": "https://vikunja.io/docs/installing/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "vikunja-docker",
      "title": "Exemplo oficial Docker do Vikunja",
      "sourceType": "official-documentation",
      "location": "https://vikunja.io/docs/full-docker-example/",
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
# Vikunja no Setup MNO

## Quando usar

Use para tarefas, projetos e kanban auto-hospedados. Escolha SQLite para uso pequeno ou banco externo quando concorrência, backup e operação justificarem.

## Arquitetura no Setup MNO

O instalador usa a imagem oficial e prepara persistência com um helper de permissões conforme o script. URL pública e diretório de arquivos precisam corresponder ao domínio e ao volume.

## Pré-requisitos

O catálogo declara cerca de 256 MB de RAM; banco externo, anexos e usuários concorrentes devem ser medidos à parte.

Exige domínio HTTPS, storage gravável pelo usuário do container, política de cadastro e email opcional. Planeje banco e anexos conforme equipe e volume.

## Fluxo seguro

Desabilite cadastro aberto após criar os usuários, aplique papéis por projeto e mantenha SMTP fora do Assistente. Não publique anexos sem autorização.

## Primeiro acesso e integrações

Crie usuário e projeto fictícios, teste tarefa, anexo e compartilhamento. Ative email ou API somente após confirmar permissões.

## Backup e atualização

Preserve banco e diretório de arquivos juntos, registre versão e teste restore. Verifique permissões do volume após recriação.

## Validação

Confirme URL pública, login, cadastro, projeto, anexo, persistência, backup e restauração. Teste usuário sem acesso ao projeto.

## Riscos e limites

Links compartilhados e anexos podem expor dados. SQLite, permissões de volume e cadastro aberto precisam de operação consciente.

## Diagnóstico

Separe proxy, URL pública, autenticação, banco, arquivo e permissão. Use projeto e anexo fictícios.
