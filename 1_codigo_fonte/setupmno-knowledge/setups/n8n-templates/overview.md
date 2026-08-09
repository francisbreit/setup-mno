---
{
  "schemaVersion": 1,
  "documentId": "setup-n8n-templates-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "bce6e066382bb7179d653a5a46d85b9ba9111d8dc979919f681e795f52167d71",
  "documentType": "setup",
  "title": "N8N Templates Free no Setup MNO",
  "setupId": "n8n-templates",
  "setupVersion": "7.7.48",
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
    "n8n",
    "templates",
    "workflows",
    "conteudo-nao-confiavel"
  ],
  "sources": [
    {
      "sourceId": "n8n-templates-installer",
      "title": "Instalador N8N Templates Free",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/n8n-workflows.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "n8n-templates-official",
      "title": "Biblioteca oficial de templates do n8n",
      "sourceType": "official-documentation",
      "location": "https://n8n.io/workflows/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "n8n-security",
      "title": "Documentação oficial de segurança do n8n",
      "sourceType": "official-documentation",
      "location": "https://docs.n8n.io/hosting/securing/overview/",
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
# N8N Templates Free no Setup MNO

## Quando usar

Use como biblioteca de exemplos para acelerar a criação de automações, nunca como coleção previamente aprovada. Quantidade de workflows não equivale a qualidade, segurança, licença compatível ou funcionamento.

## Arquitetura no Setup MNO

O instalador usa uma imagem customizada do Setup com navegador de workflows. Ela não é a galeria oficial do n8n e deve ser tratada como conteúdo de terceiros até cada template ser inspecionado.

## Pré-requisitos

O catálogo declara cerca de 8 GB de RAM. Essa entrada deve exibir alerta de aplicação pesada no instalador antes de ser homologada.

Exige recursos elevados conforme o catálogo, ambiente de teste, n8n compatível e inventário de credenciais e nós usados. Defina dono, finalidade e dados permitidos para cada fluxo importado.

## Fluxo seguro

Leia o JSON integral, remova credenciais, URLs internas, community nodes e código não compreendido. Importe primeiro em n8n isolado com credenciais fictícias e execução manual.

## Primeiro acesso e integrações

Pesquise por objetivo, selecione um único modelo e reconstrua as credenciais no destino. Nunca confie em tokens ou endpoints contidos no arquivo importado.

## Backup e atualização

Versione o JSON revisado e exporte o workflow ativo sem credenciais. A biblioteca pode mudar independentemente do n8n; preserve o artefato aprovado e um rollback desativado.

## Validação

Confirme nós, expressões, código, gatilhos, destinos, volume, idempotência, timeout e tratamento de erro. Só ative agenda ou webhook após revisão humana.

## Riscos e limites

Templates podem exfiltrar dados, apagar registros, gerar custos ou executar código. O rótulo “free” não prova origem, licença ou segurança.

## Diagnóstico

Separe erro do catálogo, importação, credencial, versão do nó e execução. Teste cada ramo com payload sintético e execução manual.
