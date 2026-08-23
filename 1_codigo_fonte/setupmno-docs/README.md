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

## Estrutura

- `architecture/`: projetos arquiteturais, limites de confiança e decisões;
- `manual/`: instruções de uso orientadas a tarefas;
- `faq/`: respostas curtas para dúvidas recorrentes;
- `releases/`: notas humanas das etapas e features criadas a partir desta
  política;
- `templates/`: modelos obrigatórios para manter a documentação consistente;
- `assets/`: inventário de imagens, GIFs e vídeos futuros, sem dados reais de
  clientes.

Documentos atuais de arquitetura e operação:

- `architecture/ai-safe-mode.md`;
- `architecture/supply-chain-sbom.md`;
- `manual/verificar-supply-chain-wsl2.md`;
- `faq/agentes-de-ia-em-vps.md`;
- `faq/supply-chain.md`;
- `releases/v7.30.0-supply-chain-sbom.md`.

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

## Definition of Done documental

Antes de declarar uma feature concluída, o mantenedor deve confirmar:

- [ ] documento sem credenciais, IPs, hostnames ou dados de clientes;
- [ ] versão, data, estado e público identificados;
- [ ] comportamento real conferido contra o código distribuído;
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
