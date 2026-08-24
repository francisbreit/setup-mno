# Como avaliar uma skill externa

- Estado: `implemented`
- Maturidade: `beta`
- Atualizado em: 2026-08-24
- Público: Francis MNO como único mantenedor PRO MASTER
- Ambientes: repositório de construção em Debian, Ubuntu ou WSL2

## Resumo para leigos

Este procedimento responde: “posso começar a revisar esta skill sem colocá-la
no servidor dos clientes?”. Ele não instala a skill. O resultado mostra o que
foi encontrado e mantém o candidato separado do Setup MNO.

> **BETA:** esta primeira versão é apropriada para testes controlados de Francis
> MNO. Ela não é um instalador de skills e não substitui a leitura humana do
> candidato.

## Antes de começar

- trabalhe somente no repositório de construção;
- use uma cópia local da skill em uma pasta separada;
- não execute nenhum arquivo do candidato;
- não informe senhas, tokens, IPs ou dados de clientes;
- exija `skill-manifest.json`, `SKILL.md` e o arquivo de licença.

Uma skill sem manifesto não é “quase aprovada”. Ela é um pacote incompleto e
deve voltar para preparação antes do gate.

## Assistente guiado

Execute:

```bash
./1_codigo_fonte/setupmno-docs/tools/skill-supply-chain-wizard.sh /caminho/ficticio/skill-candidata
```

O assistente:

1. lê a pasta sem executar seus scripts;
2. cria um relatório temporário com permissões `0600`;
3. informa bloqueios e alertas em linguagem simples;
4. se não houver bloqueio, apresenta um token ligado aos hashes;
5. solicita que o PRO MASTER digite o token;
6. registra somente a autorização para revisão canônica.

O relatório permanece em uma pasta exclusiva dentro de `/tmp`. Copiá-lo para a
base canônica é uma decisão posterior e não é feita pelo assistente.

## Leitura do resultado

### Bloqueada

Pare. Leia cada item `BLOQUEIO`. Não edite a skill apenas para esconder o
detector. Corrija a origem, atualize o manifesto e reinicie a revisão com um
novo hash.

### Aguardando revisão PRO MASTER

Os checks automáticos não acharam violação bloqueante, mas isso não prova que a
skill seja segura. Confira a finalidade, todos os arquivos, comandos, URLs,
dependências, permissões e ações declaradas.

### Aprovada para revisão canônica

O token corresponde ao conteúdo exato analisado. Ainda não existe autorização
para instalar, executar, publicar ou enviar a skill aos clientes.

## Uso direto para diagnóstico

```bash
python3 -B 1_codigo_fonte/setupmno-docs/tools/skill_supply_chain_gate.py \
  --candidate /caminho/ficticio/skill-candidata \
  --report /tmp/skill-report.json
```

Compare uma atualização com uma cópia anterior usando `--baseline`. O relatório
separa arquivos adicionados, modificados e removidos.

## Resultado esperado

Uma candidata conservadora termina com:

```text
Decisão: awaiting-pro-master-review
Nenhum arquivo foi instalado, executado, copiado ou publicado.
```

Uma candidata que pede sudo ou Docker socket termina como `blocked` e não recebe
token.

## Erros comuns

- **A skill tem muitas estrelas; posso confiar?** Popularidade não prova o
  conteúdo do commit baixado nem as permissões solicitadas.
- **O antivírus não encontrou nada.** O gate verifica também governança,
  inventário, origem e capacidade operacional; são camadas diferentes.
- **A skill só precisa do Docker socket para ler.** O socket permite operações
  administrativas e continua proibido para skills externas.
- **Posso aprovar usando `main`?** Não. A revisão deve apontar para um commit
  completo e imutável.

## Rollback

Como o gate não instala nada, basta descartar a pasta candidata e o relatório
temporário. Não há stack, serviço, volume, banco, DNS ou cliente para restaurar.

## Limites e segurança

O gate é uma triagem determinística, não auditoria completa de código. Uma skill
aprovada para revisão ainda deve passar por revisão humana, testes isolados e
decisão canônica antes de qualquer integração futura.

## Fontes oficiais

- [SLSA — verificação de procedência](https://slsa.dev/spec/v1.0/verifying-artifacts)
- [SPDX — tratamento de licenças](https://spdx.dev/learn/handling-license-info/)
- [GitHub — fixar dependências em commit completo](https://docs.github.com/en/enterprise-cloud@latest/code-security/tutorials/secure-your-organization/protect-against-threats)

## Publicação futura no Help

Criar um tutorial PRO MASTER com captura sanitizada dos três resultados e um
exemplo fictício de skill bloqueada por Docker socket. Não publicar caminhos ou
relatórios reais de clientes.
