# Control Center v4.31.1 — Visibilidade de funcionalidades Beta

- Versão entregue: Control Center 4.31.1
- Setup MNO associado: 7.31.0
- Estado editorial: `implemented`
- Maturidade da política: `stable`
- Atualizado em: 2026-08-24
- Público: todos os planos

## Para iniciantes — o que foi resolvido

O usuário agora consegue identificar no menu que Blueprints é uma área Beta,
antes de clicar. O Help também explica a diferença entre algo que já pode ser
testado em Beta e algo que ainda está “Em breve”.

## O que mudou

- selo BETA ao lado de Blueprints no menu;
- Assistente MNO e Blueprints identificados como Beta no Help;
- definição de Beta adicionada ao glossário e à FAQ;
- contagem de Blueprints preservada ao lado do selo;
- política documentada para futuras funcionalidades.

Nenhuma permissão, plano, endpoint, stack, ação Docker ou dado persistente foi
alterado.

## Segurança e limites

Beta não reduz controles de segurança e não equivale a homologação completa. Um
Blueprint individual homologado não promove automaticamente toda a área de
Blueprints para estável.

## Gates esperados

- teste frontend confirma o selo BETA antes do contador de Blueprints;
- teste frontend confirma a explicação no Help;
- assets usam a versão de cache 4.31.1;
- gerador x86/ARM, smoke test SHC e empacotador oficial devem concluir sem erro.

## Rollback

Restaurar o commit anterior reverte a apresentação visual. Não há migração de
dados, mudança de banco ou limpeza de volumes.

## Como Francis MNO pode ensinar esta mudança

“Quando você vir BETA, o recurso já pode ser testado, mas ainda está evoluindo.
Quando vir EM BREVE, aquela parte ainda não foi liberada. Nos dois casos, o
Setup MNO deixa a situação visível para você decidir com consciência.”
