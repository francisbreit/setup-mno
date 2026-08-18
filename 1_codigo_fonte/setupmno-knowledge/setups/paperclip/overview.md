---
{
  "schemaVersion": 1,
  "documentId": "setup-paperclip-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "5ab2cf56bc986404aea23ac183c9b668d7a4ebdea300acc4684eef061a3bdd34",
  "documentType": "setup",
  "title": "Paperclip no Setup MNO",
  "setupId": "paperclip",
  "setupVersion": "7.22.2",
  "architectures": [
    "amd64"
  ],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": [
    "paperclip",
    "ia",
    "agentes",
    "imagem-nao-oficial"
  ],
  "sources": [
    {
      "sourceId": "paperclip-installer",
      "title": "Instalador Paperclip",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/paperclip.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "paperclip-official",
      "title": "Repositório oficial do Paperclip",
      "sourceType": "official-documentation",
      "location": "https://github.com/paperclipai/paperclip",
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
# Paperclip no Setup MNO

## Quando usar

Use apenas para laboratório de coordenação e gestão de agentes. Não recomende como gestão documental comum: o projeto oficial atual é voltado a organizações de agentes.

## Arquitetura no Setup MNO

O instalador x86 usa uma imagem de terceiro cujo namespace não corresponde ao repositório oficial atual do Paperclip. Essa divergência de procedência bloqueia homologação e precisa ser resolvida antes de dados reais.

## Pré-requisitos

O catálogo declara cerca de 1 GB de RAM apenas em x86; agentes e banco podem exigir mais, e a procedência da imagem deve ser resolvida primeiro.

Exige Postgres, domínio HTTPS, segredo de autenticação, provedor de agentes e política de autonomia. Confirme identidade, licença e conteúdo da imagem antes de executar fora de ambiente descartável.

## Fluxo seguro

Mantenha agentes sem credenciais produtivas, shell privilegiado ou acesso ao Docker. Use empresa fictícia, metas reversíveis e aprovação humana por ação.

## Primeiro acesso e integrações

Crie organização e agentes de teste sem canais externos. Valide papéis, orçamento, pausa e auditoria antes de qualquer integração.

## Backup e atualização

Preserve banco e configuração sem tokens, registre digest da imagem e teste restauração. Não atualize por tag flutuante enquanto a procedência estiver divergente.

## Validação

Confirme arquitetura x86, autenticação, isolamento, pausa, trilha de ações e restauração. Compare a imagem instalada com o projeto oficial e bloqueie promoção se não houver correspondência verificável.

## Riscos e limites

Imagem de terceiro, autonomia e projeto recente formam risco crítico de supply chain. O nome semelhante não prova que a imagem implementa o repositório oficial.

## Diagnóstico

Separe imagem, aplicação, banco, provedor e agente. Preserve digest e logs sanitizados; não compartilhe segredos nem conteúdo das tarefas.
