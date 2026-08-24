# FAQ — skills externas e agentes de servidor

- Estado: `implemented`
- Maturidade: `beta`
- Atualizado em: 2026-08-24
- Público: Francis MNO, futura comunidade e autores do Help
- Ambientes: Debian, Ubuntu, WSL2 e Docker Swarm

## Resumo para leigos

Uma skill pode trazer conhecimento útil, mas também pode pedir comandos,
arquivos e permissões perigosas. O Setup MNO separa “ler para avaliar” de
“confiar para usar”.

> **BETA:** o gate já funciona no ambiente de construção, porém ainda está em
> validação controlada e pode receber regras adicionais.

## Uma skill publicada em catálogo é segura?

Não necessariamente. Catálogo, estrelas e comentários ajudam a medir interesse,
mas não substituem commit fixo, licença, hashes, inventário, revisão de código e
permissões mínimas.

## O gate executa a skill para descobrir o que ela faz?

Não. Ele usa análise estática: lê arquivos e declarações sem rodar scripts. Uma
etapa futura poderá usar laboratório descartável, mas nunca a produção como
primeiro teste.

## Por que o commit precisa ter 40 caracteres?

Porque nomes como `main` e tags podem apontar para conteúdo diferente no
futuro. O commit completo liga a revisão ao código exato analisado.

## Se não houver bloqueio, a skill está homologada?

Não. Ela apenas pode seguir para revisão canônica. O relatório sempre lembra que
análise estática não prova ausência de comportamento malicioso.

## Por que Docker socket, root e sudo são bloqueados?

Esses acessos permitem alterar grande parte do servidor. Para uma skill externa,
isso ultrapassa a função consultiva do especialista SRE e quebra o AI Safe Mode.

## O token PRO MASTER é uma senha?

Não. Ele confirma que a decisão se refere exatamente aos hashes exibidos. O
token não autentica o mantenedor e não deve ser tratado como controle de acesso.

## O gate instala a skill no Hermes, Codex ou OpenClaw?

Não. Esta etapa não possui integração de instalação com nenhum agente. Ela
produz somente evidência para a decisão de Francis MNO.

## Limites e segurança

Não use o gate para analisar uma pasta com dados reais de clientes. Não execute
o candidato antes da revisão. Uma aprovação nunca autoriza acesso a credenciais,
Docker socket, shell ou produção.

## Fontes oficiais

- [SLSA — verifying artifacts](https://slsa.dev/spec/v1.0/verifying-artifacts)
- [SPDX — handling license info](https://spdx.dev/learn/handling-license-info/)
- [GitHub — pinning to full commit SHA](https://docs.github.com/en/enterprise-cloud@latest/code-security/tutorials/secure-your-organization/protect-against-threats)
- [OWASP GenAI — supply chain](https://genai.owasp.org/llmrisk/llm032025-supply-chain/)

## Publicação futura no Help

Publicar como FAQ geral sem expor o assistente PRO MASTER aos demais planos. A
mensagem principal é: uma skill útil continua sendo software de terceiros e
precisa de fronteira de confiança.
