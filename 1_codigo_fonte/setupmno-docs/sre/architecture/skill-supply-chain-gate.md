# Arquitetura do Skill Supply Chain Gate

- Estado: `implemented`
- Maturidade: `beta`
- Atualizado em: 2026-08-24
- Público: mantenedor PRO MASTER e autores do futuro Help
- Ambientes: repositório de construção em Debian, Ubuntu ou WSL2

## Resumo para leigos

Uma skill é um conjunto de instruções e arquivos que ensina um agente de IA a
realizar uma tarefa. Baixar uma skill e colocá-la diretamente em um servidor é
parecido com contratar uma pessoa desconhecida e entregar as chaves antes de
conferir sua identidade e o trabalho que pretende fazer.

O Skill Supply Chain Gate funciona como uma alfândega. Ele confere o pacote,
aponta riscos e produz um relatório. Não instala nem executa a skill. Um pacote
sem bloqueios ainda precisa da revisão de Francis MNO, o único PRO MASTER.

> **BETA:** o gate já valida candidatos e bloqueia riscos conhecidos, mas suas
> regras ainda serão ampliadas com a experiência de homologações reais. Use-o
> somente no repositório de construção e revise manualmente todo resultado.

## Fronteira de confiança

```text
Skill externa
     |
     v
Pasta candidata isolada e inventariada
     |
     v
Gate determinístico -> bloqueada ou aguardando revisão
     |
     v
Confirmação PRO MASTER ligada ao hash exato
     |
     v
Aprovada somente para revisão canônica

Nenhuma seta instala, publica ou executa a skill.
```

O manifesto fornecido pelo autor da skill é uma declaração, não uma prova. O
gate compara essa declaração com os arquivos e procura padrões conhecidos, mas
análise estática não garante que o conteúdo seja seguro. Por isso o relatório
sempre mantém o alerta de revisão humana.

## Contrato do candidato

O arquivo `skill-manifest.json` schema 1 declara:

- identificador, versão SemVer e entrypoint;
- repositório GitHub e commit completo de 40 caracteres;
- licença com identificador SPDX e arquivo de licença;
- inventário estrito com caminho, tamanho, permissão e SHA-256;
- URLs e dependências com versões e hashes fixos;
- comandos, leituras, escritas e acesso de rede;
- root, sudo, Docker socket, modo privilegiado, rede do host e secrets;
- ações possíveis, risco e capacidade de alterar o sistema.

O manifesto fica fora de seu próprio inventário para evitar um hash circular.
Qualquer outro arquivo precisa estar declarado.

## Decisões possíveis

- `blocked`: há violação estrutural ou operacional; não pode ser aprovada;
- `awaiting-pro-master-review`: passou pelos checks automáticos e aguarda revisão;
- `approved-for-canonical-review`: Francis MNO confirmou o hash exato; ainda não
  houve instalação, incorporação ou publicação.

O token de confirmação não autentica a pessoa. Ele serve apenas para impedir
que a confirmação de um relatório seja reutilizada depois que os arquivos
mudarem. O acesso ao repositório de construção e a governança continuam sendo
controles separados.

## Gates determinísticos

O candidato é bloqueado quando houver, entre outros casos:

- symlink, arquivo extra, arquivo ausente ou caminho com travessia;
- tamanho, modo ou SHA-256 divergente;
- origem flutuante em vez de commit fixo;
- licença ausente ou fora da allowlist suportada;
- dependência sem versão e hash fixos;
- URL não HTTPS ou encontrada no conteúdo sem declaração;
- binário não revisado ou texto que não seja UTF-8;
- possível segredo incorporado;
- download enviado diretamente para shell, `eval`, remoção recursiva forçada,
  `chmod 777`, sudo ou Docker socket;
- permissão para root, sudo, privileged, host network, secrets ou Docker socket;
- comando administrativo proibido ou ação que altera o sistema.
- comando encontrado em shell, mas omitido da lista declarada pelo autor.

## Fontes oficiais

- [SLSA — verificação de procedência](https://slsa.dev/spec/v1.0/verifying-artifacts)
- [SPDX — tratamento de licenças](https://spdx.dev/learn/handling-license-info/)
- [GitHub — fixar dependências em commit completo](https://docs.github.com/en/enterprise-cloud@latest/code-security/tutorials/secure-your-organization/protect-against-threats)
- [OWASP — riscos de cadeia de suprimentos em sistemas com LLM](https://genai.owasp.org/llmrisk/llm032025-supply-chain/)

## Limites e segurança

- O gate não clona repositórios nem acessa a internet.
- Ele não executa scripts, entrypoints ou dependências do candidato.
- Ele não prova que a licença declarada corresponde juridicamente ao conteúdo.
- Regras estáticas podem produzir alertas falsos ou não reconhecer lógica
  maliciosa bem escondida.
- Aprovação significa somente “pode seguir para revisão canônica”.
- Nenhuma skill recebe root, sudo, Docker socket, shell ou credenciais de
  produção por consequência desta etapa.

## Publicação futura no Help

Transformar a arquitetura em um fluxo de cinco cartões: origem, inventário,
riscos, revisão PRO MASTER e resultado. O Help não deve ensinar clientes a
ignorar bloqueios nem apresentar aprovação de revisão como instalação segura.
