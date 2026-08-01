---
{
  "schemaVersion": 1,
  "documentId": "setup-budibase-overview",
  "documentVersion": "1.0.2",
  "contentSHA256": "97ad73be8eb61e9751298d9d06a1cc699586c3fd16fb09673c19e14caefa36ab",
  "documentType": "setup",
  "title": "Budibase no Setup MNO",
  "setupId": "budibase",
  "setupVersion": "7.0.1",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-07-30",
  "sourceType": "setup-mno",
  "risk": "medium",
  "language": "pt-BR",
  "tags": ["budibase", "low-code", "internal-tools"],
  "sources": [
    {
      "sourceId": "budibase-installer",
      "title": "Instalador Budibase",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/budibase.sh",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    },
    {
      "sourceId": "budibase-catalog",
      "title": "Entrada Budibase no catálogo",
      "sourceType": "setup-mno",
      "location": "setupmno-control/catalog.json",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    }
  ],
  "homologation": {
    "verifiedAt": null,
    "verifiedPorts": [],
    "verifiedImages": []
  }
}
---
# Budibase no Setup MNO

## Quando usar

Use para construir ferramentas internas e fluxos de trabalho low-code com
dados e formulários. Compare Appsmith quando a prioridade for dashboards
conectados e Baserow quando a prioridade for uma experiência de planilha.

## Arquitetura no Setup MNO

O instalador usa a distribuição integrada do Budibase, com serviços internos
encapsulados pela aplicação e volume persistente próprio. A stack participa
das redes interna e externa e recebe uma única rota.

## Pré-requisitos

Exige domínio, infraestrutura-base saudável e capacidade coerente com o
catálogo. Defina política de contas, fontes de dados e backup antes de colocar
uma ferramenta interna em produção.

## Fluxo seguro

O Instalador Seguro gera os segredos internos, cria volume, configura a
publicação e permite deploy via Portainer ou Docker. Os valores gerados
permanecem fora do conhecimento e da LLM.

## Validação

Confirme réplica, acesso, criação de uma aplicação de teste e persistência. Uma
interface disponível não prova que os componentes internos de dados estão
saudáveis.

## Riscos e limites

A distribuição integrada simplifica instalação, mas concentra vários
componentes na mesma unidade operacional. Monitore memória, faça backup do
volume e preserve os segredos em atualizações.

## Diagnóstico

Se a interface falhar, comece por réplica e rota. Se apenas edição ou dados
falharem, investigue o estado interno pelo procedimento autorizado, sem
solicitar segredos ao usuário.
