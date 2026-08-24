# Especialista SRE em modo somente leitura

- Estado: `implemented`
- Maturidade: `beta`
- Componente: snapshot SRE `1.0.0`
- Público: todos os planos; governança canônica exclusiva do PRO MASTER
- Ambientes: Debian, Ubuntu, WSL2 e Docker Swarm
- Atualizado em: 2026-08-24

## Resumo para leigos

O Especialista SRE cria uma fotografia pequena da saúde do servidor para ajudar
o Assistente MNO a explicar o que está acontecendo. SRE significa
**Site Reliability Engineering**, prática de manter sistemas disponíveis e
confiáveis usando evidências.

Essa fotografia não é uma chave do servidor. Ela não permite instalar,
reiniciar, apagar ou corrigir nada. O objetivo é observar primeiro e somente
depois orientar o próximo passo seguro.

## Modelo mental

É como o painel de um carro: mostra combustível, temperatura e alertas, mas não
desmonta o motor. A analogia termina aí: o snapshot é uma leitura pontual e não
substitui monitoramento contínuo nem um diagnóstico humano completo.

## Contrato fechado

O agente interno expõe somente `GET /sre/snapshot`, protegido pelo token interno
já usado entre os componentes do Control Center. A rota web autenticada é
`GET /api/sre/snapshot`. Não existem parâmetros, seleção livre de endpoint,
comando, caminho de arquivo ou corpo enviado pelo usuário.

O snapshot possui schema 1, versão `1.0.0`, origem
`agent-fixed-read-only`, indicador `readOnly: true` e maturidade `beta`.
Respostas que não obedecem integralmente ao contrato são recusadas.

## Dados permitidos

- versões do Setup MNO, Control Center, Docker, kernel e sistema operacional;
- arquitetura, CPU, memória, disco, carga e tempo ligado;
- quantidade de nós, aplicações, serviços, réplicas e containers;
- até 60 serviços usando referências opacas válidas somente naquela fotografia;
- até 40 estados recentes de tasks permitidos;
- logs de até oito serviços degradados reduzidos a contagens de sinais de erro,
  alerta, falta de memória ou permissão;
- fatos observados por regras locais e limitações conhecidas.

## Dados proibidos

- hostname, IP, domínio e e-mail;
- nomes reais de stacks e serviços;
- IDs reais do Docker e referências de imagens;
- environment, secrets, credenciais e comandos;
- caminhos ou conteúdo de volumes;
- mensagens de erro de tasks;
- linhas ou conteúdo bruto de logs.

Referências `service-xxxxxxxxxxxx` são hashes temporários com sal aleatório.
Elas permitem relacionar um evento ao serviço dentro do mesmo snapshot, mas não
identificam o serviço real e mudam na próxima coleta.

## Logs sanitizados

O agente lê uma amostra limitada somente quando um serviço está degradado. O
conteúdo é processado localmente e descartado. O snapshot recebe apenas
contagens, como `errorSignals: 2`. Mesmo que uma linha contenha senha, domínio,
e-mail ou dado de cliente, essa linha não é devolvida ao painel ou à LLM.

Uma contagem é um sinal, não uma causa confirmada. Por exemplo, “três sinais de
permissão” orienta a investigação, mas não prova qual arquivo ou volume está
incorreto.

## Fluxo de confiança

```text
Docker socket
  -> agente com endpoints fixos
  -> coleta GET com limites
  -> nomes e conteúdo bruto descartados
  -> schema e política validados
  -> painel autenticado ou Assistente
  -> explicação consultiva
```

O painel web e a stack da LLM continuam sem Docker socket. Somente o agente
interno toca o socket, e seu código não possui proxy Docker genérico nem rota de
escrita. Montar o socket como `:ro` protege o arquivo montado, mas não transforma
a API Docker em somente leitura; a proteção real é a allowlist de rotas no
código, os métodos `GET`, o schema fechado e a ausência de API livre.

## Fatos e hipóteses

`observedFacts` é produzido por regras determinísticas, por exemplo:

- memória abaixo de 70%: fato observado informativo;
- disco acima de 85%: fato observado crítico;
- réplica abaixo do desejado: fato observado de degradação.

`hypotheses` permanece vazio no snapshot. O Assistente pode formular uma
hipótese na explicação, mas deve identificá-la como hipótese e nunca promovê-la
a fato verificado.

## Planos e permissões

Todos os planos recebem o mesmo bloqueio de dados sensíveis e mutações. O modo
básico interpreta localmente. Planos com conector LLM podem enviar somente o
snapshot sanitizado e o conhecimento canônico necessário. PRO MASTER governa
mudanças de política e futuras promoções, mas não recebe um snapshot menos
protegido.

## Limites e falhas seguras

- se o runtime, o Docker ou o contrato estiver inconsistente, o snapshot falha;
- log indisponível é marcado como indisponível, nunca inventado;
- a coleta é pontual e não mantém histórico de telemetria;
- o recurso não substitui Portainer, monitoramento, backup ou resposta a
  incidentes;
- nenhuma recomendação é executada automaticamente.

## Limites e segurança

O recurso observa somente os campos enumerados neste contrato e falha fechado
se o agente devolver schema, origem, limites ou indicadores de privacidade
divergentes. Ele não é um antivírus, não comprova a causa de um incidente e não
concede ao modelo de IA acesso ao Docker socket, ao shell ou a arquivos do host.

## Rollback

Voltar à release anterior remove a rota e faz o Assistente usar o contexto
anterior. Não existe rollback de dados porque o recurso não cria volumes,
serviços ou estado persistente. Não é necessário reiniciar aplicações dos
clientes.

## Fontes oficiais

- https://docs.docker.com/reference/api/engine/
- https://docs.docker.com/engine/security/protect-access/
- https://docs.docker.com/engine/swarm/how-swarm-mode-works/swarm-task-states/
- https://docs.docker.com/reference/cli/docker/service/logs/

## Publicação futura no Help

O Control Center recebe apenas uma explicação curta e o aviso BETA. A versão
completa deste contrato permanece na base humana até passar por revisão
editorial, capturas sanitizadas e testes de compreensão com usuários leigos.
