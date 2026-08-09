---
{
  "schemaVersion": 1,
  "documentId": "setup-focalboard-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "e9af376fb1e2398bab8a1fd5110361c8d3917841700275bd96abbd3d77f32161",
  "documentType": "setup",
  "title": "Focalboard no Setup MNO",
  "setupId": "focalboard",
  "setupVersion": "7.7.47",
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
    "focalboard",
    "kanban",
    "projetos",
    "descontinuado"
  ],
  "sources": [
    {
      "sourceId": "focalboard-installer",
      "title": "Instalador Focalboard",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/focalboard.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "focalboard-repo",
      "title": "Repositório oficial Focalboard",
      "sourceType": "official-documentation",
      "location": "https://github.com/mattermost-community/focalboard",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "focalboard-docker",
      "title": "Instalação Docker Focalboard",
      "sourceType": "official-documentation",
      "location": "https://www.focalboard.com/docs/personal-edition/docker/",
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
# Focalboard no Setup MNO

## Quando usar

Use somente para laboratório, migração ou continuidade consciente de quadros existentes. O repositório oficial declara que o Focalboard standalone não está mantido; não o recomende para nova produção sem aceite explícito.

## Arquitetura no Setup MNO

O catálogo oferece apenas amd64. O instalador usa `Focalboard na tag latest`, volume de dados, rota e limite de 1 GB. A edição Personal Server é descrita para uso pessoal/desenvolvimento.

## Pré-requisitos

Exige domínio, volume, plano de migração e aceite formal do risco de software sem manutenção. Avalie alternativas mantidas antes de criar novos dados.

## Fluxo seguro

Não exponha como serviço crítico. Restrinja acesso, mantenha rede e backup e não dependa de futuras correções de segurança. Evite plugins ou integrações não verificadas.

## Primeiro acesso e integrações

Use quadro fictício, teste contas, permissões, anexos e exportação. Confirme um caminho real de migração para outro sistema antes de adotar.

## Backup e atualização

Copie volume e exporte quadros em formato utilizável. Atualização não deve ser presumida; mantenha imagem conhecida e teste restauração. Rollback é restaurar o volume e a imagem registrados.

## Validação

Confirme que a imagem ainda inicia, login, quadro, persistência, exportação e restauração. Registre a ausência de manutenção como limitação visível.

## Riscos e limites

Projeto não mantido implica vulnerabilidades e incompatibilidades sem correção. `latest` pode desaparecer ou mudar, e a edição não é indicada como plataforma empresarial.

## Diagnóstico

Separe imagem indisponível, volume, banco interno, proxy e navegador. Não tente corrigir dados reais sem cópia imutável.
