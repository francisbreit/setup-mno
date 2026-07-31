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
- Setups do lote piloto devem existir em `registry/setups.json` e no catálogo
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
  --setup-version 6.3.1 \
  --architecture amd64
```

O resolvedor normal retorna somente documentos `reviewed` ou `homologated`.
Use `--include-drafts` apenas no fluxo editorial.

Testes de regressão:

```bash
python3 -B tools/test_knowledge.py
python3 -B tools/test_blueprints.py
```

Validação isolada da fábrica de Blueprints:

```bash
python3 -B tools/blueprint_factory.py \
  --setup-version 6.3.1
```

Cada Blueprint reside em `blueprints/<blueprintId>/`, com `blueprint.json`
validado por `schema/blueprint.schema.json` e `README.md` humano. A fábrica gera
um ZIP determinístico por pasta, um índice e um manifesto com SHA-256. O status
`example` exige `fictitious: true`, `deployable: false` e links no domínio
reservado `.invalid`.

Os `README.md` dos bundles nunca entram diretamente no RAG. Na subetapa 5.2,
cada exemplo possui um `knowledge.md` revisado que percorre o mesmo pipeline de
produção. Como esses documentos declaram `fictitious: true` e
`deployable: false`, somente o Arquiteto de Blueprints pode recuperá-los quando
o modo explícito de homologação está ativo. Workflows, PDFs, imagens e vídeos
permanecem como artefatos e não são tratados como instruções para o modelo.

Geração reproduzível do pacote:

```bash
python3 -B tools/generate_package.py \
  --setup-version 6.3.1 \
  --control-version 3.3.1
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
