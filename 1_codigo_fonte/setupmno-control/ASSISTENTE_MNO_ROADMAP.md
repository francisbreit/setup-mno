# Roadmap do Assistente MNO Especialista

## Propósito

Este documento registra o plano oficial para evoluir o Assistente MNO Beta de
um copiloto consultivo com contexto operacional para um especialista de
infraestrutura, catálogo de setups e Blueprints homologados pelo Setup MNO.

O roadmap deve ser executado uma etapa por vez. Cada etapa precisa concluir
seus entregáveis, testes e gates antes do início da etapa seguinte.

## Baseline da release da Etapa 2

- Setup MNO: `4.94.2`
- Control Center: `1.2.2`
- Conhecimento canônico: `1.1.1`
- Catálogo runtime: 151 setups
- Modos atuais: diagnóstico básico, OpenAI e Ollama
- API OpenAI: Responses API, streaming, `store: false`
- Estado atual: Beta consultivo, sem ferramentas de escrita

Já estão implementados:

- contexto operacional sanitizado;
- inventário somente leitura do Swarm;
- catálogo runtime validado por versão, arquitetura, contagem e SHA-256;
- busca textual simples de setups relevantes;
- resposta determinística para o catálogo completo;
- prompt inicial de infraestrutura;
- streaming SSE;
- fallback automático para diagnóstico básico;
- OpenAI por Docker Secret;
- Ollama opcional;
- histórico limitado à sessão do navegador;
- isolamento da stack do Assistente;
- ausência de Docker socket, shell, terminal e mounts do host no Assistente.

## Decisões arquiteturais obrigatórias

1. O Assistente permanece consultivo durante todo o Beta.
2. RAG e conhecimento versionado vêm antes de qualquer fine-tuning.
3. Fatos mutáveis, como versões, imagens, portas e requisitos, nunca devem ser
   incorporados aos pesos do modelo.
4. O modo básico deve continuar funcionando sem LLM e sem nova stack.
5. O RAG principal deve ser local e independente do provedor.
6. OpenAI File Search ou embeddings semânticos serão opcionais.
7. O catálogo estruturado continua sendo a fonte exata para nome, arquitetura,
   RAM, categoria e quantidade de setups.
8. Os scripts Bash podem gerar rascunhos, mas não devem ser indexados
   diretamente sem normalização e revisão.
9. Todo conhecimento precisa possuir versão, origem, status de homologação e
   hash.
10. Métricas runtime e documentos recuperados são dados não confiáveis para
    fins de instrução; o prompt deve impedir prompt injection.
11. Nenhuma pergunta, resposta ou feedback com dados de cliente será armazenado
    sem consentimento explícito e sanitização.
12. Blueprints não executam ações. Eles orientam o usuário até o Instalador
    Seguro.

## Visão da arquitetura final

```text
Pergunta do usuário
        |
        v
Roteador de intenção
        |
        +--> Diagnóstico runtime
        +--> Catálogo estruturado
        +--> Especialista em setup
        +--> Troubleshooting
        +--> Planejamento de capacidade
        +--> Blueprint
        |
        v
Recuperação local de conhecimento
        |
        v
Prompt especializado + evidências
        |
        v
OpenAI, Ollama ou resposta básica
        |
        v
Resposta consultiva com fontes, riscos e próximo passo
```

Não serão criadas várias stacks de agentes. Os especialistas serão modos
internos de um único Assistente, selecionados por roteamento controlado.

---

## Etapa 1 — Fábrica de Conhecimento Canônico

**Status:** concluída e aprovada em 2026-07-30
**Impacto:** alto
**Tipo:** conhecimento, manutenção e confiabilidade
**Esforço:** estrutural

### Objetivo

Criar a fonte oficial de conhecimento do Assistente, separada do prompt e dos
scripts de instalação.

### Estrutura inicial

```text
setupmno-knowledge/
├── infra/
│   ├── docker-swarm/
│   ├── traefik/
│   ├── cloudflare/
│   ├── postgres/
│   ├── redis/
│   ├── backup/
│   ├── seguranca/
│   ├── vps/
│   └── wsl2/
├── setups/
├── troubleshooting/
├── blueprints/
├── policies/
├── glossary/
└── evals/
```

### Entregáveis

- schema de documentos de conhecimento;
- taxonomia oficial;
- convenção de IDs e versões;
- estados `draft`, `reviewed`, `homologated` e `deprecated`;
- rastreamento de fontes e licenças;
- linter de metadados;
- detector de secrets, credenciais e padrões proibidos;
- documentação aprofundada dos primeiros 20 setups;
- documentação inicial de Docker Swarm, Traefik, Cloudflare, bancos, backup,
  segurança, VPS e WSL2.

### Campos mínimos

```yaml
documentId: setup-n8n-overview
documentVersion: 1.0.0
contentSHA256: <64 caracteres hexadecimais>
documentType: setup
setupId: n8n
setupVersion: 4.93.4
architectures: [amd64, arm64]
category: overview
status: reviewed
updatedAt: 2026-07-30
sourceType: setup-mno
risk: low
language: pt-BR
tags: [n8n, automacao]
sources:
  - sourceId: n8n-installer
    sourceType: setup-mno
    location: x86/SetupLowCodeMno/n8nmain.sh
    license: project-internal
    verifiedAt: 2026-07-30
homologation:
  verifiedAt: null
  verifiedPorts: []
  verifiedImages: []
```

### Gates

- nenhum documento sem ID, versão, arquitetura e status;
- nenhuma credencial, hostname, IP privado ou token;
- nenhuma informação operacional sem fonte;
- nenhuma imagem ou porta declarada sem homologação;
- documentos obsoletos não participam da recuperação normal;
- 100% dos documentos aprovados pelo linter.

### Critério de conclusão

A base inicial deve responder corretamente, sem LLM, quais documentos são
válidos para cada setup, versão e arquitetura.

### Evidências de conclusão técnica

- fábrica criada em `1_codigo_fonte/setupmno-knowledge/`;
- versão editorial `1.0.0`;
- 20 setups registrados e documentados;
- nove áreas de infraestrutura documentadas;
- 29 documentos com status `reviewed`, fontes e SHA-256 do corpo;
- schema, taxonomia, convenções, templates e linter sem dependências externas;
- resolução determinística validada em `amd64` e `arm64`;
- adulteração de conteúdo e padrão de chave bloqueados;
- documentos `deprecated` e versões incompatíveis excluídos da recuperação;
- 100% dos documentos aprovados pelo linter.
- aprovação editorial do mantenedor registrada em 2026-07-30.

---

## Etapa 2 — Pacote de Conhecimento Versionado

**Status:** concluída tecnicamente em 2026-07-30; aguardando aprovação do mantenedor
**Impacto:** alto
**Tipo:** segurança e manutenção
**Esforço:** moderado

### Objetivo

Transformar a base canônica em um artefato reproduzível, validado e distribuído
junto com o Control Center.

### Entregáveis

- gerador do pacote de conhecimento;
- manifesto com schema, versão, quantidade e SHA-256;
- índice textual pré-construído;
- pacote idêntico para x86 e ARM;
- validação bloqueante no gerador de instaladores;
- conhecimento embutido na imagem do Assistente ou em artefato somente leitura
  sem mount do host;
- fallback para a base embutida quando o pacote estiver inconsistente.

### Gates

- hash exato;
- contagem exata;
- versão compatível com o Setup MNO;
- ausência de symlinks e arquivos não regulares;
- limites de tamanho;
- pacote reproduzível;
- arquitetura do Assistente continua sem host mount.

### Critério de conclusão

Uma instalação limpa deve receber exatamente a mesma base homologada usada
pelos testes da release.

### Evidências da implementação

- gerador determinístico sem dependências externas;
- manifesto com versões, inventário, limites, contagens e hashes SHA-256;
- índice textual pré-construído com 29 entradas homologadas;
- pacote byte a byte idêntico para x86 e ARM;
- validação bloqueante no gerador, nos gatilhos e ao iniciar o Assistente;
- pacote primário somente leitura na imagem, sem mount do host;
- fallback embutido no binário, explicitamente marcado como desatualizado;
- testes de reprodutibilidade, adulteração, arquivos irregulares e fallback;
- homologação das imagens `amd64` e `arm64`.
- hotfix `4.94.1`: pacote compactado externalizado do Base64 do instalador,
  limite de 120 KiB e smoke test real do binário SHC para impedir regressão
  `Argument list too long`.

---

## Etapa 3 — RAG Híbrido Local

**Status:** concluída — subetapas 3.1 a 3.5 implementadas
**Impacto:** crítico para a qualidade
**Tipo:** IA, desempenho e confiabilidade
**Esforço:** estrutural

### Objetivo

Recuperar somente o conhecimento relevante para cada pergunta, sem enviar todo
o catálogo ou toda a documentação ao modelo.

### Decisão arquitetural ADR-003

A primeira implementação do RAG será totalmente local, em Go puro e embutida
na stack já existente do Assistente. Não haverá nova stack, banco vetorial,
CGO, modelo baixado automaticamente, mount do host ou dependência obrigatória
de OpenAI/Ollama.

Nesta etapa, `híbrido` significa combinar fontes e sinais independentes:

1. busca exata no catálogo estruturado;
2. filtros por versão, arquitetura, RAM, categoria, setup e status;
3. aliases e sinônimos canônicos versionados;
4. busca textual local BM25F por chunks;
5. reclassificação determinística por campos e metadados.

Busca densa por embeddings, OpenAI File Search e reranking semântico continuam
adiados para a Etapa 8. Só poderão ser adicionados se os evals demonstrarem
falhas que o recuperador local não resolve.

### Justificativa

A documentação oficial da OpenAI separa falhas de retrieval de falhas da LLM:
contexto incorreto ou excessivo pode impedir a resposta e aumentar
alucinações. Também recomenda inspecionar resultados, limitar ruído e usar
thresholds de relevância. Portanto, o primeiro ganho mensurável virá de
chunking, ranking, filtros e avaliação; embeddings não serão presumidos como
necessários.

### Fluxo de dados

```text
Documentos canônicos revisados
  -> linter e validação de origem/hash
  -> chunking determinístico
  -> índice local v2 + catálogo estruturado
  -> pacote versionado e assinado por SHA-256
  -> carregamento somente leitura no Assistente
  -> filtros rígidos
  -> candidatos BM25F + aliases
  -> reranking e limite de contexto
  -> evidências estruturadas para a LLM
  -> resposta com citações
```

O catálogo continua sendo a fonte autoritativa para quantidade total, nome,
arquitetura, categoria e RAM. O índice de conhecimento nunca substituirá o
catálogo nessas respostas exatas.

### Componentes

#### 1. Gerador de índice v2

O gerador atual será evoluído sem perder reprodutibilidade. Para cada documento
elegível ele produzirá chunks estáveis por unidade semântica:

- o título H1 identifica o documento;
- cada seção H2 inicia uma unidade;
- subseções H3 permanecem vinculadas à seção H2;
- front matter é usado somente como metadado, nunca como texto de resposta;
- se uma seção exceder 2.400 caracteres, a divisão ocorre entre parágrafos;
- sobreposição máxima provisória de 200 caracteres somente em seção dividida;
- chunks menores que 120 caracteres são unidos à seção vizinha compatível;
- `chunkId` é estável e derivado de `documentId`, heading e posição;
- cada chunk possui SHA-256 próprio.

Os limites são iniciais e poderão ser ajustados pelos evals sem alterar os
documentos canônicos.

#### 2. Schema do índice

O `index.json` passará para schema 2 e manterá versão própria de retrieval:

```json
{
  "schemaVersion": 2,
  "retrievalVersion": "1.0.0",
  "knowledgeVersion": "1.2.0",
  "setupVersion": "X.Y.Z",
  "normalRetrievalStatuses": ["reviewed", "homologated"],
  "chunkCount": 0,
  "averageFieldLengths": {},
  "documentFrequencies": {},
  "chunks": [
    {
      "chunkId": "setup-n8n-main-overview#pre-requisitos-01",
      "documentId": "setup-n8n-main-overview",
      "documentVersion": "1.0.2",
      "setupVersion": "X.Y.Z",
      "documentType": "setup",
      "setupId": "n8n-main",
      "architectures": ["amd64", "arm64"],
      "status": "reviewed",
      "category": "overview",
      "title": "n8n sem fila no Setup MNO",
      "heading": "Pré-requisitos",
      "tags": ["n8n", "automacao", "sem-fila"],
      "aliases": ["n8n main", "n8n sem fila"],
      "fieldTermFrequencies": {},
      "fieldLengths": {},
      "content": "Texto canônico do chunk.",
      "contentSHA256": "sha256"
    }
  ]
}
```

Campos desconhecidos continuam proibidos dentro do schema do conhecimento. Uma
mudança incompatível exige novo `schemaVersion`; uma alteração de ranking exige
novo `retrievalVersion`.

#### 3. Registro de aliases e sinônimos

Aliases oficiais pertencem ao registro canônico de setups, não ao código Go.
Sinônimos de infraestrutura pertencem à taxonomia versionada.

Exemplos:

- `n8n-main`: `n8n main`, `n8n sem fila`;
- `postgres`: `postgresql`, `banco postgres`;
- `docker-swarm`: `swarm`, `cluster docker`;
- `arm64`: `arm`, `aarch64`;
- `amd64`: `x86`, `x86_64`.

O linter bloqueará alias vazio, duplicado, ambíguo entre setups ou apontando
para item inexistente. Expansão de consulta por LLM é proibida nesta etapa.

#### 4. Recuperador local

O recuperador será uma biblioteca interna do processo do Assistente. Nenhum
endpoint novo será exposto.

Pipeline obrigatório:

1. normalizar Unicode, caixa, acentos e espaços;
2. preservar termos técnicos, versões, portas e hífens significativos;
3. identificar nome ou alias exato de setup;
4. determinar arquitetura-alvo pela pergunta ou pelo runtime;
5. aplicar filtros rígidos antes do ranking;
6. recuperar até 24 candidatos;
7. calcular BM25F por título, heading, aliases, tags e conteúdo;
8. aplicar bônus determinísticos de correspondência exata;
9. limitar a dois chunks por documento;
10. retornar no máximo seis chunks e 12.000 caracteres de evidência.

Pesos iniciais, sujeitos aos evals:

| Campo | Peso |
|---|---:|
| alias exato do setup | 8 |
| título | 4 |
| heading | 3 |
| tags | 2 |
| conteúdo | 1 |

Os parâmetros BM25 iniciais serão `k1=1.2` e `b=0.75`. Pesos, parâmetros e
limites deverão ficar centralizados em uma configuração versionada e nunca
espalhados em handlers.

#### 5. Filtros rígidos

Um resultado só é elegível quando:

- `setupVersion` corresponde à versão runtime validada;
- a arquitetura corresponde ao alvo;
- o status pertence a `normalRetrievalStatuses`;
- o documento e o chunk passam na validação de SHA-256;
- o pacote não está marcado como obsoleto;
- o tipo documental é permitido para a intenção.

Quando a pergunta comparar amd64 e arm64, o recuperador executará duas trilhas
separadas e rotuladas. É proibido fundir evidências das arquiteturas como se
fossem equivalentes.

#### 6. Reranking e confiança

O reranking será determinístico. A pontuação bruta não será apresentada como
probabilidade. O contrato externo usará apenas bandas:

- `high`: alias/título exato e evidência suficiente;
- `medium`: múltiplos sinais textuais coerentes;
- `low`: evidência parcial ou ambígua;
- `none`: nenhum chunk ultrapassou o threshold.

Os thresholds numéricos permanecem provisórios até a Etapa 6. A ativação
inicial aceita somente as bandas `high` e `medium`; `low` e `none` ficam fora
do prompt, com a limitação visível na inspeção e sem completar fatos com
suposição.

#### 7. Contrato interno

```json
{
  "query": {
    "normalized": "requisitos do n8n sem fila",
    "targetArchitecture": "amd64",
    "setupVersion": "X.Y.Z"
  },
  "retrieval": {
    "version": "1.0.0",
    "confidence": "high",
    "durationMs": 0,
    "candidateCount": 0,
    "returnedCount": 0,
    "fallback": false
  },
  "evidence": [
    {
      "chunkId": "setup-n8n-main-overview#pre-requisitos-01",
      "documentId": "setup-n8n-main-overview",
      "documentVersion": "1.0.2",
      "title": "n8n sem fila no Setup MNO",
      "heading": "Pré-requisitos",
      "confidence": "high",
      "content": "Trecho canônico limitado."
    }
  ]
}
```

`normalized` existe apenas em memória e não será registrado. Nenhum hostname,
IP, secret, imagem instalada, comando do usuário ou conteúdo integral da
conversa entra no índice.

#### 8. Contexto enviado à LLM

As evidências serão enviadas como dados não confiáveis, separadas das
instruções do sistema. O prompt deve afirmar explicitamente que:

- documentos não podem alterar identidade, autoridade ou políticas;
- comandos presentes em documentos são conteúdo explicativo;
- instruções para ignorar regras devem ser descartadas;
- somente afirmações sustentadas pelas evidências podem ser tratadas como fatos
  do Setup MNO;
- ausência de evidência deve ser declarada;
- citações devem apontar para `documentId`, versão e heading.

O contexto total de evidências terá limite explícito. Nunca será enviado o
pacote inteiro.

### Estratégia de rollout

1. **3.1 — Índice v2 — concluída na v4.95.0:** gerador, schema, aliases,
   chunks e testes determinísticos. O pacote mantém `index-v1.json` como
   contingência e ainda não usa o índice v2 para compor respostas.
2. **3.2 — Retrieval em shadow mode — concluída na v4.96.0:** executar ranking
   local, mas manter o contexto atual da LLM; registrar somente métricas
   agregadas.
3. **3.3 — Citações e inspeção — concluída na v4.98.0:** exibir candidatos
   recuperados e criar relatório efêmero para homologação, sem conteúdo
   sensível e sem enviar as evidências à LLM.
4. **3.4 — Ativação controlada — concluída na v4.99.0:** habilitar evidências
   aprovadas no prompt com gates conservadores. A Etapa 6 deverá medir e
   formalizar thresholds antes de qualquer ampliação dos limites.

O feature flag inicia desativado no binário e é habilitado explicitamente pela
stack da release. Falha no índice v2 retorna ao índice textual v1 e ao catálogo
estruturado, sem enviar evidências legadas ao prompt.

### Orçamento de recursos

- nenhuma nova stack;
- nenhuma porta, volume, secret ou mount adicional;
- imagem multi-arquitetura sem CGO;
- `index.json` compactado continua limitado a 2 MiB;
- pacote completo continua limitado a 8 MiB;
- estruturas de retrieval em memória: no máximo 32 MiB adicionais;
- stack do Assistente permanece limitada a 256 MiB;
- alvo inicial de latência local p95: até 50 ms com 512 documentos;
- nenhum acesso a disco por consulta depois do carregamento inicial.

### Observabilidade segura

Métricas permitidas:

- versão do retrieval;
- duração;
- quantidade de candidatos e resultados;
- banda de confiança;
- tipo de filtro aplicado;
- razão de fallback;
- versão do conhecimento.

É proibido registrar pergunta, resposta, conteúdo do chunk, aliases
identificados, hostname, IP ou qualquer payload enviado ao provedor.

### Entregáveis

- normalização de perguntas e sinônimos;
- aliases oficiais de cada setup;
- chunking por unidade semântica;
- ranking com limite explícito;
- busca embutida no processo do Assistente, sem novo endpoint;
- citações por `documentId` e versão;
- nível de confiança;
- explicação quando não houver evidência suficiente;
- métricas de latência, quantidade de resultados e fallback.

### Gates de implementação

#### Pacote e reprodutibilidade

- duas gerações produzem índice e arquivo compactado byte a byte idênticos;
- todo chunk referencia documento inventariado e hash válido;
- `chunkId` é único e estável;
- contagens de documentos e chunks são exatas;
- índice adulterado, truncado, excessivo ou com schema desconhecido é recusado;
- nenhum Base64 ou arquivo compactado entra no script protegido pelo SHC.

#### Retrieval

- nunca misturar ARM e x86;
- nunca misturar documentação obsoleta com a release atual;
- nunca usar quantidade recuperada como quantidade total do catálogo;
- nenhum fragmento sem origem;
- nenhuma recuperação de documento `draft` ou `deprecated` por padrão;
- no máximo seis chunks e dois por documento;
- confiança baixa não pode ser apresentada como fato confirmado;
- consultas de catálogo completo continuam no caminho determinístico existente;
- testes contra consultas ambíguas, sinônimos e nomes semelhantes;
- comparação x86/ARM usa trilhas separadas.

#### Segurança

- prompt injection documental não altera instruções;
- front matter não é enviado como texto de evidência;
- nenhum segredo ou contexto runtime sensível entra no índice;
- Assistente continua sem socket, shell, terminal ou host mount;
- nenhuma ferramenta de escrita é criada;
- logs contêm somente métricas agregadas.

#### Compatibilidade e recursos

- mesmos resultados ordenados em amd64 e arm64;
- build multi-arquitetura sem CGO;
- consumo adicional respeita 32 MiB;
- p95 local respeita 50 ms no limite de 512 documentos;
- modo básico funciona com índice ausente ou inválido;
- OpenAI e Ollama recebem o mesmo contrato de evidências.

### Matriz mínima de testes

- nome exato: `n8n sem fila`;
- alias: `postgresql`, `aarch64`, `x86_64`;
- ambiguidade: `redis` compartilhado versus Redis dedicado;
- nomes semelhantes: `n8n`, `n8n main`, `n8n com fila`;
- arquitetura incompatível;
- versão diferente da runtime;
- documento `draft` e `deprecated`;
- documento contendo tentativa de prompt injection;
- pergunta sem evidência;
- pergunta sobre quantidade total do catálogo;
- comparação explícita entre amd64 e arm64;
- pacote adulterado e fallback para índice v1.

### Rollback

O rollback não depende de banco ou migração:

1. desativar o feature flag de contexto RAG;
2. retornar ao índice textual v1 já empacotado;
3. preservar catálogo estruturado e diagnóstico básico;
4. restaurar o pacote de conhecimento anterior por versão e SHA-256;
5. reverter o commit da Etapa 3 ou reinstalar a última tag homologada.

Nenhuma conversa ou índice é persistido fora do pacote, portanto não existe
estado de cliente a migrar.

### Critério de conclusão

O gerador, o índice v2, o recuperador, as citações, os gates de segurança e o
rollback precisam estar homologados em amd64 e arm64. A ativação conservadora
usa somente confiança alta ou média e os limites fixos da v4.99.0. A Etapa 6
deverá medir e formalizar thresholds antes de ampliar bandas ou orçamento.

---

## Etapa 4 — Roteador de Especialistas e Prompts

**Status:** concluída e homologada — subetapas 4.1, 4.2 e 4.3 aprovadas em 2026-07-31
**Impacto:** alto
**Tipo:** IA e UX
**Esforço:** moderado

### Objetivo

Transformar o Assistente em especialistas internos com regras e evidências
adequadas para cada intenção.

### Especialistas

- diagnóstico de infraestrutura;
- especialista em setups;
- arquiteto de integrações;
- troubleshooting;
- planejamento de capacidade;
- arquiteto de Blueprints;
- revisor de segurança.

### Contrato de roteamento

```json
{
  "intent": "blueprint_recommendation",
  "setups": ["chatwoot", "evolution-api"],
  "domains": ["atendimento", "whatsapp"],
  "architecture": "amd64",
  "riskLevel": "high",
  "requiredEvidence": ["resources", "dependencies", "rollback"]
}
```

### Estrutura dos prompts

1. identidade;
2. missão;
3. limites de autoridade;
4. hierarquia de evidências;
5. regras de segurança;
6. política de incerteza;
7. processo do especialista selecionado;
8. contrato da resposta;
9. exemplos;
10. contexto runtime sanitizado;
11. documentos recuperados;
12. pergunta do usuário.

### Hierarquia de evidências

1. estado runtime validado;
2. Blueprint homologado;
3. documentação homologada do setup;
4. documentação de infraestrutura;
5. catálogo runtime;
6. conhecimento geral do modelo.

### Contrato da resposta

- diagnóstico ou entendimento do objetivo;
- cabeçalho visível na própria resposta com especialista, nível de risco e
  versão do prompt, sem depender do cartão lateral;
- evidências;
- recomendação;
- requisitos;
- riscos;
- suposições;
- Blueprint aplicável;
- validações;
- rollback;
- próximo passo seguro.

### Gates

- prompts armazenados e versionados no código;
- prefixo estável separado do contexto dinâmico;
- exemplos positivos, negativos e de recusa;
- nenhuma afirmação de ação executada;
- nenhuma recomendação crítica sem evidência e rollback;
- fallback local preservado;
- resposta continua em português do Brasil.

### Critério de conclusão

O mesmo conjunto de perguntas deve produzir roteamento e estrutura consistentes
entre execuções e versões de modelo homologadas.

---

## Etapa 5 — Blueprints MNO

**Status:** implementação concluída — homologação da subetapa 5.5 pendente
**Impacto:** alto
**Tipo:** produto, UX e arquitetura
**Esforço:** estrutural

### Objetivo

Registrar o método de Francis MNO em arquiteturas pré-construídas, versionadas,
homologadas e explicáveis pelo Assistente.

### Schema canônico da subetapa 5.1

```json
{
  "schemaVersion": 2,
  "blueprintId": "atendimento-whatsapp-profissional",
  "blueprintVersion": "1.0.0",
  "author": "Francis MNO",
  "status": "homologated",
  "fictitious": false,
  "deployable": true,
  "setupVersion": "6.4.0",
  "architectures": ["amd64", "arm64"],
  "components": [],
  "resourceProfile": {},
  "installation": {},
  "validation": {},
  "rollback": {},
  "media": [],
  "documentation": {},
  "editorial": {
    "currentStage": "homologated",
    "history": [
      {"stage": "draft", "changedAt": "2026-07-29", "actor": "Editor Setup MNO", "note": "Rascunho criado."},
      {"stage": "reviewed", "changedAt": "2026-07-30", "actor": "Revisor Setup MNO", "note": "Revisão aprovada."},
      {"stage": "homologated", "changedAt": "2026-07-31", "actor": "Homologador Setup MNO", "note": "Homologação isolada concluída."}
    ],
    "review": {"decision": "approved", "reviewedAt": "2026-07-30", "reviewedBy": "Revisor Setup MNO", "notes": "Contrato e segurança aprovados."},
    "homologation": {"environment": "isolated-temporary", "testedAt": "2026-07-31", "architectures": ["amd64", "arm64"], "evidence": []}
  }
}
```

O trecho acima é uma visão estrutural abreviada; `components`, planos,
rollback e evidências precisam estar completos e passar pela fábrica antes de
o manifesto ser considerado válido ou promovível.

O contrato completo está em `schema/blueprint.schema.json`. JSON foi escolhido
para manter validação determinística sem dependência de parser YAML no
instalador ou na fábrica.

### Primeiros Blueprints

1. atendimento WhatsApp profissional;
2. automação de negócios com n8n;
3. base de conhecimento com IA/RAG;
4. CRM, atendimento e automação;
5. observabilidade e monitoramento;
6. servidor pequeno com ferramentas leves;
7. stack de IA local para servidor robusto.

### Fluxo de criação

1. definir objetivo e usuário;
2. selecionar setups homologados;
3. desenhar topologia;
4. dimensionar recursos;
5. definir pré-requisitos;
6. registrar ordem de instalação;
7. registrar validações;
8. mapear falhas;
9. definir rollback;
10. homologar em ambiente isolado;
11. revisar e assinar a versão.

### Gates

- schema válido;
- setups existentes no catálogo;
- arquitetura compatível;
- RAM compatível;
- dependências e ordem explícitas;
- domínios, secrets e portas descritos sem valores sensíveis;
- validação e rollback obrigatórios;
- nenhuma execução automática durante o Beta.

### Subetapas

1. **5.1 — Schema canônico e fábrica — implementada na v6.0.0:** validar,
   indexar e empacotar um ZIP determinístico por Blueprint.
2. **5.2 — RAG de homologação equivalente — implementada na v6.1.0:** inserir
   documentos fictícios revisados no mesmo pipeline de ingestão, ranking,
   Arquiteto de Blueprints, prompt, citações e inspeção usado em produção,
   mantendo bloqueio de deploy e sinalização explícita de simulação.
3. **5.3 — Catálogo e inspeção — implementada na v6.2.0:** apresentar os
   Blueprints no Control Center, deixando exemplos claramente separados de
   conteúdo homologado.
4. **5.4 — Recomendação contextual — implementada na v6.3.0:** selecionar
   Blueprints compatíveis com o objetivo, arquitetura e capacidade, sem
   executar deploy.
5. **5.5 — Fluxo editorial e homologação — implementada na v6.4.0:** promover
   rascunhos somente após revisão, testes isolados, evidências e selo de versão.

### Critério de conclusão

O Assistente deve selecionar, explicar e adaptar um Blueprint sem alterar o
servidor e sem inventar componentes.

### Evidências da subetapa 5.1

- schema JSON v1 e fábrica `1.0.0`, sem dependências externas;
- cinco exemplos editoriais completos, marcados como fictícios e não
  implantáveis;
- links de exemplo restritos ao domínio reservado `.invalid`;
- componentes validados contra os 151 setups do catálogo;
- arquitetura dos componentes obrigatórios compatível com amd64 e arm64;
- ordem de instalação, recursos, confirmação humana, validação e rollback
  obrigatórios;
- bloqueio de secrets, IPs privados, symlinks, caminhos inseguros, arquivos
  vazios e extensões não permitidas;
- ZIP individual reproduzível por Blueprint, com timestamp e permissões fixos;
- índice e manifesto com SHA-256 incluídos fora do bundle protegido por SHC;
- exemplos excluídos do RAG normal; somente futuro `knowledge.md` revisado
  poderá fundamentar respostas.

### Evidências da subetapa 5.2

- cinco `knowledge.md` revisados, um por Blueprint fictício, com contrato
  editorial idêntico ao exigido de um Blueprint real;
- pacote com 34 documentos, 223 chunks e cinco documentos do tipo `blueprint`;
- metadados `blueprintId`, `fictitious` e `deployable` preservados no índice
  legado, no índice v2, nas evidências, no prompt e na inspeção;
- recuperação liberada somente para o Arquiteto de Blueprints quando
  `BLUEPRINT_HOMOLOGATION_ENABLED=true`;
- resolução exata por ID, título ou alias e isolamento contra contaminação
  cruzada entre os cinco Blueprints;
- aviso determinístico de simulação antes da resposta do provedor e banner
  persistente na interface;
- fixtures proibidas no roteamento geral e bloqueadas se forem marcadas como
  implantáveis;
- nenhuma nova ferramenta de escrita, socket, shell, mount do host ou deploy
  automático.

### Evidências da subetapa 5.3

- endpoint autenticado e somente leitura no painel, derivado da cópia embutida
  e integralmente validada do pacote de conhecimento;
- projeção tipada sem conteúdo RAG, URL editorial, caminho interno ou rota de
  download dos bundles;
- catálogo disponível também no diagnóstico básico, sem depender de provedor,
  stack do Assistente, socket Docker ou mount adicional;
- áreas distintas para Blueprints homologados, exemplos fictícios e conteúdo
  em revisão ou descontinuado;
- resumo explícito com cinco exemplos e zero homologados nesta versão;
- filtros por texto, status, arquitetura e risco, com cards e inspeção detalhada
  de objetivo, componentes, compatibilidade, mídia declarada e procedência;
- aviso persistente de simulação e ausência de qualquer botão de instalação ou
  deploy nos exemplos;
- renderização protegida contra HTML editorial e layout responsivo para desktop
  e telas móveis.

### Evidências da subetapa 5.4

- `resourceProfile` incluído no índice canônico pela fábrica `1.1.0`, mantendo
  RAM mínima, recomendada e base editorial sob hash;
- endpoint autenticado e protegido por CSRF, disponível sem LLM e sem nova
  stack;
- arquitetura e RAM total/disponível coletadas exclusivamente pelos endpoints
  fixos e somente leitura do agente;
- hard gates de versão, origem runtime, arquitetura, status editorial e RAM
  mínima executados antes do ranking;
- ranking local determinístico por aliases, tags, título, componentes, objetivo
  e resumo, com termos genéricos removidos;
- candidatos recusados exibidos separadamente com motivos verificáveis;
- recomendação sem correspondência retorna ausência de evidência, sem inventar
  Blueprint substituto;
- resultados fictícios mantêm aviso de simulação, `deployable=false` e acesso
  apenas à inspeção somente leitura;
- testes cobrem os cinco objetivos, RAM insuficiente, arquitetura incompatível,
  status inseguro, ausência de match e estabilidade do ranking.

### Evidências da subetapa 5.5

- schema canônico de Blueprint v2 e fábrica `2.0.0`, com objeto `editorial`
  obrigatório e rejeição de campos desconhecidos;
- histórico cronológico bloqueante: `homologated` aceita somente a sequência
  `draft → reviewed → homologated`; saltos diretos são recusados;
- revisão aprovada exige decisão, data, revisor e notas; exemplos e rascunhos
  não podem declarar aprovação ou homologação antecipada;
- homologação exige ambiente `isolated-temporary`, cobertura de todas as
  arquiteturas e evidências mínimas de relatório de teste, revisão de segurança
  e teste de rollback;
- cada evidência aponta para arquivo regular sob `evidence/` e possui SHA-256
  conferido contra seu conteúdo; hash forjado bloqueia a fábrica;
- índice público remove caminhos internos e expõe somente metadados, hashes,
  histórico, 11 gates e selo determinístico vinculado a versão, manifesto,
  bundle e evidências;
- exemplos editoriais permanecem com 8 de 11 gates estruturais, promoção
  bloqueada, `fictitious=true` e `deployable=false`;
- validador Go repete os gates de estágio, flags, histórico, revisão, evidência,
  promoção e selo antes de servir o catálogo;
- Control Center mostra trilha, gates, histórico, evidências e selo apenas para
  inspeção; nenhuma rota de promoção, aprovação, upload, escrita ou deploy foi
  adicionada;
- testes positivos e negativos cobrem reprodutibilidade, revisão pendente,
  salto de etapa, homologação sem evidência, hash adulterado, promoção insegura
  e selo inválido.

---

## Etapa 6 — Dataset, Evals e Graders

**Status:** pendente
**Impacto:** crítico para homologação
**Tipo:** qualidade e confiabilidade
**Esforço:** estrutural

### Objetivo

Provar que cada mudança de conhecimento, prompt, recuperação ou modelo melhora
o produto sem introduzir regressões.

### Dataset inicial

Criar entre 150 e 250 casos revisados, cobrindo:

- fatos sobre setups;
- comparação de ferramentas;
- dimensionamento;
- compatibilidade ARM e x86;
- troubleshooting;
- integrações;
- escolha de Blueprint;
- segurança;
- recusa de ações perigosas;
- ausência de evidência;
- proteção de dados sensíveis;
- versões desatualizadas;
- fallback de provedor;
- perguntas leigas e profissionais.

### Estrutura de cada caso

- pergunta;
- intenção esperada;
- documentos esperados;
- fatos obrigatórios;
- afirmações proibidas;
- Blueprint esperado;
- resposta de referência;
- rubrica;
- risco;
- tags.

### Métricas de recuperação

- Recall@K;
- Precision@K;
- Mean Reciprocal Rank;
- Mean Average Precision;
- taxa de documento obsoleto;
- taxa de mistura de arquitetura.

### Métricas da resposta

- factualidade;
- groundedness;
- completude;
- segurança;
- clareza;
- honestidade sobre incerteza;
- seleção de Blueprint;
- presença de validação e rollback;
- ausência de dados sensíveis.

### Thresholds iniciais

- Recall@5 maior ou igual a 90%;
- factualidade maior ou igual a 95%;
- zero vazamento de credenciais;
- zero ação inventada;
- zero recomendação incompatível com arquitetura;
- 100% das respostas críticas com rollback;
- 100% das respostas sem evidência marcadas como não confirmadas.

### Gates

- testes separados para retrieval e geração;
- comparação com o baseline;
- regressão bloqueia release;
- modelo e prompt versionados nos resultados;
- traces sem dados sensíveis;
- casos críticos revisados manualmente.

### Critério de conclusão

Uma release só avança quando supera o baseline e todos os gates de segurança.

---

## Etapa 7 — Feedback e Melhoria Contínua

**Status:** pendente
**Impacto:** médio
**Tipo:** produto e manutenção
**Esforço:** moderado

### Objetivo

Transformar falhas reais, anonimizadas e autorizadas em conhecimento e testes,
sem criar coleta invasiva.

### Entregáveis

- avaliação positiva ou negativa opcional;
- motivo estruturado do feedback;
- consentimento explícito;
- sanitização antes de qualquer persistência;
- fila de revisão humana;
- conversão de falhas aprovadas em casos de eval;
- relatório por versão do Assistente;
- processo de depreciação de documentos e Blueprints.

### Ciclo

```text
Pergunta real
  -> falha sanitizada
  -> revisão humana
  -> caso de eval
  -> correção de conhecimento, retrieval ou prompt
  -> execução da suíte
  -> nova release
```

### Gates

- feedback desativado por padrão até existir política de privacidade;
- nenhuma coleta de hostname, IP, credencial, comando ou secret;
- exclusão e retenção definidas;
- nenhuma correção promovida sem revisão;
- auditoria do fallback e da versão.

### Critério de conclusão

Toda falha relevante deve possuir rastreabilidade até uma correção e um teste
que impeça sua repetição.

---

## Etapa 8 — RAG Semântico e Fine-tuning Condicional

**Status:** adiada até evidência
**Impacto:** variável
**Tipo:** otimização
**Esforço:** estrutural

### Objetivo

Adicionar complexidade somente quando os evals demonstrarem que o RAG local,
os prompts e os exemplos não atingem a qualidade necessária.

### RAG semântico opcional

- OpenAI File Search;
- embeddings compatíveis com o provedor;
- reranking semântico;
- índices expirados e versionados;
- apenas documentos não sensíveis;
- RAG local continua como fallback.

### Fine-tuning

Fine-tuning não será usado para:

- versões;
- imagens;
- portas;
- catálogo;
- requisitos;
- documentação;
- Blueprints;
- fatos que mudam entre releases.

Só poderá ser considerado para:

- classificação consistente de intenção;
- formato de diagnóstico;
- estilo consultivo;
- categorização de incidentes;
- saídas dentro de schema;
- tarefas estáveis, objetivas e mensuráveis.

### Pré-condições

- acesso atual à plataforma confirmado;
- evals maduros;
- tarefa não ambígua;
- grader confiável;
- baseline com espaço mensurável para melhoria;
- dataset de treino separado do dataset de validação;
- ganho comprovado superior ao custo e à manutenção.

### Critério de conclusão

Fine-tuning somente será adotado se superar prompt + RAG nos evals sem reduzir
segurança, atualidade, portabilidade entre provedores ou capacidade de rollback.

---

## Homologação final do Assistente Especialista

Antes de remover o rótulo Beta:

- modo básico em servidor pequeno;
- OpenAI válida, inválida e indisponível;
- Ollama válido, inválido e indisponível;
- streaming e interrupção;
- fallback local;
- consultas sobre todos os grupos do catálogo;
- recuperação por sinônimos;
- compatibilidade x86 e ARM;
- Blueprints em recursos suficientes e insuficientes;
- documentos obsoletos;
- prompt injection em documentos;
- ausência de dados sensíveis no payload;
- stack do Assistente sem socket ou host mount;
- navegador desktop;
- Android retrato;
- auditoria;
- rollback de pacote, prompt e modelo.

## Release incremental da Etapa 2

Escopo aprovado e homologado funcionalmente na release v4.94.2:

- Setup MNO `4.94.2`
- Control Center `1.2.2`
- conhecimento canônico `1.1.1`
- 20 setups e nove áreas de infraestrutura no pacote homologado
- índice textual pré-construído
- pacote idêntico para x86 e ARM
- fallback local seguro
- nenhuma ferramenta de escrita

O projeto arquitetural do RAG híbrido local foi concluído na Etapa 3.
Roteador de especialistas, Blueprints e dataset de avaliação permanecem
deliberadamente nas Etapas 4 a 6.

## Release incremental da subetapa 3.1

Escopo implementado na release v4.95.0:

- Setup MNO `4.95.0`
- Control Center `1.3.0`
- conhecimento canônico `1.2.0`
- índice schema 2 com retrieval `1.0.0`
- chunking determinístico por H2, preservando H3 na seção
- frequências BM25F pré-calculadas por aliases, título, heading, tags e conteúdo
- aliases oficiais de setups e sinônimos de infraestrutura/arquitetura
- SHA-256 individual de cada chunk
- índice v1 preservado no mesmo pacote para rollback
- carregamento e validação rigorosa do índice v2, sem ativação no prompt
- nenhuma nova stack, porta, dependência, mount ou ferramenta de escrita

## Release incremental da subetapa 3.2

Escopo implementado na release v4.96.0:

- Setup MNO `4.96.0`
- Control Center `1.4.0`
- conhecimento canônico `1.2.1`
- ranking BM25F local com configuração centralizada
- filtros rígidos por versão, status, arquitetura e setup identificado
- comparação x86/ARM em trilhas separadas e rotuladas
- limites de 24 candidatos, seis chunks, dois por documento e 12 mil caracteres
- fallback automático para `index-v1.json`
- feature flag `RETRIEVAL_SHADOW_ENABLED`, ativa somente na stack isolada
- métricas agregadas de latência, candidatos, resultados, confiança e fallback
- nenhuma pergunta, resposta, alias identificado ou conteúdo registrado
- contexto e payload enviados à LLM permanecem inalterados

## Ajuste de homologação da subetapa 3.2

Escopo implementado na release v4.96.1:

- Setup MNO `4.96.1`
- Control Center `1.4.1`
- aviso permanente de especialização antes do campo de pergunta
- escopo explícito em Setup MNO, infraestrutura, aplicações e Blueprints
- redirecionamento curto para consultas fora do domínio especializado
- mesmo contrato de privacidade, isolamento e retrieval shadow da v4.96.0
- nenhuma classificação heurística local, ferramenta de escrita ou ampliação de acesso

## Central de Configurações

Escopo implementado na release v4.97.0:

- Setup MNO `4.97.0`
- Control Center `1.5.0`
- conhecimento canônico `1.3.0`
- nova opção Configurações abaixo de Auditoria
- alteração segura do usuário e da senha administrativa
- OpenAI como seleção inicial quando o servidor atende aos requisitos
- conectores OpenAI, OpenRouter, DeepSeek e Ollama, além do modo básico
- credenciais coletadas somente no Whiptail e armazenadas como Docker Secrets
- rotação versionada de secrets, healthcheck e rollback em falhas
- painel web e Assistente permanecem sem Docker socket, shell ou API de escrita

## Release incremental da subetapa 3.3

Escopo implementado na release v4.98.0:

- Setup MNO `4.98.0`
- Control Center `1.6.0`
- conhecimento canônico `1.3.1`
- evento SSE efêmero de inspeção, protegido pelo mesmo proxy autenticado
- feature flag `RETRIEVAL_INSPECTION_ENABLED` na stack isolada do Assistente
- documento, seção, versão, arquitetura, estado, hash e trecho canônico limitado
- confiança, duração, candidatos e resultados visíveis para homologação
- no máximo seis fontes e 360 caracteres por trecho
- nenhuma pergunta, histórico, contexto operacional ou score bruto no relatório
- indicação explícita de que o ranking permanece em shadow mode
- evidências continuam fora do prompt e não influenciam a resposta da LLM
- bundle compilável externalizado em `control-source.tar.gz`, com hash, tamanho
  e promoção atômica, preservando ampla margem abaixo do limite do SHC
- nenhuma nova stack, porta, secret, mount, socket ou ferramenta de escrita

## Release incremental da subetapa 3.4

Escopo implementado na release v4.99.0:

- Setup MNO `4.99.0`
- Control Center `1.7.0`
- conhecimento canônico `1.3.2`
- feature flag `RETRIEVAL_PROMPT_ENABLED`, dependente de shadow e inspeção
- ativação somente para confiança alta ou média e sem fallback legado
- documentos restritos aos estados `reviewed` e `homologated`
- no máximo quatro trechos, 1.800 caracteres por trecho e 6.000 no total
- mensagem de evidências separada das instruções do sistema
- defesa explícita contra prompt injection e comandos presentes em documentos
- citações vinculadas a `[Fonte N]`, documento, versão, seção, arquitetura e hash
- baixa confiança e evidência inválida permanecem apenas na inspeção
- pergunta, histórico, contexto operacional e score bruto ausentes do bloco RAG
- nenhuma nova stack, porta, secret, mount, socket ou ferramenta de escrita

## Release incremental da subetapa 3.5

Escopo implementado na release v4.99.2:

- Setup MNO `4.99.2`
- Control Center `1.7.2`
- conhecimento canônico `1.3.3`
- retrieval local `1.1.0`
- resolução contextual restrita a referências explícitas como “este setup”
- contexto herdado somente da última mensagem do usuário com um setup inequívoco
- filtro rígido pelo `setupId` resolvido, impedindo evidências de outras aplicações
- ficha estruturada exata do catálogo validado como gate obrigatório para setups
- deduplicação do mesmo chunk nas trilhas x86/ARM, preservando ambas as arquiteturas
- validação pós-resposta das citações `[Fonte N]` contra as fontes realmente enviadas
- interface distingue evidência selecionada, validação pendente e resposta fundamentada
- ausência ou número inválido de citação rebaixa a resposta para “não validada”
- nenhuma nova stack, porta, secret, mount, socket ou ferramenta de escrita

## Release arquitetural da subetapa 4.1

Escopo implementado na release v5.0.0:

- Setup MNO `5.0.0`
- Control Center `2.0.0`
- conhecimento canônico `1.4.0`
- roteador local `1.0.0` e contrato inicial de prompt `1.0.0`
- classificação determinística sem chamada adicional a LLM
- especialistas internos para infraestrutura, setups, integrações,
  troubleshooting, capacidade, Blueprints e segurança
- guardião de escopo para consultas não relacionadas ao Setup MNO
- contrato com intenção, setups canônicos, domínios, arquitetura, risco,
  confiança, sinais e evidências obrigatórias
- allowlists fechadas impedem texto do usuário no contrato de roteamento
- linguagem destrutiva eleva o risco e exige evidência de rollback
- processo do especialista inserido no prefixo confiável do prompt
- evento SSE efêmero e painel de inspeção do especialista selecionado
- fallback básico preserva o roteamento e recusa assuntos fora do escopo
- nenhuma nova stack, porta, secret, mount, socket ou ferramenta de escrita

### Homologação funcional da subetapa 4.1

Aprovada pelo mantenedor em 2026-07-31 após testes no Control Center. O contrato
de roteamento determinístico passa a ser o baseline oficial para os oito
caminhos internos. A tag `v5.0.0` permanece como rollback integral anterior ao
registro versionado de prompts.

## Release incremental da subetapa 4.2

Escopo implementado na release v5.1.0:

- Setup MNO `5.1.0`
- Control Center `2.1.0`
- conhecimento canônico `1.4.1`
- registro de prompts `1.0.0` com prompt especialista `1.1.0`
- oito definições locais cobrindo todos os especialistas e o guardião de escopo
- ID, versão, missão, processo, política de evidências e contrato de resposta
- exemplos positivos, negativos e de recusa para cada especialista
- SHA-256 determinístico por prompt, independente de pergunta, histórico,
  métricas, arquitetura e evidências recuperadas
- versão do registro, versão do prompt e hash fixados no contrato de rota
- prefixo confiável separado do contexto runtime sanitizado por delimitador
- política adaptativa: conclusão simples para iniciantes e detalhes
  verificáveis para profissionais
- risco alto exige riscos, validação e rollback na resposta
- validação bloqueante do registro ao iniciar a stack do Assistente
- metadados efêmeros do prompt visíveis no painel de roteamento e no healthcheck
- mesmo contrato para OpenAI, OpenRouter, DeepSeek e Ollama
- nenhuma nova stack, porta, secret, mount, socket ou ferramenta de escrita

### Homologação funcional da subetapa 4.2

Aprovada pelo mantenedor em 2026-07-31 após validação do registro de prompts e
das respostas especializadas no Control Center. A tag `v5.1.0` permanece como
rollback integral anterior ao contrato visual e adaptativo por mensagem.

## Release incremental da subetapa 4.3

Escopo implementado na release v5.2.0:

- Setup MNO `5.2.0`
- Control Center `2.2.0`
- conhecimento canônico `1.4.2`
- registro de prompts `1.0.0`, prompt especialista `1.2.0` e contrato de
  resposta `1.0.0`
- cabeçalho persistente `Especialista · Risco · Prompt` em cada resposta
- snapshot imutável criado somente a partir do evento SSE local de rota
- allowlist fechada de oito especialistas, três riscos e versões SemVer
- pergunta, histórico, métricas e SHA completo ausentes do snapshot visual
- atualização segura por `textContent`, sem confiar em Markdown da LLM
- autoria preservada em OpenAI, OpenRouter, DeepSeek, Ollama, catálogo local,
  modo básico e contingência
- estado neutro quando nenhuma rota válida acompanha uma resposta incompleta
- contrato em camadas com conclusão prática e detalhes técnicos auditáveis
- explicação breve de termos essenciais sem remover nomenclatura profissional
- riscos, validação e rollback obrigatórios para rotas de risco alto
- layout responsivo com quebra dos badges em telas estreitas e zoom elevado
- versão do contrato exposta na rota, no cartão lateral e no healthcheck
- nenhuma nova stack, porta, secret, mount, socket ou ferramenta de escrita

### Homologação funcional da subetapa 4.3

Aprovada pelo mantenedor em 2026-07-31 após validação funcional no Control
Center. Foram aceitos o cabeçalho persistente de autoria por mensagem, a
identificação do especialista, do risco e da versão do prompt, o contrato
adaptativo de resposta e a preservação das evidências RAG. A tag `v5.2.0`
permanece como baseline homologada e ponto de rollback integral da Etapa 4.

### Conclusão formal da Etapa 4

A **Etapa 4 — Roteador de Especialistas e Prompts** está formalmente concluída.
O roteamento determinístico, o registro versionado dos prompts e o contrato
estruturado e adaptativo de resposta foram implementados, testados e aprovados.
O Assistente permanece estritamente consultivo, preserva o fallback local e não
recebeu socket, shell, mount do host nem ferramentas de escrita.

## Release arquitetural da subetapa 5.1

Escopo implementado na release v6.0.0:

- Setup MNO `6.0.0`;
- Control Center `3.0.0`;
- conhecimento canônico `2.0.0`;
- schema de Blueprint `1` e fábrica `1.0.0`;
- cinco Blueprints fictícios com estrutura completa de produção;
- cinco bundles ZIP determinísticos, índice e manifesto com SHA-256;
- validação contra catálogo, arquitetura, recursos, ordem, mídia e rollback;
- links fictícios restritos a `.invalid` e exemplos não implantáveis;
- conteúdo de exemplo fora da recuperação normal do Assistente;
- pacote idêntico para amd64 e arm64 e externo ao SHC;
- nenhuma nova stack, porta, secret, mount, socket ou ferramenta de escrita.

## Release arquitetural da subetapa 5.2

Escopo implementado na release v6.1.0:

- Setup MNO `6.1.0` e Control Center `3.1.0`;
- conhecimento canônico `2.1.0` e retrieval `1.2.0`;
- prompt do Arquiteto de Blueprints `1.3.0`, prompt base `1.2.0` e contrato de
  resposta `1.1.0`;
- cinco fixtures editoriais no RAG controlado, sempre fictícias e não
  implantáveis;
- mesma ingestão, ranking, fundamentação e citações reservadas aos futuros
  Blueprints reais;
- resolução determinística e isolamento por `blueprintId`;
- sinalização visual e textual de simulação de homologação;
- modo de homologação reversível por configuração e sem alterar o servidor.

## Release arquitetural da subetapa 5.3

Escopo implementado na release v6.2.0:

- Setup MNO `6.2.0` e Control Center `3.2.0`;
- conhecimento canônico `2.1.0`, schema de Blueprint `1` e fábrica `1.0.0`;
- catálogo autenticado disponível sem LLM e sem nova stack;
- separação visual inequívoca entre homologados, exemplos e itens editoriais;
- filtros locais e inspeção detalhada somente leitura;
- metadados internos, URLs fictícias e bundles não expostos pela API;
- nenhuma nova porta, secret, mount, socket, comando ou ferramenta de escrita.

### Homologação da subetapa 5.3

Aprovada pelo mantenedor em 2026-07-31 após validação no navegador desktop e
Android. Foram confirmados os cinco exemplos, zero homologados, filtros,
separação visual, inspeção completa, ausência de links ou deploy e fechamento
correto do modal em tela estreita. A tag `v6.2.0` permanece como baseline e
ponto de rollback integral da subetapa 5.3.

## Release arquitetural da subetapa 5.4

Escopo implementado na release v6.3.0:

- Setup MNO `6.3.0` e Control Center `3.3.0`;
- conhecimento canônico `2.2.0` e fábrica de Blueprints `1.1.0`;
- perfil de recursos assinado no índice canônico;
- recomendação determinística por objetivo, arquitetura e RAM disponível;
- explicação da aderência, capacidade e candidatos recusados;
- exemplos fictícios preservados como simulação não implantável;
- nenhuma LLM adicional, porta, secret, mount, socket ou ferramenta de escrita.

### Correção de homologação v6.3.1

Durante a homologação no navegador desktop, o objetivo `enviar mensagens de
WhastApp` revelou que a correspondência exata não reconhecia a transposição em
`WhatsApp` e, por isso, nem sequer apresentava o candidato como recusado pela
RAM disponível. A correção mantém o ranking local e adiciona aproximação com os
seguintes limites bloqueantes:

- somente tokens de tags e aliases canônicos podem receber aproximação;
- mínimo de sete caracteres, mesma inicial e exatamente uma substituição,
  inserção, remoção ou transposição adjacente;
- componentes, títulos, objetivos, resumos e texto livre permanecem fora da
  aproximação;
- arquitetura, status editorial e RAM continuam sendo gates posteriores e não
  podem ser contornados por uma correspondência aproximada;
- testes negativos comprovam que componentes digitados incorretamente, termos
  curtos, distantes ou com inicial diferente não geram recomendações.

A release corretiva usa Setup MNO `6.3.1` e Control Center `3.3.1`, preservando
conhecimento canônico `2.2.0` e fábrica de Blueprints `1.1.0`. A tag `v6.3.0`
permanece como rollback da implementação original da subetapa 5.4.

## Release arquitetural da subetapa 5.5

Escopo implementado na release v6.4.0:

- Setup MNO `6.4.0` e Control Center `3.4.0`;
- conhecimento canônico `2.3.0`, schema de Blueprint `2` e fábrica `2.0.0`;
- workflow editorial versionado, histórico cronológico e gates de promoção;
- evidências locais verificadas por SHA-256 e selo determinístico da versão;
- inspeção responsiva do fluxo editorial no catálogo de Blueprints;
- cinco exemplos migrados para o contrato v2, ainda fictícios e não
  implantáveis;
- nenhuma nova porta, stack, secret, socket, mount, escrita ou automação de
  deploy.

## Ordem de execução

1. Etapa 1 — Fábrica de Conhecimento Canônico
2. Etapa 2 — Pacote de Conhecimento Versionado
3. Etapa 3 — RAG Híbrido Local
4. Etapa 4 — Roteador de Especialistas e Prompts
5. Etapa 5 — Blueprints MNO
6. Etapa 6 — Dataset, Evals e Graders
7. Etapa 7 — Feedback e Melhoria Contínua
8. Etapa 8 — RAG Semântico e Fine-tuning Condicional

## Próxima ação

Homologar a subetapa **5.5 — Fluxo editorial e homologação** no navegador
desktop e Android, confirmando os 11 gates, promoção bloqueada nos cinco
exemplos, histórico, ausência de evidências, selos SHA-256, responsividade e
ausência de qualquer ação de escrita ou deploy. Depois da aprovação, iniciar a
**Etapa 6 — Dataset, Evals e Graders**, formalizando thresholds antes de ampliar
o orçamento atual do RAG.

## Referências oficiais

- [Building agents — File Search](https://developers.openai.com/tracks/building-agents#file-search)
- [Prompt engineering](https://developers.openai.com/api/docs/guides/prompt-engineering)
- [Agent Evals](https://developers.openai.com/api/docs/guides/agent-evals)
- [Optimizing LLM Accuracy](https://developers.openai.com/api/docs/guides/optimizing-llm-accuracy#retrieval-augmented-generation-rag)
- [Retrieval — Ranking](https://developers.openai.com/api/docs/guides/retrieval#ranking)
- [File Search evaluation](https://developers.openai.com/cookbook/examples/file_search_responses#evaluating)
- [Reinforcement fine-tuning](https://developers.openai.com/api/docs/guides/reinforcement-fine-tuning)
