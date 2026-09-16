---
{
  "schemaVersion": 1,
  "documentId": "setup-photoprism-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "6694ab6df16fb98afac56897920072dfc4c3ee36ac17a9fa50e7ed7785547782",
  "documentType": "setup",
  "title": "PhotoPrism no Setup MNO",
  "setupId": "photoprism",
  "setupVersion": "7.48.5",
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
    "photoprism",
    "fotos",
    "midia",
    "sqlite"
  ],
  "sources": [
    {
      "sourceId": "photoprism-installer",
      "title": "Instalador PhotoPrism",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/photoprism.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "photoprism-compose",
      "title": "Docker Compose oficial PhotoPrism",
      "sourceType": "official-documentation",
      "location": "https://docs.photoprism.app/getting-started/docker-compose/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "photoprism-backup",
      "title": "Backup oficial PhotoPrism",
      "sourceType": "official-documentation",
      "location": "https://docs.photoprism.app/user-guide/backups/",
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
# PhotoPrism no Setup MNO

## Quando usar

Use para organizar, indexar e pesquisar acervos de fotos privados. Reconhecimento e metadados aumentam sensibilidade; não exponha originais nem use public mode sem decisão explícita.

## Arquitetura no Setup MNO

O instalador usa `PhotoPrism na tag latest`, Redis dedicado, volumes e porta host, com limite de 2 GB; não há MariaDB explícito, portanto tende a SQLite. O oficial recomenda pelo menos 4 GB de swap e evitar limite rígido durante indexação.

## Pré-requisitos

Exige storage para originais e thumbnails, backup externo, senha admin forte e capacidade de CPU/RAM/disco. Para concorrência, MariaDB é preferível a SQLite.

## Fluxo seguro

Não publique porta direta, mantenha autenticação, limite mounts e considere originals read-only. Proteja geolocalização, rostos, senhas e WebDAV.

## Primeiro acesso e integrações

Use pequena biblioteca sintética, valide importação, indexação, busca, álbum, download e exclusão. Meça pico de memória e CPU com arquivos representativos.

## Backup e atualização

O oficial exige originais, dump do índice e recomenda storage/configuração. Gere backup pelo CLI e copie originais/storage; teste restore antes de update.

## Validação

Confirme login, volumes, indexação, thumbnails, busca, backup/restore e persistência. Verifique swap e ausência de OOM durante RAW/vídeo.

## Riscos e limites

Fotos e metadados são altamente sensíveis. 2 GB com limite rígido diverge da orientação oficial; SQLite, porta host e `latest` elevam risco.

## Diagnóstico

Separe storage, índice/SQLite, Redis, codecs, memória, permissões e proxy. Use mídias sintéticas sem rostos reais.
