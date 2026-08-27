# Base de Conhecimento Humana do Setup MNO

Esta pasta é a fonte versionada de manuais, FAQ, decisões e notas de evolução
destinadas a pessoas. Ela complementa, mas não substitui:

- `setupmno-knowledge/`, que alimenta o conhecimento canônico e os gates do
  Assistente MNO;
- o Help embarcado no Control Center, que contém somente conteúdo selecionado
  e preparado para a interface;
- `setupmno-control/ASSISTENTE_MNO_ROADMAP.md`, que permanece como roadmap
  canônico da profissionalização do produto.

O conteúdo desta pasta **não é empacotado automaticamente** no runtime, não
altera instaladores e não deve ser copiado integralmente para o Help. A
publicação futura no Control Center exige seleção editorial, adaptação para
leigos, revisão de segurança e validação em desktop e Android.

## Público e camadas de leitura

Esta base é escrita primeiro para **Francis MNO e sua comunidade maker**. Ela
não pressupõe formação profissional em DevOps. Ao mesmo tempo, deve conservar
informações suficientes para que uma pessoa experiente possa conferir a
arquitetura, os riscos e as evidências.

Os documentos devem usar divulgação progressiva:

1. **Para iniciantes:** o problema, o benefício e o resultado em linguagem
   simples;
2. **Modelo mental:** uma analogia curta, quando ela realmente ajudar;
3. **Como funciona por dentro:** a camada técnica, com componentes e decisões;
4. **Como testar:** passos pequenos, comandos seguros, resultado esperado e
   sinais de falha;
5. **Como ensinar:** uma síntese que possa virar aula, postagem, FAQ ou vídeo.

Siglas e jargões devem ser explicados na primeira ocorrência. A linguagem
simples nunca deve esconder riscos, criar promessas exageradas ou transformar
uma hipótese em fato. O padrão completo está em
`manual/padrao-didatico-francis-mno.md`.

## Estrutura

- `architecture/`: projetos arquiteturais, limites de confiança e decisões;
- `manual/`: instruções de uso orientadas a tarefas;
- `faq/`: respostas curtas para dúvidas recorrentes;
- `releases/`: notas humanas das etapas e features criadas a partir desta
  política;
- `templates/`: modelos obrigatórios para manter a documentação consistente;
- `assets/`: inventário de imagens, GIFs e vídeos futuros, sem dados reais de
  clientes;
- `sre/`: base didática e versionada do futuro especialista SRE, com manifesto
  próprio e sem publicação automática no runtime ou no Help.

Documentos atuais de arquitetura e operação:

- `manual/padrao-didatico-francis-mno.md`;
- `manual/politica-de-funcionalidades-beta.md`;
- `architecture/ai-safe-mode.md`;
- `architecture/supply-chain-sbom.md`;
- `manual/verificar-supply-chain-wsl2.md`;
- `faq/agentes-de-ia-em-vps.md`;
- `faq/supply-chain.md`;
- `releases/v7.30.0-supply-chain-sbom.md`;
- `sre/README.md`;
- `sre/manifest.json`;
- `releases/v7.31.0-sre-knowledge-pack.md`;
- `releases/control-v4.31.1-visibilidade-beta.md`;
- `sre/architecture/skill-supply-chain-gate.md`;
- `sre/manual/avaliar-skill-externa.md`;
- `sre/faq/skills-externas.md`;
- `releases/v7.32.0-skill-supply-chain-gate.md`;
- `releases/v7.32.1-control-install-heartbeat.md`;
- `releases/v7.32.2-apt-nao-interativo.md`;
- `releases/v7.33.1-dockerswarm-apt-nao-interativo.md`;
- `releases/v7.33.2-reparo-snapshot-sre-upgrade.md`;
- `releases/v7.33.3-convergencia-control-arm.md`;
- `releases/v7.33.4-configuracao-assistente-transacional.md`;
- `architecture/fronteira-protecao-shc.md`;
- `releases/v7.33.5-fronteira-protecao-shc.md`;
- `sre/architecture/motores-deterministicos.md`;
- `releases/v7.34.0-motores-deterministicos-sre.md`;
- `releases/v7.34.1-correcao-motores-sre-wsl2.md`;
- `releases/v7.34.2-handoff-login-bootstrap.md`;
- `releases/v7.34.3-sbom-terminal-docker-wsl2.md`;
- `sre/architecture/plano-acao-consultivo.md`;
- `releases/v7.35.0-sre-4.md`;
- `sre/architecture/runbooks-homologados.md`;
- `releases/v7.36.0-sre-5.md`;
- `sre/architecture/gate-qualidade-saida-assistente.md`;
- `releases/v7.36.1-gate-qualidade-saida-assistente.md`;
- `releases/v7.36.2-correcao-build-control-center.md`;
- `releases/v7.37.0-preparacao-laboratorio-strix-sre6.md`;
- `sre/architecture/read-only-specialist.md`;
- `sre/manual/usar-diagnostico-seguro.md`;
- `releases/v7.33.0-especialista-sre-read-only.md`.

Validação específica do SRE Knowledge Pack:

```bash
python3 1_codigo_fonte/setupmno-docs/tools/validate-sre-knowledge.py
bash 1_codigo_fonte/setupmno-docs/tools/test-sre-knowledge-validator.sh
bash 1_codigo_fonte/setupmno-docs/tools/test-skill-supply-chain-gate.sh
```

## Regra a partir de agora

Toda nova etapa ou feature do Setup MNO deve atualizar a documentação no mesmo
ciclo em que o código é alterado. A documentação mínima é:

1. objetivo e problema resolvido;
2. público, planos e ambientes afetados;
3. fluxo de uso para leigos;
4. arquitetura e limites de segurança;
5. pré-requisitos e compatibilidade;
6. gates e evidências de validação;
7. falhas conhecidas e FAQ;
8. rollback ou forma segura de desativação;
9. limitações e itens deliberadamente fora do escopo;
10. nota da etapa em `releases/`.

Uma correção pequena pode registrar esses itens em um único arquivo de release.
Uma feature estrutural deve possuir também documento em `architecture/` ou
`manual/`.

## Estados editoriais

- `draft`: proposta ainda não implementada;
- `implemented`: código concluído, aguardando homologação;
- `validated`: homologado nas plataformas declaradas;
- `published`: conteúdo selecionado e publicado no Help;
- `outdated`: não representa mais o comportamento corrente.

O estado documental nunca substitui o estado da release, do selo ou das
evidências técnicas.

## Maturidade das funcionalidades

O estado editorial de um documento e a maturidade da funcionalidade são
informações diferentes. Toda feature deve declarar uma destas classificações:

- `draft`: ainda é projeto e não pode ser apresentada como disponível;
- `beta`: disponível para testes controlados, com limites claramente visíveis;
- `stable`: passou pelos critérios definidos e foi promovida expressamente;
- `deprecated`: ainda funciona, mas será substituída ou removida;
- `retired`: não está mais disponível.

O rótulo BETA deve aparecer antes do uso, dentro da experiência e no Help. O
guia completo está em `manual/politica-de-funcionalidades-beta.md`.

## Definition of Done documental

Antes de declarar uma feature concluída, o mantenedor deve confirmar:

- [ ] documento sem credenciais, IPs, hostnames ou dados de clientes;
- [ ] versão, data, estado e público identificados;
- [ ] maturidade da funcionalidade declarada e consistente nas interfaces;
- [ ] recursos Beta possuem aviso visível antes do uso, limites e canal de
      feedback seguro;
- [ ] comportamento real conferido contra o código distribuído;
- [ ] resumo compreensível sem conhecimento prévio de DevOps;
- [ ] termos técnicos explicados e camada de auditoria técnica preservada;
- [ ] teste contém resultado esperado e sinais claros de falha;
- [ ] síntese preparada para Francis MNO ensinar o assunto à comunidade;
- [ ] riscos e limites descritos sem promessas exageradas;
- [ ] rollback compatível com dados stateful;
- [ ] FAQ atualizada quando a mudança cria uma dúvida previsível;
- [ ] nota de release ligada aos testes executados;
- [ ] conteúdo para o Help tratado como publicação separada.

## Convenções

- idioma principal: português do Brasil;
- nomes de arquivos: minúsculos e separados por hífen;
- exemplos devem usar domínios, nomes e credenciais fictícios;
- comandos destrutivos devem aparecer somente quando indispensáveis, com alvo
  literal e aviso explícito;
- conclusões baseadas em teste, documentação oficial ou inferência devem ser
  distinguidas;
- imagens e vídeos não podem revelar tokens, e-mails, IPs ou instalações de
  clientes.

Use `templates/feature.md` ao iniciar uma nova feature.
