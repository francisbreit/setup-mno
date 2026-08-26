---
{
  "schemaVersion": 1,
  "documentId": "setup-filebrowser-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "c9976aefee3066e287b4d5df7e223e980433dcdfc7340e84b484e33bf0ef062f",
  "documentType": "setup",
  "title": "File Browser no Setup MNO",
  "setupId": "filebrowser",
  "setupVersion": "7.34.1",
  "architectures": [
    "amd64",
    "arm64"
  ],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": [
    "filebrowser",
    "arquivos",
    "storage",
    "administracao"
  ],
  "sources": [
    {
      "sourceId": "filebrowser-installer",
      "title": "Instalador File Browser",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/filebrowser.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "filebrowser-install",
      "title": "Instalação oficial File Browser",
      "sourceType": "official-documentation",
      "location": "https://filebrowser.org/installation",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "filebrowser-config",
      "title": "Configuração oficial File Browser",
      "sourceType": "official-documentation",
      "location": "https://filebrowser.org/configuration",
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
# File Browser no Setup MNO

## Quando usar

Use como interface administrativa para arquivos de um volume explicitamente delimitado. Não exponha a raiz do host, diretórios do Setup MNO, secrets ou dados de outras aplicações.

## Arquitetura no Setup MNO

O instalador usa `File Browser na tag latest`, publica uma porta no host, monta volume persistente e define `FB_NOAUTH=true`. Embora o catálogo estime 64 MB, o estado sem autenticação é bloqueante para qualquer exposição pública.

## Pré-requisitos

Exige diretório alvo específico, política de permissões, usuário sem privilégios, autenticação e gate de conflito da porta. Defina quem pode ler, gravar, apagar e compartilhar.

## Fluxo seguro

Não use o fluxo atual em produção enquanto `FB_NOAUTH=true`. Habilite autenticação, limite o mount ao diretório necessário, elimine porta pública quando houver proxy seguro e aplique menor privilégio.

## Primeiro acesso e integrações

Com diretório temporário, teste login, upload, download, renomeação e exclusão por usuário não privilegiado. Confirme que caminhos fora do escopo não são visíveis.

## Backup e atualização

File Browser não substitui backup. Preserve os arquivos e sua configuração/banco de usuários separadamente. Antes de atualizar, fixe tag, copie configuração e teste restore.

## Validação

Confirme autenticação obrigatória, TLS, escopo do mount, permissões, persistência, limite de upload e ausência de symlink escapando do diretório autorizado.

## Riscos e limites

Sem autenticação e com porta publicada, qualquer visitante pode manipular arquivos do volume. Um mount amplo pode causar perda ou vazamento; `latest` dificulta rollback.

## Diagnóstico

Separe proxy, autenticação, UID/GID, permissões, volume e limites. Use somente arquivos descartáveis e nunca forneça caminhos reais ao Assistente.
