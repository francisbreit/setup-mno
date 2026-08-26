---
{
  "schemaVersion": 1,
  "documentId": "infra-solution-patterns-architecture",
  "documentVersion": "1.0.0",
  "contentSHA256": "2805c267fbbee2d7448bdab804874cdc41132e1a29ba764c83dcde4c650b60ef",
  "documentType": "infrastructure",
  "title": "Padrões de deploy e microssistemas orientados a objetivos",
  "topicId": "solution-patterns",
  "setupVersion": "7.34.2",
  "architectures": ["amd64", "arm64"],
  "category": "architecture",
  "status": "reviewed",
  "updatedAt": "2026-08-03",
  "sourceType": "maintainer-authored",
  "risk": "medium",
  "language": "pt-BR",
  "tags": ["solution-patterns", "microssistemas", "deploy", "integracoes", "arquitetura", "objetivos"],
  "sources": [
    {
      "sourceId": "control-catalog-patterns",
      "title": "Catálogo canônico de setups e combos",
      "sourceType": "setup-mno",
      "location": "setupmno-control/catalog.json",
      "license": "project-internal",
      "verifiedAt": "2026-08-03"
    },
    {
      "sourceId": "blueprint-catalog-patterns",
      "title": "Catálogo canônico de Blueprints",
      "sourceType": "setup-mno",
      "location": "setupmno-knowledge/blueprints/blueprint-001-whatsapp-marketing-completo/blueprint.json",
      "license": "project-internal",
      "verifiedAt": "2026-08-03"
    }
  ],
  "homologation": {"verifiedAt": null, "verifiedPorts": [], "verifiedImages": []}
}
---
# Padrões de deploy e microssistemas orientados a objetivos

## Papel no Setup MNO

Este documento orienta o Assistente a transformar objetivos em arquiteturas
progressivas. Ele fornece padrões iniciais sem substituir a documentação de
cada setup nem declarar integrações como homologadas.

## Missão do Mestre de Deploys

O Assistente deve começar pelo resultado que o usuário quer obter, não por uma
lista aleatória de produtos. A recomendação deve reduzir complexidade,
explicitar alternativas e produzir um caminho incremental que também possa ser
auditado por um profissional de DevOps.

## Perguntas mínimas antes de recomendar

1. Qual dor, processo ou resultado precisa ser resolvido?
2. Quem utilizará a solução e qual volume inicial é esperado?
3. Quais sistemas já existem e precisam trocar dados?
4. Há dados pessoais, mensagens, pagamentos ou outros riscos especiais?
5. Qual disponibilidade, retenção e tolerância a perda são aceitáveis?
6. Quais recursos de CPU, RAM e disco estão realmente disponíveis?
7. O usuário prefere simplicidade inicial ou maior capacidade de escala?
8. Existe Blueprint aplicável ou será uma arquitetura sugerida?

Quando o usuário ainda não souber responder, o Assistente deve propor uma
opção inicial conservadora e explicar quais decisões podem ser adiadas.

## Método de arquitetura guiada

1. **Resultado:** reescrever a dor como resultado mensurável.
2. **Capacidades:** separar interface, automação, dados, canal, identidade,
   armazenamento, observabilidade e backup.
3. **Aplicações:** listar no máximo três candidatas por capacidade e explicar
   o motivo de cada uma.
4. **Setups:** mapear as aplicações escolhidas para entradas instaláveis,
   variantes ou combos existentes no catálogo.
5. **Blueprint:** priorizar um Blueprint quando seu objetivo, componentes e
   capacidade forem compatíveis.
6. **Capacidade e segurança:** comparar RAM e arquitetura, definir exposição,
   secrets, redes e persistência.
7. **Entrega incremental:** instalar e validar uma camada de cada vez, evitando
   um grande deploy sem diagnóstico intermediário.
8. **Operação:** definir saúde, logs, backup, atualização e rollback antes de
   considerar o microssistema concluído.

## Princípios

Começar pelo valor, reduzir o número de componentes, reutilizar serviços quando
o padrão do Setup permitir, preservar margem operacional e validar cada camada
antes da próxima. Alternativas devem ser comparadas por simplicidade, recursos,
manutenção e capacidade de recuperação, não por popularidade isolada.

## Padrões iniciais de solução

Os padrões abaixo são referências de composição. Eles não declaram que toda
integração está homologada; endpoints, autenticação e fluxo de dados devem ser
confirmados nos documentos dos setups e em teste controlado.

### Automação de processos de negócio

- **Capacidades:** orquestração, entrada por webhook ou agenda, persistência e
  tratamento de falhas.
- **Aplicações candidatas:** n8n ou Activepieces; PostgreSQL quando exigido
  pelo setup; Redis somente nas variantes com fila.
- **Setups candidatos:** `N8N V1 - SEM FILA (MAIN)` para simplicidade inicial,
  `N8N V2 - FILA (QUEUE)` para processamento desacoplado ou `ACTIVEPIECES` como
  alternativa visual.
- **Validação:** executar um fluxo pequeno e idempotente antes de importar
  automações complexas.

### Atendimento digital e WhatsApp

- **Capacidades:** canal, caixa de entrada humana, mensageria, armazenamento e
  automação.
- **Setups candidatos:** combos `CHATWOOTN + EVOLUTIONN 2.0 + RABBITMQ*` ou a
  variante com MinIO; n8n para orquestrações adicionais.
- **Blueprint relacionado:** WhatsApp Marketing Completo quando o objetivo
  incluir campanhas, automação e atendimento humano.
- **Validação:** usar números e destinatários de laboratório, medir duplicidade
  e testar transferência para atendimento humano.

### Marketing e jornada de leads

- **Capacidades:** cadastro, segmentação, campanhas, automação e canal.
- **Setups candidatos:** `MAUTIC 7 PADRÃO` ou `MAUTIC 7 WHATSAPP MKT`, n8n e um
  combo de atendimento quando a operação exigir caixa humana.
- **Risco:** consentimento, rate limit, duplicidade e proteção de dados devem
  ser tratados antes de uma campanha real.

### Ferramentas internas e operações no-code

- **Capacidades:** interface interna, dados, autenticação e automação.
- **Aplicações candidatas:** Appsmith, Budibase ou ToolJet para interface;
  Baserow ou NocoDB para dados acessíveis; n8n ou Activepieces para processos.
- **Validação:** começar por um único caso de uso, perfis com menor privilégio e
  uma base de teste antes de conectar dados de produção.

### Base de conhecimento com IA e RAG

- **Capacidades:** ingestão, extração, embeddings, banco vetorial, recuperação,
  modelo e interface.
- **Aplicações candidatas:** Dify, Flowise ou Langflow; Qdrant, Weaviate ou
  ChromaDB; Ollama/Open WebUI quando o servidor comportar IA local.
- **Blueprint relacionado:** Base de Conhecimento com IA e RAG.
- **Validação:** usar um conjunto pequeno de documentos sem dados sensíveis,
  perguntas de referência e citações verificáveis antes de ampliar a base.

### Observabilidade e disponibilidade

- **Capacidades:** métricas do host, métricas de serviços, disponibilidade
  externa, alertas e logs.
- **Setups candidatos:** Beszel para visão leve, Grafana/Prometheus para séries
  e painéis, Uptime Kuma para testes externos e Dozzle para inspeção de logs.
- **Blueprint relacionado:** Observabilidade e Monitoramento.
- **Validação:** simular uma degradação controlada e confirmar que o alerta
  identifica o serviço sem expor dados sensíveis.

### Gestão de projetos e colaboração

- **Capacidades:** projetos, tarefas, comunicação e automação.
- **Setups candidatos:** Plane, OpenProject ou Vikunja conforme a profundidade
  desejada; Mattermost para comunicação; n8n para eventos e notificações.
- **Validação:** configurar um projeto piloto, permissões por equipe e política
  de backup antes de importar a operação completa.

### Documentação e conhecimento de equipe

- **Capacidades:** autoria, organização, busca, controle de acesso e backup.
- **Setups candidatos:** BookStack para estrutura de livros, Wiki.js para wiki,
  Outline ou Docmost para experiência colaborativa.
- **Validação:** testar exportação e restauração, permissões e anexos antes de
  centralizar documentação crítica.

### CRM e automação comercial

- **Capacidades:** contatos, funil, atividades, integração de canal e tarefas
  automáticas.
- **Setups candidatos:** Krayin CRM, Twenty CRM ou Evolution CRM; n8n para
  automações; Chatwoot quando atendimento humano precisar ser centralizado.
- **Validação:** usar contatos fictícios, conferir deduplicação e registrar a
  origem de cada atualização.

### Servidor pequeno e serviços essenciais

- **Capacidades:** poucos serviços, baixa manutenção, monitoramento e backup.
- **Princípio:** selecionar setups leves, evitar duplicar bancos ou storage e
  preservar margem de RAM para o sistema e picos.
- **Blueprint relacionado:** Servidor Pequeno com Ferramentas Leves.
- **Validação:** comparar memória disponível com requisitos recomendados e
  instalar uma aplicação por vez.

## Como apresentar alternativas

Para cada recomendação, o Assistente deve separar:

- **aplicações candidatas**, que entregam capacidades;
- **setups instaláveis**, que são as unidades reais do catálogo;
- **Blueprint aplicável**, quando houver uma receita revisada;
- **conexões confirmadas** e **conexões ainda sugeridas**;
- **mínimo viável**, **opção equilibrada** e **opção escalável**, quando as
  evidências permitirem comparar recursos e complexidade.

Se não houver Blueprint, a resposta deve chamar o desenho de **arquitetura
sugerida** e oferecer a criação futura de um Blueprint, sem inventar arquivos,
workflows, vídeos ou links.

## Validação

Uma recomendação passa quando identifica o objetivo, separa aplicações de
setups, encontra ou descarta explicitamente um Blueprint, usa apenas nomes do
catálogo, declara conexões ainda sugeridas e inclui um teste ponta a ponta.

## Riscos e limites

Os padrões não confirmam endpoints, credenciais, versões de APIs nem
compatibilidade entre todos os componentes. Combinações aumentam consumo,
superfície de falha e responsabilidade de backup. O Assistente deve reduzir o
escopo ou pedir dados adicionais quando capacidade e requisitos não forem
suficientes.

### Critério de conclusão de um microssistema

Uma solução só está pronta quando cada componente possui estado saudável, o
fluxo ponta a ponta foi testado, falhas geram evidência útil, secrets não foram
expostos, backups podem ser restaurados e existe rollback documentado. Instalar
todos os containers não é suficiente para declarar o objetivo entregue.
