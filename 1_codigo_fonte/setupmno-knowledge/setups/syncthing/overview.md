---
{
  "schemaVersion": 1,
  "documentId": "setup-syncthing-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "2b654d12f3cfab2db13b93c84ec3ff7cdaed6e99d8d8252376316afa070f9ccb",
  "documentType": "setup",
  "title": "Syncthing no Setup MNO",
  "setupId": "syncthing",
  "setupVersion": "7.2.12",
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
    "syncthing",
    "arquivos",
    "p2p",
    "sincronizacao"
  ],
  "sources": [
    {
      "sourceId": "syncthing-installer",
      "title": "Instalador Syncthing",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/syncthing.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "syncthing-docs",
      "title": "Documentação oficial do Syncthing",
      "sourceType": "official-documentation",
      "location": "https://docs.syncthing.net/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "syncthing-image",
      "title": "Imagem Docker do Syncthing mantida pelo projeto",
      "sourceType": "official-documentation",
      "location": "https://hub.docker.com/r/syncthing/syncthing/",
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
# Syncthing no Setup MNO

## Quando usar

Use para sincronização contínua P2P entre dispositivos controlados. Sincronização não é backup: exclusões e corrupção podem se propagar para todos os pares.

## Arquitetura no Setup MNO

O instalador usa uma imagem da LinuxServer, enquanto o projeto Syncthing também publica sua própria imagem. Volumes, identidade do dispositivo e interface de administração exigem proteção.

## Pré-requisitos

O catálogo declara cerca de 100 MB de RAM; muitos arquivos, watchers e indexação inicial podem elevar esse consumo.

Exige storage, política de pastas, Device IDs autorizados, versionamento de arquivos e backup independente. Planeje conectividade, relay e descoberta conforme privacidade.

## Fluxo seguro

Proteja a GUI, aceite pares manualmente e comece com pasta sintética. Não sincronize secrets, bancos ativos ou diretórios do sistema sem avaliação específica.

## Primeiro acesso e integrações

Troque a senha da GUI, adicione um único dispositivo de teste e valide conflitos, exclusões e versionamento. Confirme os caminhos antes de habilitar envio e recebimento.

## Backup e atualização

Mantenha backup offline separado e preserve configuração e certificados do dispositivo. Atualize um nó por vez e teste reconexão e compatibilidade.

## Validação

Confirme autenticação, Device ID, pasta correta, persistência, conflito, exclusão e restauração pelo backup independente. Teste reinício controlado.

## Riscos e limites

Erro de caminho ou exclusão se replica rapidamente. Acesso à GUI, permissões amplas e confusão entre sync e backup tornam o risco crítico.

## Diagnóstico

Separe descoberta, relay, conexão, autenticação, pasta, permissão e conflito. Use arquivos sintéticos e compare hashes.
