---
{
  "schemaVersion": 1,
  "documentId": "setup-stirling-pdf-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "e4ce1c63c9046258a20c88e1041ab758393effcebebfc5a79f3b3913ca8afeaa",
  "documentType": "setup",
  "title": "Stirling PDF no Setup MNO",
  "setupId": "stirling-pdf",
  "setupVersion": "7.4.1",
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
    "stirling-pdf",
    "pdf",
    "documentos",
    "imagem-legada"
  ],
  "sources": [
    {
      "sourceId": "stirling-pdf-installer",
      "title": "Instalador Stirling PDF",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/stirlingpdf.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "stirling-docs",
      "title": "Documentação oficial do Stirling PDF",
      "sourceType": "official-documentation",
      "location": "https://docs.stirlingpdf.com/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "stirling-github",
      "title": "Repositório oficial do Stirling PDF",
      "sourceType": "official-documentation",
      "location": "https://github.com/Stirling-Tools/Stirling-PDF",
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
# Stirling PDF no Setup MNO

## Quando usar

Use para manipulação local de PDFs quando documentos não podem ser enviados a serviços externos. Confirme se OCR, assinatura, redação e conversão atendem ao requisito real.

## Arquitetura no Setup MNO

O instalador referencia um namespace histórico de imagem diferente do namespace oficial atual. Como PDFs podem ser sensíveis, a procedência e a política de descarte precisam ser validadas antes da homologação.

## Pré-requisitos

O catálogo declara cerca de 1 GB de RAM, que pode ser insuficiente para OCR, LibreOffice, arquivos grandes ou conversões simultâneas.

Exige domínio HTTPS, CPU e memória conforme OCR e conversões, storage temporário e política de retenção. Fontes e idiomas adicionais podem aumentar recursos.

## Fluxo seguro

Habilite autenticação, limite tamanho e concorrência e mantenha processamento temporário. Não envie documentos, nomes ou metadados ao Assistente.

## Primeiro acesso e integrações

Use PDF sintético para testar união, conversão, OCR e remoção de temporários. APIs só devem ser liberadas com autenticação, cota e validação de arquivo.

## Backup e atualização

Preserve somente configuração necessária; arquivos de trabalho não devem virar backup permanente. Migre para imagem oficial fixada em teste isolado e mantenha rollback.

## Validação

Confirme imagem efetiva, autenticação, limites, processamento, limpeza e ausência de acesso anônimo. Teste arquivo malformado em ambiente controlado.

## Riscos e limites

Parsers de documentos recebem conteúdo hostil e podem consumir muitos recursos. Imagem histórica, tag flutuante e arquivos confidenciais formam risco crítico.

## Diagnóstico

Separe proxy, upload, parser, OCR, conversor, memória e limpeza. Use arquivo sintético e logs sem conteúdo documental.
