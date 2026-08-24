---
{
  "schemaVersion": 1,
  "documentId": "infra-ecosystem-architecture",
  "documentVersion": "1.0.0",
  "contentSHA256": "934bb4be372a0dd11ac8648dfe56519d32b266a6f2f52e62d1f3b6f497fa1526",
  "documentType": "infrastructure",
  "title": "Ontologia e inventários do ecossistema Setup MNO",
  "topicId": "ecosystem",
  "setupVersion": "7.32.2",
  "architectures": ["amd64", "arm64"],
  "category": "terminology",
  "status": "reviewed",
  "updatedAt": "2026-08-03",
  "sourceType": "setup-mno",
  "risk": "low",
  "language": "pt-BR",
  "tags": ["ecosystem", "inventario", "aplicacoes", "setups", "blueprints", "microssistemas"],
  "sources": [
    {
      "sourceId": "control-catalog",
      "title": "Catálogo canônico do Control Center",
      "sourceType": "setup-mno",
      "location": "setupmno-control/catalog.json",
      "license": "project-internal",
      "verifiedAt": "2026-08-03"
    },
    {
      "sourceId": "knowledge-setup-registry",
      "title": "Registro canônico de setups",
      "sourceType": "setup-mno",
      "location": "setupmno-knowledge/registry/setups.json",
      "license": "project-internal",
      "verifiedAt": "2026-08-03"
    },
    {
      "sourceId": "blueprint-schema",
      "title": "Contrato canônico de Blueprints",
      "sourceType": "setup-mno",
      "location": "setupmno-knowledge/schema/blueprint.schema.json",
      "license": "project-internal",
      "verifiedAt": "2026-08-03"
    }
  ],
  "homologation": {"verifiedAt": null, "verifiedPorts": [], "verifiedImages": []}
}
---
# Ontologia e inventários do ecossistema Setup MNO

## Papel no Setup MNO

Este documento é a autoridade semântica usada para distinguir o que o usuário
quer conhecer, instalar, combinar ou construir. Ele impede que inventários de
naturezas diferentes sejam tratados como equivalentes.

## Modelo mental

O Setup MNO separa quatro níveis para evitar recomendações e contagens
enganosas. Eles se relacionam, mas não são sinônimos.

1. **Aplicação ou ferramenta** é um produto de software que entrega uma
   capacidade funcional ou operacional. n8n, PostgreSQL, Chatwoot e Beszel são
   exemplos de aplicações. Uma aplicação pode aparecer em várias versões,
   variantes, combos e Blueprints.
2. **Setup** é uma unidade instalável do catálogo. Um setup pode representar
   uma aplicação individual, uma variante preparada pelo mantenedor, um banco
   de dados, um utilitário ou um combo com múltiplas aplicações e dependências.
3. **Blueprint** é uma planta baixa ou receita digital orientada a um
   resultado. Ele referencia setups, determina ordem, configurações,
   integrações, validações, materiais de apoio, segurança e rollback.
4. **Microssistema** é a solução funcional obtida ao aplicar um Blueprint ou
   uma arquitetura guiada a uma dor concreta. É o resultado entregue ao
   usuário, e não uma nova entrada instalável por definição.

## Relações entre os níveis

Uma aplicação pode possuir mais de um setup por causa de versão, arquitetura,
modo de execução ou personalização. Um setup combo pode conter várias
aplicações. Um Blueprint pode usar vários setups e acrescentar trabalho que um
instalador isolado não representa: criação de contas, parâmetros, importação de
workflows, configuração de webhooks, validação ponta a ponta, documentação e
plano de recuperação.

Por isso, uma entrada de setup não equivale a uma aplicação única, e um conjunto
de setups não equivale automaticamente a um Blueprint.

## Autoridade das contagens

- `canonicalSetupEntries` e `catalogEntries` contam **setups**, nunca produtos
  únicos nem Blueprints.
- `blueprintEntries` conta **Blueprints**. `blueprintBetaEntries` e
  `blueprintHomologatedEntries` detalham seu estágio.
- `installedApps` descreve aplicações ou stacks observadas no servidor naquele
  momento; `services` descreve serviços Docker. Essas contagens também não são
  intercambiáveis.
- O total de aplicações únicas só pode ser informado quando existir um registro
  normalizado de produtos e relações entre produto, variante e componente. O
  estado `applicationInventoryStatus=not-normalized` proíbe usar o total de
  setups como substituto.
- `setupTypeEntries` classifica setups como Individual, Combo, Utilitário ou
  Banco de Dados. Essa classificação ajuda a explicar o catálogo, mas não
  elimina duplicidades de produtos.

## Política de resposta do Assistente

Ao responder inventários, o Assistente deve nomear a entidade contada, a fonte
da contagem e o momento a que ela se refere. Se a pergunta for ambígua, deve
explicar a diferença antes de apresentar números.

Ao recomendar uma solução, deve percorrer os níveis nesta ordem:

1. entender a dor e o resultado desejado;
2. decompor o resultado em capacidades;
3. identificar aplicações capazes de entregar cada capacidade;
4. escolher setups instaláveis compatíveis com arquitetura e recursos;
5. procurar um Blueprint aplicável;
6. se não houver Blueprint, apresentar a combinação como arquitetura sugerida,
   nunca como integração homologada;
7. definir validação incremental, observabilidade e rollback.

## Princípios

Toda resposta começa pela entidade correta e preserva a origem do número. O
Assistente prefere um fato determinístico a uma aproximação da LLM, separa
produto de instalador e só promove uma arquitetura sugerida quando existirem
evidências próprias de integração.

## Validação

Os gates devem perguntar separadamente quantos setups, Blueprints, aplicações
únicas, aplicações instaladas e serviços existem. É falha crítica responder
“155 Blueprints” ou “155 aplicações únicas”, porque 155 é exclusivamente o
inventário atual de setups.

Perguntas sobre a diferença entre os conceitos devem recuperar este documento
e mencionar os quatro níveis sem fundi-los.

## Riscos e limites

Um instalador homologado confirma a instalação testada pelo mantenedor. Isso
não transforma automaticamente toda combinação entre aplicações em integração
validada. Um guia Blueprint Beta pode orientar execução manual, mas exige
confirmação humana e testes ponta a ponta. Somente evidências próprias podem
promover uma integração ou Blueprint a homologado.

O Assistente é consultivo: ele pode explicar, comparar, dimensionar e desenhar
o caminho, mas ações reais continuam no Instalador Seguro.
