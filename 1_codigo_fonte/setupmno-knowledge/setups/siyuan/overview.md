---
{
  "schemaVersion": 1,
  "documentId": "setup-siyuan-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "bd3af1df1daa924c83fa50656bcf7f73874aad8fcfb831ab48d4fc010e67ae76",
  "documentType": "setup",
  "title": "SiYuan no Setup MNO",
  "setupId": "siyuan",
  "setupVersion": "7.7.8",
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
    "siyuan",
    "pkm",
    "notas",
    "conhecimento"
  ],
  "sources": [
    {
      "sourceId": "siyuan-installer",
      "title": "Instalador SiYuan",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/siyuan.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "siyuan-official",
      "title": "Repositório oficial do SiYuan",
      "sourceType": "official-documentation",
      "location": "https://github.com/siyuan-note/siyuan",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "siyuan-docker",
      "title": "Guia oficial de Docker do SiYuan",
      "sourceType": "official-documentation",
      "location": "https://github.com/siyuan-note/siyuan/blob/master/README.md#docker-hosting",
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
# SiYuan no Setup MNO

## Quando usar

Use para gestão pessoal de conhecimento baseada em blocos, referências e trabalho offline. Avalie o modelo de sincronização e licenciamento antes de prometer colaboração ou sync específicos.

## Arquitetura no Setup MNO

O instalador executa a imagem do SiYuan com workspace persistente. O workspace contém notas, configuração e possivelmente anexos sensíveis.

## Pré-requisitos

O catálogo declara cerca de 512 MB de RAM; anexos, índices e bases grandes podem elevar CPU, memória e storage.

Exige domínio HTTPS, volume com permissões corretas, senha de acesso e política de backup. Dimensione storage por anexos e histórico, não apenas texto.

## Fluxo seguro

Proteja a interface, restrinja cadastro e nunca exponha o workspace como compartilhamento de arquivos. Conteúdo de notas e tokens não deve ser enviado ao Assistente.

## Primeiro acesso e integrações

Crie notebook fictício, teste blocos, exportação e upload. Habilite extensões ou sincronização somente após revisar dados que sairão do servidor.

## Backup e atualização

Preserve o workspace inteiro de forma consistente e cifrada. Teste restauração, exportação e abertura após atualização; registre a versão efetiva.

## Validação

Confirme login, persistência, anexos, busca, exportação e restore. Verifique que o volume mantém propriedade compatível após recriação.

## Riscos e limites

Base pessoal pode concentrar dados e segredos. Extensões, sync externo, tag flutuante e permissões incorretas ampliam o risco.

## Diagnóstico

Separe proxy, autenticação, workspace, permissão de volume, extensão e sincronização. Use notebook fictício.
