# Fábrica de Conhecimento do Assistente MNO

Esta pasta é a fonte canônica, editorial e versionada do conhecimento usado
pelo Assistente MNO. Ela não é um prompt, não executa ações e ainda não faz
parte diretamente do binário protegido por SHC. O gerador produz um pacote
regular, versionado e validado por SHA-256, distribuído em `.control-package/`.

## Contrato editorial

- Os documentos são Markdown com um objeto JSON entre os dois delimitadores
  `---` iniciais.
- Metadados devem obedecer a `schema/document.schema.json`.
- `contentSHA256` é o SHA-256 do corpo Markdown normalizado pelo linter e torna
  adulterações detectáveis antes da recuperação.
- IDs, tipos, categorias, status, riscos, arquiteturas e licenças permitidos
  estão em `schema/taxonomy.json`.
- Setups de cada lote devem existir em `registry/setups.json` e no catálogo
  canônico do Control Center.
- `draft` identifica conteúdo em construção; `reviewed` identifica conteúdo
  revisado contra as fontes declaradas; `homologated` exige teste no ambiente
  de homologação; `deprecated` nunca participa da recuperação normal.
- Imagens e portas só podem aparecer quando declaradas no bloco
  `homologation` e verificadas na data informada.
- Nunca registrar credenciais, tokens, chaves, hostnames ou endereços de
  clientes.

## Convenções

O `documentId` usa segmentos minúsculos separados por hífen:

```text
<tipo>-<assunto>-<categoria>
```

Exemplos: `setup-n8n-main-overview`, `infra-docker-swarm-architecture`.

`documentVersion` segue SemVer e muda quando o conteúdo do documento muda.
`setupVersion` indica a versão do Setup MNO contra a qual o documento foi
revisado. Compatibilidade é declarada em `architectures`.

Para calcular o hash esperado após uma edição:

```bash
python3 tools/lint_knowledge.py --root . hashes
```

## Fluxo editorial

1. Criar o documento a partir de um template.
2. Manter o status como `draft` durante a escrita.
3. Declarar fontes e licença de cada fonte.
4. Executar o linter e revisar o diff.
5. Mudar para `reviewed` somente após conferir as fontes.
6. Mudar para `homologated` somente após teste controlado.
7. Marcar como `deprecated` quando o conteúdo não representar mais o Setup.

## Cobertura do catálogo

A base atual cobre as 151 entradas do catálogo. Os sete lotes editoriais
fecharam a cobertura dedicada em 100%; o relatório reproduzível é:

```bash
python3 -B tools/knowledge_coverage.py
```

O gate de cobertura total é bloqueante mesmo no canal Beta:

```bash
python3 -B tools/knowledge_coverage.py --require-complete
```

O gate monotônico obrigatório impede que uma nova ferramenta reabra a lacuna:

```bash
python3 -B tools/knowledge_coverage.py --enforce-baseline
```

A baseline `coverage-baseline.json` exige 151 entradas cobertas e nenhuma
pendência. Toda nova aplicação deve acrescentar registro, documento, fontes e
evals no mesmo commit em que entra no catálogo; os mínimos nunca devem ser
reduzidos para liberar a build.

O comando cruza nome do catálogo, registro canônico e documento
`setups/<setupId>/overview.md`. Uma entrada só conta como coberta se os três
existirem e forem coerentes. O modo normal informa a lacuna sem bloquear as
releases; `--require-complete` retorna código 3 se qualquer entrada ficar sem
cobertura.

### Definição de conhecimento completo

Cada nova entrada deve documentar, com fontes revisadas:

1. finalidade, público, casos de uso e alternativas;
2. variantes e comportamento específico do Setup MNO;
3. arquitetura, RAM, imagens, portas e dependências verificadas;
4. pré-requisitos, instalação, primeiro acesso e configuração;
5. segurança, exposição e tratamento de secrets;
6. backup, atualização, migração e rollback;
7. diagnóstico e falhas frequentes;
8. integrações suportadas e limitações;
9. aliases e fontes oficiais;
10. casos de eval para fatos, capacidade, segurança e recuperação.

Rascunhos gerados a partir de scripts ou catálogo não contam como cobertura.
Eles só entram no RAG normal após revisão humana, validação do linter e status
`reviewed` ou `homologated`. Uma nova ferramenta não deve ser liberada sem o
documento e os testes correspondentes.

## Validação

```bash
python3 tools/lint_knowledge.py \
  --root . \
  --catalog ../setupmno-control/catalog.json
```

Consulta determinística sem LLM:

```bash
python3 tools/lint_knowledge.py \
  --root . \
  --catalog ../setupmno-control/catalog.json \
  resolve \
  --setup-id n8n-main \
  --setup-version 7.2.16 \
  --architecture amd64
```

O resolvedor normal retorna somente documentos `reviewed` ou `homologated`.
Use `--include-drafts` apenas no fluxo editorial.

Testes de regressão:

```bash
python3 -B tools/test_knowledge.py
python3 -B tools/test_blueprints.py
python3 -B tools/knowledge_coverage.py
```

## Dataset e evals

`evals/dataset.json` é um artefato canônico revisado, com 815 casos e schema
estrito em `schema/eval-dataset.schema.json`. Ele contém perguntas e respostas
de referência, portanto entra somente no pacote interno de conhecimento e
nunca é devolvido pela API do painel. A interface recebe apenas métricas
agregadas, versões e o SHA-256 do dataset.

Para gerar e validar o dataset de forma reproduzível:

```bash
python3 -B tools/eval_factory.py \
  --root . \
  --setup-version 7.2.16
python3 -B tools/test_knowledge.py
```

O binário do Control Center executa `evalcheck` contra o retrieval e o roteador
reais. O instalador repete esse comando na imagem final e bloqueia a release se
qualquer threshold ou gate de segurança falhar. Nenhuma LLM, rede ou dado do
servidor participa desse baseline determinístico.

Validação isolada da fábrica de Blueprints:

```bash
python3 -B tools/blueprint_factory.py \
  --setup-version 7.2.16
```

Cada Blueprint reside em `blueprints/<blueprintId>/`, com `blueprint.json`
validado por `schema/blueprint.schema.json` e `README.md` humano. A fábrica gera
um ZIP determinístico por pasta, um índice e um manifesto com SHA-256. Os cinco
guias iniciais usam status `reviewed`, `fictitious: false` e `deployable: false`:
podem orientar execução manual, mas não representam homologação técnica nem
autorização de deploy automático.

Os `README.md` dos bundles nunca entram diretamente no RAG. Cada guia possui um
`knowledge.md` revisado que percorre o pipeline normal e pode ser recuperado
pelo Arquiteto de Blueprints. O índice também transporta checklist, ordem de
instalação, validação e rollback para a interface. Workflows, PDFs, imagens e
vídeos permanecem artefatos; links não publicados ficam nulos e não são
inventados pelo gerador nem pelo Assistente.

Geração reproduzível do pacote:

```bash
python3 -B tools/generate_package.py \
  --setup-version 7.2.16 \
  --control-version 4.11.0
```

O gerador executa o linter antes do build, inclui somente documentos
`reviewed` ou `homologated`, cria `index.json` schema 2 com chunks e campos
BM25F pré-calculados, preserva `index-v1.json` como contingência e produz
`knowledge-package.tar.gz` e `manifest.json`. O mesmo pacote contém o índice,
o manifesto, o schema e os bundles determinísticos dos Blueprints. O arquivo
compactado usa ordem, permissões, proprietário e timestamps determinísticos.

Aliases de setups pertencem a `registry/setups.json`. Sinônimos de
infraestrutura e arquitetura pertencem a `schema/taxonomy.json`; o linter
bloqueia valores vazios, duplicados, ambíguos ou com alvo desconhecido.

## Estrutura

```text
setupmno-knowledge/
├── infra/
├── setups/
├── troubleshooting/
├── blueprints/
├── policies/
├── glossary/
├── evals/
├── registry/
├── schema/
├── templates/
└── tools/
```
