# Triagem de Docker Swarm

- Estado: `implemented`
- Atualizado em: 2026-08-23
- Público: mantenedor PRO MASTER e autores do futuro Help
- Ambientes: Docker Swarm em Debian, Ubuntu e WSL2

## Resumo para leigos

Um serviço com `0/1` réplica não explica sozinho a causa. O Swarm possui nós,
estado desejado, tarefas e containers. A tarefa registra por que uma tentativa
falhou; o container atual mostra apenas uma parte da história.

## Objetivo

Diagnosticar o plano de controle e a convergência sem alterar serviços ou
reiniciar o cluster.

## O que observar

Consultas de baseline:

```bash
docker info --format '{{.Swarm.LocalNodeState}} {{.Swarm.ControlAvailable}} {{.Swarm.NodeID}}'
docker node ls
docker stack ls
docker service ls
docker service ps --no-trunc NOME_LITERAL_DO_SERVICO
docker service inspect NOME_LITERAL_DO_SERVICO
docker service logs --tail 100 NOME_LITERAL_DO_SERVICO
```

Use apenas nomes literais já inventariados. Logs devem ser revisados e
sanitizados antes de compartilhamento.

## Ordem de análise

1. **Engine:** o daemon responde?
2. **Swarm:** o nó está ativo e o manager possui controle?
3. **Quorum:** há managers suficientes e alcançáveis?
4. **Estado desejado:** quantas réplicas deveriam existir?
5. **Tarefas:** qual foi a primeira mensagem de rejeição ou falha?
6. **Imagem:** digest e arquitetura são compatíveis com o nó?
7. **Rede e volumes:** os recursos declarados existem e estão acessíveis?
8. **Aplicação:** o processo iniciou, ficou estável e respondeu internamente?

## Padrões comuns

- `no suitable node`: constraint, plataforma, recurso ou disponibilidade do nó.
- `task: non-zero exit`: leia o primeiro log da aplicação e o exit code.
- `rejected`: imagem, mount, secret, config, rede ou definição inválida.
- réplicas oscilando: healthcheck, dependência, memória ou erro de inicialização.
- manager isolado: trate quorum antes de mudanças no serviço.
- imagem por tag mutável: registre o digest observado; a mesma tag pode mudar.

## Backup do estado do Swarm

O estado do manager fica em `/var/lib/docker/swarm`. A documentação do Docker
orienta parar o Docker no manager que será copiado para obter backup consistente.
Isso é manutenção planejada e não deve ser executado por um coletor somente
leitura. O backup do Swarm não substitui backup dos volumes e bancos das
aplicações.

## Limites e segurança

- Não use `docker swarm init --force-new-cluster` como diagnóstico.
- Não remova serviço, stack, nó, rede ou volume para “testar”.
- Não exponha o Docker socket a painel web ou LLM.
- Em cluster de manager único, não prometa alta disponibilidade; documente o
  ponto único de falha e planeje restore.
- Alterações só poderão ocorrer em runbooks fechados das etapas futuras.

## Fontes oficiais

- [Administer and maintain a swarm](https://docs.docker.com/engine/swarm/admin_guide/)
- [Deploy services to a swarm](https://docs.docker.com/engine/swarm/services/)
- [Swarm task states](https://docs.docker.com/engine/swarm/how-swarm-mode-works/swarm-task-states/)
- [Docker service logs](https://docs.docker.com/reference/cli/docker/service/logs/)

## Publicação futura no Help

Exibir a sequência `cluster -> serviço -> tarefa -> container -> aplicação`, com
exemplos visuais de `1/1`, `0/1` e reinício contínuo. O usuário deve aprender a
abrir a tarefa antes de procurar uma correção.
