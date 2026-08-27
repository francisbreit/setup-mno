# Runbooks homologados SRE-5

- Versão planejada: Setup MNO 7.36.0 / Control Center 4.36.0
- Versão entregue: candidata v7.36.0
- Estado: `implemented`
- Maturidade da funcionalidade: `beta`
- Atualizado em: 2026-08-27
- Responsável: mantenedor PRO MASTER
- Público: usuários de todos os planos e mantenedor PRO MASTER
- Ambientes: VPS Debian/Ubuntu e WSL2 com Docker Desktop
- Arquiteturas: AMD64 e ARM64
- Planos afetados: Free, Free1, Free2, PRO e PRO MASTER

## Resumo para leigos

O SRE-5 cria uma lista fechada de procedimentos confiáveis, chamados
runbooks. A IA pode indicar um item dessa lista, mas não pode escrever um
comando novo, mudar seus parâmetros nem executá-lo sozinha.

Nesta primeira versão, existem somente três runbooks de leitura: coleta de
evidências, triagem do Docker Swarm e revisão da linha de base de segurança.
Todos levam ao mesmo fluxo SRE-3 já testado. Nenhum deles corrige, reinicia,
instala, atualiza ou remove algo.

## Modelo mental ou analogia

É como um armário de ferramentas lacrado: a IA pode apontar qual ferramenta
aprovada combina com o diagnóstico, mas somente uma pessoa autenticada abre o
armário. A analogia termina aí, pois o backend ainda valida o contrato antes de
mostrar o botão.

## Objetivo e critérios de sucesso

- Objetivo: impedir que uma resposta de IA vire comando livre e permitir
  somente um handoff para operação previamente homologada.
- Evidência esperada: evento SSE `runbook`, registro 1.0.0, maturidade BETA,
  `automaticExecution=false` e `freeCommandAllowed=false`.
- Condição de falha: runbook desconhecido, mutável, parametrizável,
  não homologado ou sem pré-checks, pós-checks, timeout, auditoria e rollback.

## Jornada do usuário

1. O SRE-4 apresenta o plano consultivo.
2. O roteador local verifica se existe runbook fechado compatível.
3. O cartão SRE-5 mostra o escopo, as conferências e os limites.
4. Quando disponível, o usuário escolhe abrir a coleta segura.
5. A senha administrativa e a confirmação humana continuam obrigatórias.
6. O Terminal Seguro executa somente o fluxo SRE já fixado; a IA não recebe
   terminal, Docker socket ou resultado bruto.

## Visibilidade da maturidade

- [x] BETA visível no cabeçalho, cartão e resumo lateral;
- [x] Help explica o que funciona e o que ainda não existe;
- [x] ausência de runbook aparece como indisponível, sem improvisação;
- [x] nenhum texto apresenta a função como automação estável;
- [ ] promoção depende de teste visual no WSL2 e em VPS e declaração de Francis MNO.

## Como funciona por dentro — nota técnica para DevOps

O backend mantém um registro compilado com IDs e versões fixos. A seleção usa
somente a intenção do roteador determinístico e o estado validado do plano
SRE-4. O conteúdo da LLM não participa da decisão.

Antes de enviar os eventos SSE, o servidor valida o plano e o runbook. O
validador falha fechado se houver comando livre, execução automática, mutação,
parâmetro arbitrário, ação diferente de `sre`, item não homologado ou contrato
incompleto. O frontend repete as verificações para decidir se mostra o botão,
mas a autorização real permanece no backend e no Terminal Seguro.

## Arquitetura e dados

- registro fechado 1.0.0 embutido no binário do Control Center;
- três runbooks `homologated`, somente leitura e sem parâmetros;
- handoff fixo `secure-terminal-handoff` para a ação `sre`;
- sem novo endpoint administrativo, porta, volume, mount ou secret;
- sem persistência da pergunta, resposta ou recomendação;
- auditoria existente registra a solicitação do fluxo SRE.

## Permissões e planos

A recomendação aparece em todos os planos. A execução remota continua
disponível apenas quando o Terminal Seguro já é permitido, autenticado e
reconfirmado. Em instalação Tradicional, o usuário acessa o executor por SSH.
PRO MASTER governa o registro canônico, mas também não pode autorizar comando
livre pela interface.

## Gates

- [x] testes unitários de registro, seleção e fail closed;
- [x] mutação e comando livre rejeitados;
- [x] consulta fora do escopo não seleciona operação;
- [x] frontend aceita somente handoff `sre` homologado e somente leitura;
- [x] fonte incluída em build, upgrade, instalador e pacote x86/ARM;
- [x] Help e documentação identificam BETA;
- [ ] atualização visual no WSL2 x86-64;
- [ ] atualização visual em VPS ARM64.

## Limites e segurança

Não há runbook de correção nesta candidata. Operações stateful, isto é,
operações que alteram dados persistentes, continuam bloqueadas até que um
procedimento específico prove backup consistente, restauração e rollback.

A LLM não escolhe IDs arbitrários, não fornece argumentos e não chama o
terminal. Uma recomendação não é autorização. A senha, a política do plano, o
tipo de instalação e a confirmação humana continuam fora do modelo.

## Rollback

Reinstalar a versão estável v7.35.0 pelo fluxo oficial. A reversão remove o
evento e os cartões SRE-5, sem alterar dados nem desfazer auditorias SRE-3 já
criadas. Confirme que Setup 7.35.0 e Control Center 4.35.0 voltaram a aparecer.

## FAQ e falhas conhecidas

- Pergunta: por que não existe botão para corrigir automaticamente?
  Resposta: porque os instaladores atuais ainda não provam de maneira uniforme
  backup, restauração e rollback de todas as aplicações.
- Pergunta: a IA consegue inventar um quarto runbook?
  Resposta: não. O backend aceita somente os três IDs compilados e validados.
- Limitação: os três itens usam a auditoria SRE-3; procedimentos mutáveis ainda
  não fazem parte desta candidata.

## Evidências

- Teste: suíte Go, teste frontend, gerador, manifests e empacotamento.
- Ambiente: repositório de construção; homologação visual ainda pendente.
- Resultado: contrato fechado rejeita mutação, parâmetros e execução automática.
- Limitação: candidata BETA, ainda não declarada estável.

## Como testar no WSL2 e na VPS

1. Atualize um ambiente de homologação para a candidata v7.36.0.
2. Pergunte `Existem serviços com falha?` ou faça uma revisão de segurança.
3. Espere o cartão `SRE-5 · BETA · registro 1.0.0`.
4. Confirme `automaticExecution=false` e `freeCommandAllowed=false` no resumo.
5. Clique em `Abrir coleta segura`, redigite a senha e confira que o diálogo
   continua sendo a Auditoria SRE-3 somente leitura.
6. Cancele no diálogo: nenhum serviço deve reiniciar ou mudar de réplica.

Sinal de falha: ausência do cartão, botão para comando livre, abertura sem
senha ou qualquer alteração automática. O teste não cria recursos temporários.

## Fontes técnicas

- Segurança do Docker Engine: https://docs.docker.com/engine/security/
- Serviços do Docker Swarm: https://docs.docker.com/engine/swarm/services/
- Resposta a incidentes e revisão humana: https://csrc.nist.gov/pubs/sp/800/61/r3/final

## Glossário mínimo

- Runbook: procedimento operacional previamente escrito e revisado.
- Handoff: entrega controlada da intenção para outro componente autorizado.
- Fail closed: bloquear a operação quando uma validação obrigatória falha.
- Stateful: ação que modifica dados persistentes e precisa de restauração.

## Como ensinar esta feature

- Objetivo: explicar que recomendar uma ferramenta não é executá-la.
- Demonstração: pergunta, plano SRE-4, cartão SRE-5 e confirmação no terminal.
- Resultado esperado: o aluno reconhece lista fechada e confirmação humana.
- Erro comum: imaginar que o texto da IA concede autorização.
- Limite obrigatório: nenhum comando livre ou correção automática.

## Publicação futura no Help

A analogia do armário, os três runbooks e a diferença entre recomendação e
autorização podem virar tutorial curto. O registro técnico completo não deve
ser copiado automaticamente para a interface.
