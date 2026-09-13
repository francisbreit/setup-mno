---
{
  "schemaVersion": 1,
  "documentId": "setup-triliumnext-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "87dde41a272bdd3a3cc691cb890ce6286b2e507b05ac355fc6940425c70e38fd",
  "documentType": "setup",
  "title": "TriliumNext no Setup MNO",
  "setupId": "triliumnext",
  "setupVersion": "7.47.0",
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
    "triliumnext",
    "notas",
    "knowledge-base",
    "imagem-legada"
  ],
  "sources": [
    {
      "sourceId": "triliumnext-installer",
      "title": "Instalador TriliumNext",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/triliumnext.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "triliumnext-docs",
      "title": "Documentação oficial do TriliumNext",
      "sourceType": "official-documentation",
      "location": "https://docs.triliumnotes.org/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "triliumnext-docker",
      "title": "Imagem oficial atual do TriliumNext",
      "sourceType": "official-documentation",
      "location": "https://hub.docker.com/r/triliumnext/trilium",
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
# TriliumNext no Setup MNO

## Quando usar

Use para base pessoal hierárquica de notas, relações e automações internas. Scripts dentro das notas devem ser tratados como código, não como conteúdo inofensivo.

## Arquitetura no Setup MNO

O instalador referencia o namespace antigo da imagem TriliumNext, enquanto o projeto atual publica outro namespace. Essa divergência precisa ser validada antes de homologação.

## Pré-requisitos

O catálogo declara cerca de 256 MB de RAM; bases, anexos e scripts exigem medição antes de uso multiusuário.

Exige domínio HTTPS, volume persistente, senha forte e política de backup. Avalie anexos, scripts e compartilhamentos públicos.

## Fluxo seguro

Proteja a interface, desabilite compartilhamentos não necessários e revise scripts importados. Notas, tokens e anexos não devem ser enviados ao Assistente.

## Primeiro acesso e integrações

Crie árvore fictícia, teste busca, relação, exportação e anexo. Não importe backup real até comprovar versão e restauração.

## Backup e atualização

Preserve banco e anexos, use exportação complementar e teste restore. Migre de namespace antigo para imagem oficial fixada em ambiente isolado.

## Validação

Confirme imagem efetiva, login, persistência, exportação, backup e restauração. Teste que nota privada não possui link público.

## Riscos e limites

Notas podem conter segredos e scripts ativos. Imagem antiga, tag flutuante e importações não revisadas ampliam o risco.

## Diagnóstico

Separe imagem, proxy, autenticação, banco, anexo, script e importação. Use base fictícia.
