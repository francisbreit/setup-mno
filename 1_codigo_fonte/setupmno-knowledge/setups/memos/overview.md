---
{
  "schemaVersion": 1,
  "documentId": "setup-memos-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "f290c3ea866973898768255b31ca67d870cf75956ae6198b5551a4b2b110e7b4",
  "documentType": "setup",
  "title": "Memos no Setup MNO",
  "setupId": "memos",
  "setupVersion": "7.29.0",
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
    "memos",
    "notas",
    "markdown",
    "sqlite"
  ],
  "sources": [
    {
      "sourceId": "memos-installer",
      "title": "Instalador Memos",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/memos.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "memos-docker",
      "title": "Deploy oficial do Memos com Docker",
      "sourceType": "official-documentation",
      "location": "https://usememos.com/docs/deploy/docker",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "memos-backup",
      "title": "Backup e restauração oficiais do Memos",
      "sourceType": "official-documentation",
      "location": "https://usememos.com/docs/operations/backup-restore",
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
# Memos no Setup MNO

## Quando usar

Use para notas rápidas, diário de trabalho e base pessoal leve em Markdown. Não trate visibilidade pública como substituto de autorização para conteúdo confidencial.

## Arquitetura no Setup MNO

O instalador usa uma instância única do Memos e volume persistente. O script ainda referencia uma tag flutuante; a documentação oficial atual diferencia tags estáveis das orientadas a desenvolvimento.

## Pré-requisitos

O catálogo declara cerca de 64 MB de RAM para uso leve; banco externo, anexos e usuários concorrentes exigem nova medição.

Exige domínio HTTPS, storage, política de visibilidade e backup da base e dos ativos. Defina quem pode criar usuários e se webhooks privados serão permitidos.

## Fluxo seguro

Mantenha cadastro controlado, visibilidade privada por padrão e webhooks restritos. Segredos, notas pessoais e URLs internas não devem compor contexto do Assistente.

## Primeiro acesso e integrações

Crie o administrador, revise configuração da instância e publique apenas uma nota fictícia. Valide API, RSS e webhook separadamente antes de conectá-los a automações.

## Backup e atualização

Copie banco e ativos persistidos, registre a versão e teste restauração. Leia migrações e prefira versão estável ou fixada antes de atualizar.

## Validação

Confirme login, permissões, persistência, upload, exportação, backup e restauração. Verifique que conteúdo privado não aparece anonimamente.

## Riscos e limites

Notas podem conter dados pessoais e segredos. Tags flutuantes, cadastro aberto e webhooks permissivos ampliam exposição.

## Diagnóstico

Separe proxy, autenticação, visibilidade, banco, ativos e integrações. Reproduza com nota e arquivo fictícios.
