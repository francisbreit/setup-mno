---
{
  "schemaVersion": 1,
  "documentId": "infra-setupmno-platform-architecture",
  "documentVersion": "1.0.0",
  "contentSHA256": "34cae5154db7e13ac23233e297d467111bde4a6656febdb56722aeeb96192932",
  "documentType": "infrastructure",
  "title": "Arquitetura operacional da plataforma Setup MNO",
  "topicId": "setupmno-platform",
  "setupVersion": "7.7.50",
  "architectures": ["amd64", "arm64"],
  "category": "architecture",
  "status": "reviewed",
  "updatedAt": "2026-08-03",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["setup-mno", "docker-swarm", "manager", "worker", "portainer", "arquitetura", "alta-disponibilidade"],
  "sources": [
    {"sourceId":"dockerswarm-x86","title":"Preparação Docker Swarm x86","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/dockerswarm.sh","license":"project-internal","verifiedAt":"2026-08-03"},
    {"sourceId":"installer-x86","title":"Orquestrador principal x86","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/install.sh","license":"project-internal","verifiedAt":"2026-08-03"},
    {"sourceId":"control-readme","title":"Arquitetura do Control Center","sourceType":"setup-mno","location":"setupmno-control/README.md","license":"project-internal","verifiedAt":"2026-08-03"}
  ],
  "homologation": {"verifiedAt": null, "verifiedPorts": [], "verifiedImages": []}
}
---
# Arquitetura operacional da plataforma Setup MNO

## Papel no Setup MNO

É a referência canônica para explicar como host, Swarm, entrada, dados,
aplicações, Portainer e Control Center formam uma única plataforma operacional.

## Visão de conjunto

O Setup MNO é um acelerador de deploys sobre Docker Swarm. A instalação inicial
cria um Swarm com um nó Manager e prepara redes, proxy de entrada, serviços de
infraestrutura e Portainer. Os setups adicionam stacks e serviços a esse plano
de execução. O Control Center observa o ambiente, apresenta inventário e
métricas e orienta o usuário; ele não substitui o Swarm, o Portainer nem o
Instalador Seguro.

## Planos da arquitetura

- **Plano de infraestrutura:** host Linux ou WSL2, Docker Engine ou Docker
  Desktop, Swarm, redes overlay, volumes, secrets e nós.
- **Plano de entrada:** Cloudflare Tunnel ou Traefik tradicional. Só um modelo
  deve ser tratado como autoridade de publicação de cada hostname.
- **Plano de dados:** bancos, filas, caches e volumes persistentes. O ciclo de
  vida dos dados é diferente do ciclo de vida dos containers.
- **Plano de aplicações:** stacks instaladas individualmente ou em combos. Um
  serviço pode possuir uma ou mais réplicas e cada réplica gera uma task.
- **Plano de operação:** Portainer, SSH e Instalador Seguro. Alterações reais
  permanecem sob confirmação humana.
- **Plano de observação:** agente somente leitura, página Visão Geral,
  inventário, saúde de réplicas e Assistente MNO consultivo.

## Topologia inicial

A topologia homologada de entrada é um Swarm de nó único, no qual o mesmo host
é Manager e executa workloads. Isso simplifica instalação, volumes locais,
Portainer e diagnóstico. Não equivale a alta disponibilidade: a falha desse
host interrompe quorum, aplicações e dados que existam somente nele.

O Manager mantém o estado Raft do Swarm, agenda serviços e participa do plano
de dados. Serviços com `node.role == manager` permanecem nesse nó. Bancos e
aplicações com volumes locais também dependem do host que contém os dados.

## Componentes persistentes e efêmeros

Containers e tasks são descartáveis. Stacks, especificações de serviços,
Docker Secrets, configs, redes e volumes formam o estado necessário para
reconstrução. Dados de negócio ficam nos bancos e volumes, não na camada
gravável do container.

Uma atualização segura preserva volumes, secrets e configuração compatível,
observa a nova task saudável e só depois encerra a anterior. Remover uma stack
não deve ser confundido com remover volumes. Backup precisa abranger dados,
configuração, chaves de criptografia das aplicações e o estado necessário para
restaurar o serviço.

## Portainer no ecossistema

Portainer é a interface operacional permanente. Ele permite inspecionar
stacks, serviços, tasks, réplicas, logs, redes, volumes, configs, secrets e nós.
Stacks criadas pelo fluxo editável são administradas pelo Portainer; stacks
criadas diretamente no Docker podem aparecer como controle limitado. O
Assistente deve explicar essa diferença antes de orientar uma edição.

O valor de um Secret nunca deve ser solicitado no chat. O Portainer pode
mostrar metadados e vínculos, mas a rotação deve seguir o instalador ou um
procedimento explícito com validação e rollback.

## Caminho para escala horizontal

O Setup MNO nasce com um Manager, mas o Swarm admite novos Managers e Workers.
Essa evolução exige projeto, não apenas o comando de ingresso.

1. Definir endereços estáveis, conectividade entre nós, portas do Swarm,
   latência, firewall e resolução de nomes.
2. Para tolerância a falhas do controle, usar número ímpar de Managers,
   normalmente três. Dois Managers não oferecem a mesma segurança de quorum.
3. Manter e testar backup do estado do Swarm antes de alterar o conjunto de
   Managers. Tokens de ingresso nunca devem ser enviados ao Assistente.
4. Adicionar Workers para capacidade de execução e aplicar labels e
   constraints deliberadamente.
5. Revisar serviços presos ao Manager, redes overlay, imagens disponíveis em
   todos os nós e limites de CPU/RAM.
6. Resolver persistência multi-nó. Volume local não acompanha uma task movida
   para outro host; bancos e aplicações stateful precisam de estratégia de
   armazenamento, replicação e recuperação compatível.
7. Validar drenagem de nó, reagendamento, falha de rede e recuperação antes de
   considerar a arquitetura altamente disponível.

Adicionar Workers não torna bancos altamente disponíveis e adicionar Managers
não replica automaticamente volumes. O Assistente deve separar capacidade,
quorum, persistência e disponibilidade em toda recomendação de escala.

## Control Center

O Control Center usa stacks separadas para painel, agente, terminal e, somente
no plano PRO quando configurado, conector de LLM. O painel não recebe Docker
socket. O agente expõe apenas leituras fixas. O terminal autenticado é o único
componente que abre o instalador original e permanece limitado a uma sessão.

Nos planos free, free1 e free2, o Control Center mantém inventário, métricas,
catálogo, terminal e diagnóstico básico local. O conector de LLM não é criado
nem utilizado. No plano PRO, o Assistente pode usar a base canônica e métricas
sanitizadas, mas continua sem shell, Docker socket ou permissão de escrita.

## Princípios

O Assistente deve primeiro identificar o tipo de instalação, o plano, a
arquitetura, o estado do Swarm, as réplicas e os recursos observados. Depois
deve separar fatos runtime, documentação canônica e hipótese. Comandos SSH e
passos no Portainer são instruções para execução humana; nunca significam que
o Assistente executou a ação.

Para toda mudança, a ordem segura é: observar, registrar estado anterior,
confirmar backup, alterar uma variável por vez, acompanhar tasks e logs,
validar a aplicação e preservar uma rota de rollback.

## Validação

Confirme topologia e papel dos nós, réplicas, redes, persistência, tipo de
entrada e backup. Em escala horizontal, teste quorum, drenagem, reagendamento,
acesso a imagens e dados antes de declarar disponibilidade.

## Riscos e limites

Nó único é simples, mas concentra falhas. Managers adicionais não replicam
volumes; Workers adicionais não tornam bancos altamente disponíveis. O
Assistente orienta e classifica comandos, mas não executa mudanças.
