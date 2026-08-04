---
{
  "schemaVersion": 1,
  "documentId": "infra-setupmno-operations-architecture",
  "documentVersion": "1.0.0",
  "contentSHA256": "656b35851fccb94cd2c16d6c8207163068b87aa8e01903e92ec87b2da9a6d27b",
  "documentType": "infrastructure",
  "title": "Operação segura do Setup MNO por Portainer e SSH",
  "topicId": "setupmno-operations",
  "setupVersion": "7.7.15",
  "architectures": ["amd64", "arm64"],
  "category": "operations",
  "status": "reviewed",
  "updatedAt": "2026-08-03",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["operacao", "portainer", "ssh", "diagnostico", "servicos", "logs", "rollback"],
  "sources": [
    {"sourceId":"restart-service","title":"Fluxo autorizado de reinício de serviços","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/restartservice.sh","license":"project-internal","verifiedAt":"2026-08-03"},
    {"sourceId":"uninstall-flow","title":"Fluxo autorizado de remoção","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/uninstall.sh","license":"project-internal","verifiedAt":"2026-08-03"},
    {"sourceId":"control-readme","title":"Arquitetura do Control Center","sourceType":"setup-mno","location":"setupmno-control/README.md","license":"project-internal","verifiedAt":"2026-08-03"}
  ],
  "homologation": {"verifiedAt": null, "verifiedPorts": [], "verifiedImages": []}
}
---
# Operação segura do Setup MNO por Portainer e SSH

## Papel no Setup MNO

É o manual canônico de investigação e recuperação assistida para usuários que
operam o Swarm por Portainer ou por uma sessão SSH própria.

## Princípios

Observar antes de alterar, preservar evidências, separar fato de hipótese,
usar a menor ação reversível e validar o fluxo de negócio depois da mudança.

## Método de diagnóstico

Comece pelo sintoma e pelo impacto: aplicação indisponível, lentidão, tarefa
reiniciando, erro de acesso, falta de espaço ou integração interrompida. Não
reinicie antes de capturar estado, tasks e logs; o reinício pode apagar a
evidência temporal sem corrigir a causa.

Ordem recomendada:

1. confirmar saúde geral, RAM, disco e quantidade de serviços;
2. localizar a stack e o serviço afetados;
3. comparar réplicas desejadas e atuais;
4. inspecionar tasks recentes e motivo de rejeição ou encerramento;
5. ler logs no intervalo do incidente;
6. revisar limites, mounts, redes, secrets e imagem sem expor valores;
7. formular uma hipótese e escolher a menor ação reversível;
8. validar externamente e preparar rollback.

## Leitura por Portainer

No Portainer, selecione o endpoint correto antes de qualquer inspeção.

- **Swarm > Services:** confirma réplicas, imagem e distribuição das tasks.
- **Stacks:** identifica se a stack é editável, seu arquivo e os serviços que a
  compõem. Não edite uma stack limitada como se o Portainer fosse sua origem.
- **Service > Tasks:** mostra nó, estado atual, estado desejado e erros de
  agendamento ou inicialização.
- **Service logs:** use janela curta ao investigar incidentes e remova qualquer
  credencial antes de compartilhar trechos.
- **Containers:** é uma visão da réplica atual. Alterar apenas um container de
  serviço Swarm não altera a especificação e pode ser perdido no reagendamento.
- **Networks, Volumes, Configs e Secrets:** confirme vínculos e nomes. Nunca
  exclua um volume para tentar corrigir um erro de aplicação.
- **Nodes:** confirme Manager/Worker, disponibilidade Active/Pause/Drain e
  recursos. Drenar um nó pode mover workloads stateless, mas não move dados de
  volumes locais.

## Leitura por SSH

Os comandos abaixo são diagnósticos comuns de somente leitura. O usuário deve
executá-los no Manager por uma sessão SSH própria e compartilhar apenas a parte
necessária, sem hostname, IP, tokens ou secrets.

```text
docker info
docker node ls
docker service ls
docker service ps --no-trunc NOME_DO_SERVICO
docker service inspect --pretty NOME_DO_SERVICO
docker service logs --since 30m --tail 200 NOME_DO_SERVICO
docker stack services NOME_DA_STACK
docker network ls
docker volume ls
docker secret ls
docker system df
free -h
df -h
uptime
journalctl -u docker --since "30 minutes ago" --no-pager
```

`docker secret ls` mostra nomes e metadados, não valores. Nunca peça ao usuário
para imprimir, copiar ou colar conteúdo de Secrets. Antes de sugerir um comando
com nome de stack ou serviço, confirme o nome real no inventário.

## Ações mutáveis sob confirmação

Reiniciar, escalar, atualizar, reverter, drenar nó ou remover recurso altera o
estado. O Assistente pode explicar o procedimento e seus critérios, mas deve
marcá-lo como ação mutável, exigir confirmação humana e preferir o Instalador
Seguro ou Portainer quando existir um fluxo autorizado.

Um reinício controlado de serviço Swarm recria tasks; ele não limpa banco,
volume nem Redis. Antes de fazê-lo, registre réplicas, imagem, erro e logs.
Depois, acompanhe o estado das novas tasks e valide a aplicação. Reinícios
repetidos sem mudança de hipótese indicam que a causa ainda não foi encontrada.

Escala só é segura quando a aplicação suporta múltiplas réplicas, sessões e
persistência compartilhada. Bancos, filas e aplicações com volumes locais não
devem ser escalados por tentativa. Uma atualização exige imagem confiável,
compatibilidade de schema, backup, política de update e procedimento de
rollback.

## Diagnósticos por sintoma

### Réplicas 0/1 ou reiniciando

Inspecione tasks e logs. Causas possíveis incluem imagem ausente, erro de
configuração, secret inexistente, mount inválido, falta de recurso, healthcheck
ou porta em uso. A condição confirma falha, mas não escolhe a causa sozinha.

### Aplicação saudável sem acesso externo

Separe aplicação, rede overlay, proxy, TLS e DNS. Confirme se o serviço está na
rede externa adequada e se a rota corresponde ao modelo Cloudflare ou Traefik.
Não altere DNS antes de confirmar o serviço internamente.

### Disco alto

Identifique filesystem, volumes, logs e imagens. `docker system df` é leitura;
comandos de prune são destrutivos e não devem ser recomendados genericamente.
Proteja bancos e volumes e estabeleça retenção de logs e backup antes da
limpeza.

### Redis com problema

Identifique qual Redis pertence à aplicação. Novos setups usam Redis dedicado;
limpar a instância errada pode encerrar sessões, filas ou cache de outro
sistema. Confirme finalidade, persistência e impacto. Limpeza de dados nunca é
passo inicial de diagnóstico.

### Banco de dados indisponível

Confirme task, volume, espaço, logs e rede. Não recrie banco, volume ou usuário.
Valide backup e integridade antes de qualquer migração ou reparo.

## Critério de recuperação

Uma ação só termina quando réplicas permanecem estáveis, healthcheck está
saudável, logs não repetem o erro, acesso interno e externo funciona e o fluxo
de negócio principal foi testado. Métrica verde isolada não prova que uma
integração ponta a ponta voltou a funcionar.

O rollback deve restaurar a especificação anterior sem apagar dados criados
depois da mudança. Se uma migração de banco não for retrocompatível, o rollback
da imagem sozinho pode falhar; por isso backup e documentação da migração vêm
antes da atualização.

## Validação

Confirme réplicas estáveis, healthcheck, ausência do erro recorrente nos logs,
acesso interno e externo e o fluxo principal da aplicação. Registre a condição
anterior e a condição recuperada.

## Riscos e limites

Não orientar `docker system prune`, remoção de volume, exclusão de stack,
recriação de banco, exposição de Secret, mudança de quorum ou reset de Swarm
como tentativa genérica. Não apresentar comando mutável como diagnóstico de
somente leitura. Não afirmar que uma ação foi executada pelo Assistente.
