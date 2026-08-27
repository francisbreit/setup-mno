# Laboratório Strix SRE-6

- Versão planejada: `v7.37.x`
- Versão entregue: preparação candidata `v7.37.1`
- Estado: `implemented`
- Maturidade da funcionalidade: `beta`
- Atualizado em: 27/08/2026
- Responsável pela governança: mantenedor PRO MASTER
- Ambientes: WSL2 e VPS Debian/Ubuntu
- Arquiteturas: AMD64 e ARM64
- Planos afetados: PRO e PRO MASTER

## Para iniciantes — o que isso resolve

Esta etapa prepara um laboratório de segurança sem liberar o teste ofensivo.
Ela confere a identidade do Strix, fixa os arquivos oficiais e cria regras que
impedem acesso ao servidor real. A preparação diagnóstica BETA aparece para
PRO e PRO MASTER, mas termina informando que o executor ainda está bloqueado.
Somente o PRO MASTER pode governar políticas, aprovar exceções ou homologar o
executor.

## Modelo mental ou analogia

É como conferir a identidade, o manual e os lacres de uma ferramenta antes de
construir uma sala de testes. A ferramenta ainda não foi ligada e nenhuma porta
da produção foi aberta.

## Objetivo e critérios de sucesso

- Objetivo: preparar uma fronteira fail closed para o futuro laboratório.
- Evidência: manifesto e contratos válidos; planos e permissões proibidas são
  rejeitados; o assistente termina bloqueado.
- Falha: solicitar alvo, iniciar pentest, baixar executor ou permitir Docker da
  produção nesta candidata.

## Jornada do usuário

1. Um usuário PRO ou PRO MASTER abre o Assistente MNO.
2. O cartão `Laboratório Strix SRE-6 · BETA` explica a preparação.
3. O Terminal Seguro exige nova autenticação.
4. O assistente valida o manifesto e informa `bloqueado até homologação`.
5. Nenhum alvo é pedido; o próximo passo é homologar o executor isolado.

## Visibilidade da maturidade

- [x] BETA no ponto de entrada, cartão e diálogo;
- [x] Help informa o que funciona e o que ainda está bloqueado;
- [x] frontend e backend liberam diagnóstico para PRO e PRO MASTER;
- [x] governança e homologação permanecem no gate PRO MASTER;
- [ ] executor homologado no WSL2 e na VPS;
- [ ] promoção estável declarada por Francis MNO.

## Como funciona por dentro — nota técnica para DevOps

O pacote contém um lock de upstream, dois schemas JSON fechados e um validador
determinístico. O terminal apenas valida esses artefatos e apresenta o estado.
Não existe imagem executora, serviço, stack, rede, volume ou secret do Strix.
`Fail closed` significa que ausência, divergência ou permissão extra bloqueia o
fluxo em vez de tentar continuar.

## Arquitetura e dados

O futuro executor deverá ser efêmero e separado do Terminal Seguro. Ele não
receberá `/var/run/docker.sock`, `/root`, secrets globais nem mounts da
produção. Esta candidata não coleta nem persiste alvos ou achados.

## Permissões e planos

O diagnóstico é permitido a `pro` e `pro-master` no frontend, endpoint de
reautenticação, proxy do terminal e launcher. Governança, exceções e
homologação continuam restritas a `pro-master`. Ocultar o cartão nunca é usado
como autorização.

## Gates

- [x] Bash e contratos;
- [x] versão, licença e hashes do upstream;
- [x] diagnóstico PRO/PRO MASTER e negação dos planos Free;
- [x] governança e homologação exclusivas do PRO MASTER;
- [x] bloqueio sem executor;
- [ ] imagem sandbox por digest;
- [ ] homologação funcional WSL2 AMD64 e VPS ARM64.

## Segurança e privacidade

Nenhuma credencial, alvo, IP, hostname, evidência bruta ou correção é aceita.
Relatórios futuros só poderão conter contagens sanitizadas e expirarão. Selo,
catálogo e remediação automática permanecem proibidos.

## Rollback

Retornar à v7.36.2 remove o ponto de entrada e os contratos. Como nenhum
executor ou dado foi criado, não há stack, volume ou alvo para restaurar.

## FAQ e falhas conhecidas

- O botão executa um pentest? Não; ele confirma que o executor está bloqueado.
- Posso informar um site? Não nesta candidata.
- Funciona para plano PRO? A preparação diagnóstica, sim. Governança,
  exceções e homologação continuam somente no PRO MASTER.
- O upstream é estável? O projeto declara estado Alpha; por isso a integração
  permanece BETA e bloqueada.

## Como testar no WSL2 e na VPS

1. Atualize a candidata e confirme Setup `7.37.1` e Control `4.37.1`.
2. Entre como PRO e abra o cartão Strix BETA; repita com PRO MASTER.
3. Resultado esperado: mensagem `bloqueado até homologação`, sem pedir alvo.
4. Sinal de falha: download, criação de container, pedido de URL ou execução.
5. Confirme que stacks e serviços antes/depois continuam iguais.
6. Confirme que um plano Free recebe bloqueio e que somente PRO MASTER mantém
   as áreas de governança e homologação.

## Glossário mínimo

- Strix: ferramenta externa de teste de segurança assistido por IA.
- Pentest: teste autorizado que procura falhas; nunca deve atingir terceiros.
- Sandbox: ambiente temporário separado do servidor real.

## Como ensinar esta feature

- Objetivo: mostrar que preparar segurança não é o mesmo que executar ataque.
- Demonstração: abrir o cartão e reconhecer o bloqueio explícito.
- Erro comum: acreditar que BETA ou PRO MASTER autoriza qualquer alvo.
- Limite obrigatório: somente autorização escrita e laboratório isolado futuro.

## Publicação futura no Help

O resumo, a jornada, a FAQ e o teste visual podem ser adaptados. Detalhes de
contratos e hashes permanecem na documentação técnica.
