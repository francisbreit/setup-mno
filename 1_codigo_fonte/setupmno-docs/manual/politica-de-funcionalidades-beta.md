# Política de funcionalidades Beta

- Estado editorial: `implemented`
- Maturidade da política: `stable`
- Público: todos os planos e mantenedor PRO MASTER
- Ambientes: Control Center, instaladores, catálogo, Help e materiais comerciais

## Para iniciantes — o que significa Beta

Uma funcionalidade **Beta** já existe e pode ser testada, mas ainda está sendo
amadurecida. Ela pode mudar, apresentar limites ou ainda não ter sido validada
em todas as situações previstas.

O aviso não significa que o recurso pode ignorar segurança. Senha, dados,
permissões e acesso ao servidor devem receber as mesmas proteções usadas nas
funcionalidades estáveis.

**Em breve** é diferente: significa que a funcionalidade ou o material ainda
não está disponível. Um recurso já utilizável não deve ser escondido como “Em
breve”, e uma promessa futura não deve ser apresentada como Beta.

## Modelo mental

Beta é como uma estrada aberta em período de testes. Ela possui sinalização,
limites e regras de segurança, mas ainda está sendo observada antes de receber a
classificação definitiva. A placa precisa aparecer antes de o motorista entrar,
não somente no final da estrada.

## Onde a informação deve aparecer

Quando a interface possuir esses elementos, o rótulo **BETA** deve aparecer:

1. no menu, botão ou cartão usado para entrar;
2. no cabeçalho ou introdução da funcionalidade;
3. nas ações e diálogos em que uma decisão relevante é tomada;
4. no Help e nos tutoriais;
5. na comunicação comercial que descreve o recurso.

Além do rótulo, o texto deve explicar:

- o que já funciona;
- o que ainda não foi homologado;
- qual cuidado o usuário deve tomar;
- como enviar feedback sem compartilhar segredos ou dados pessoais.

## Como funciona por dentro — nota técnica para DevOps

A maturidade da funcionalidade e o estado de seus artefatos são dimensões
independentes. Um Blueprint individual pode estar `homologated`, enquanto o
módulo de Blueprints continua `beta`. A promoção de um artefato não deve alterar
implicitamente o lifecycle do módulo.

Novas features devem declarar um estado fechado:

- `draft`;
- `beta`;
- `stable`;
- `deprecated`;
- `retired`.

O frontend não é a única fonte de controle. Recursos Beta continuam sujeitos às
mesmas verificações de autorização no backend, agente, terminal e instalador. A
ausência da etiqueta é uma falha de comunicação; a ausência do controle no
backend é uma falha de segurança.

## Estado atual conhecido

- **Assistente MNO:** Beta. Oferece diagnóstico e orientação, mas não executa
  comandos e suas respostas exigem revisão humana.
- **Área de Blueprints:** Beta. Os guias podem ser consultados, mas a área ainda
  está em amadurecimento.
- **Manual completo de Blueprints:** Em breve. Isso não significa que a área
  Beta esteja indisponível.

Essa lista deve ser atualizada quando Francis MNO promover ou retirar uma
funcionalidade.

## Critérios para sair do Beta

Uma funcionalidade somente pode ser promovida para estável quando possuir:

1. escopo e limites documentados;
2. critérios objetivos de sucesso;
3. testes nos ambientes e arquiteturas declarados;
4. falhas conhecidas e comportamento controlado;
5. rollback compatível com os dados envolvidos;
6. Help revisado;
7. declaração explícita de Francis MNO.

Remover a etiqueta sem essas evidências é uma falha de release.

## Como testar no WSL2 e na VPS

Esta política não exige uma infraestrutura especial. Depois de atualizar o
Control Center:

1. abra o painel em um navegador desktop;
2. confirme que Blueprints e Assistente MNO mostram **BETA** antes do clique;
3. abra Blueprints e confirme o aviso sobre homologação incompleta;
4. abra o Help e pesquise por `beta`;
5. confirme que o texto diferencia **BETA** de **EM BREVE**;
6. repita em um celular ou em modo responsivo e verifique se os rótulos continuam
   legíveis.

Sinal de falha: um recurso Beta aparece como estável, não possui aviso antes do
uso ou mistura a informação com “Em breve”.

## Rollback

Se o rótulo prejudicar a interface, restaure o frontend anterior, mas mantenha a
classificação Beta na documentação e não promova o recurso para estável. O
rollback visual não altera a maturidade real da funcionalidade.

## Como Francis MNO pode ensinar esta regra

“Beta quer dizer que você já pode conhecer e testar o recurso, mas ele ainda
está evoluindo. Leia os avisos e não trate o resultado como homologação completa.
Em breve é diferente: quer dizer que aquela parte ainda não foi liberada.”
