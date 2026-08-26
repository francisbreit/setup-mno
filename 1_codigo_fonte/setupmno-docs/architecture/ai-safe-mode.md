# Projeto arquitetural — AI Safe Mode

- Estado: `draft`
- Tipo: segurança, governança, UX e produtividade
- Impacto: crítico
- Esforço: estrutural e incremental
- Atualizado em: 2026-08-23
- Baseline observada: Setup MNO `v7.29.0`
- Última versão estável declarada: `v7.34.3`
- Implementação de runtime: não iniciada

## 1. Visão executiva

O AI Safe Mode transforma agentes de IA em copilotos limitados do Setup MNO.
Ele permite diagnóstico, explicação, pesquisa e preparação de mudanças sem
transformar Codex, Claude Code, Hermes Agent, OpenClaw ou outro agente em
administrador root do servidor.

O contrato central é:

```text
IA interpreta e propõe
  -> gates determinísticos verificam
  -> laboratório isolado comprova
  -> humano autoriza
  -> Instalador Seguro executa
  -> monitoramento valida
  -> rollback restaura quando for seguro
```

Prompt, memória, modelo, RAG e aprovação textual não são controles de
autorização. Toda autoridade deve ser aplicada fora do modelo.

## 2. Objetivos

1. permitir que leigos obtenham diagnóstico útil sem entregar acesso amplo;
2. oferecer aos operadores experientes evidência, diff, dry-run e automação
   controlada;
3. reduzir instalações improvisadas diretamente em `/root`;
4. preparar aplicações candidatas fora do catálogo sem tocar na produção;
5. aproveitar o Homologation Runner, o importador canônico e os gates do Setup
   MNO em vez de criar uma segunda esteira;
6. tornar segurança, rastreabilidade e rollback diferenciais mensuráveis do
   produto;
7. orientar escala vertical e horizontal sem prometer alta disponibilidade
   automática para dados stateful.

## 3. Fora do escopo inicial

- shell genérico remoto para a IA;
- mount de `/var/run/docker.sock` no Assistente ou no sandbox;
- execução como root;
- publicação automática de stack, DNS, Cloudflare, catálogo ou release;
- alteração automática de managers, quorum ou estado Raft;
- migração autônoma de banco ou volume;
- correção automática baseada somente na resposta de uma LLM;
- ingestão irrestrita de logs, `.env`, secrets, chaves ou arquivos do cliente;
- promessa de que um scanner ou uma IA elimina todos os riscos.

## 4. Modelo de ameaça

### 4.1 Ativos protegidos

- host, kernel, usuários e chaves SSH;
- daemon Docker, Swarm e estado Raft;
- stacks, configs, secrets, redes e volumes;
- bancos, filas, objetos e backups;
- tokens de Cloudflare e provedores de IA;
- código SHC, licenciamento e artefatos de distribuição;
- dados, domínios e identidade dos clientes;
- governança, selos e ledger do mantenedor.

### 4.2 Ameaças consideradas

- comando incorreto ou inventado pelo modelo;
- prompt injection em README, página web, issue, log ou saída de ferramenta;
- exfiltração de dados por prompt, ferramenta, MCP ou acesso de rede;
- execução acidental como root ou membro do grupo `docker`;
- dependência, plugin, skill, MCP ou imagem comprometida;
- instalação com tag móvel ou artefato sem proveniência;
- colisão de portas, rotas, nomes, volumes ou redes;
- alteração de serviço stateful sem backup restaurável;
- falsa sensação de segurança causada por resultado parcial de scanner;
- fadiga de aprovação e aceitação automática pelo usuário leigo;
- bypass de frontend quando backend não aplica a mesma autorização;
- concorrência entre duas sessões alterando o mesmo alvo.

### 4.3 Princípio de contenção

O sistema deve assumir que a saída do modelo e todo conteúdo externo são não
confiáveis. Uma IA comprometida ou profundamente equivocada deve conseguir, no
máximo, danificar seu próprio workspace descartável.

## 5. Zonas de confiança

```text
Z0 - Produção
     Docker Swarm, dados, secrets e Setup MNO existente
     ^ nenhuma IA possui acesso direto

Z1 - Gate determinístico
     políticas, validadores, manifests e Instalador Seguro
     ^ aceita somente ações e formatos fixos

Z2 - Diagnóstico sanitizado
     snapshot somente leitura, agregado e sem identidade do cliente
     ^ única fonte operacional normal para a IA

Z3 - Workspace/sandbox
     usuário sem privilégio, filesystem próprio, recursos limitados
     ^ local onde a IA pode criar candidatos

Z4 - Provedor/modelo e conteúdo externo
     sempre não confiável
```

Fluxos de Z3 ou Z4 para Z0 são proibidos. Uma proposta precisa atravessar Z1 e,
quando executável, ser comprovada em homologação isolada antes da confirmação
humana.

## 6. Componentes propostos

### 6.1 Safe Mode UI

Nova jornada no Control Center. Não recebe Docker socket, mount do host ou API
de shell. Mostra objetivo, escopo, dados coletados, plano, gates, evidências,
risco e próximo passo.

### 6.2 Diagnostic Snapshot

Extensão estritamente somente leitura dos endpoints permitidos do agente
existente. Produz um objeto pequeno e sanitizado com:

- versão e arquitetura;
- memória, disco e CPU agregados;
- estado e réplicas dos serviços;
- alertas derivados de regras locais;
- catálogo relevante;
- identificadores opacos somente durante a sessão.

Não expõe hostname, IP, domínio, e-mail, imagem privada, secret, environment,
comando, log bruto ou conteúdo de volume.

### 6.3 AI Connector

Reutiliza a stack isolada prevista para o Assistente MNO. Continua sem socket,
shell, terminal, host mount, porta publicada, Traefik ou rota própria. Recebe
somente o snapshot sanitizado e devolve explicação ou proposta estruturada.

### 6.4 Policy Gate

Validador determinístico fora do modelo. Avalia um manifesto de proposta com
schema fechado; texto livre nunca vira comando. Deve bloquear, entre outros:

- `privileged`, host PID/IPC/network e capabilities amplas;
- Docker socket ou mounts de caminhos sensíveis;
- portas não autorizadas ou em conflito;
- secrets em environment, YAML, argumentos ou logs;
- imagens sem digest na promoção;
- tags móveis na produção;
- ausência de limites e healthcheck quando aplicável;
- rotas Traefik duplicadas;
- nomes fora do namespace da homologação;
- arquiteturas não comprovadas;
- escrita no host e alteração de recursos preexistentes;
- ações de Swarm, banco ou storage fora da lista permitida.

### 6.5 Isolated Workspace

Ambiente descartável ou persistente por projeto, mas nunca compartilhado com
produção. Identidade proposta: `mno-agent`, sem `sudo`, sem grupo `docker` e
sem acesso a `/root`.

Controles mínimos:

- root filesystem somente leitura quando tecnicamente possível;
- `cap_drop: ALL` e `no-new-privileges`;
- limites de CPU, memória, PIDs e disco;
- rede desativada por padrão; allowlist temporária quando indispensável;
- workspace dedicado, sem mounts do host além dele;
- credenciais efêmeras e específicas da tarefa, com escopo mínimo;
- nenhuma credencial herdada do operador;
- limpeza ou snapshot controlado ao terminar.

No WSL2, o workspace não deve residir em `/root` nem herdar automaticamente o
perfil do usuário administrador. Em VPS, o agente não deve compartilhar a
conta SSH usada para administrar o servidor.

### 6.6 Homologation Bridge

Não é uma API genérica para Docker. Converte somente propostas que passaram
pelos gates em pacotes de laboratório compatíveis com o processo existente.
Recursos recebem identificador `setupmno-hml-<aplicacao>-<datahora-curta>` e
inventário literal para limpeza.

### 6.7 Secure Installer Handoff

Uma proposta aprovada não executa por conta própria. A interface abre o fluxo
determinístico adequado do Instalador Seguro. A ação, os parâmetros e o alvo
devem ser conhecidos; comandos livres são proibidos.

### 6.8 Audit Ledger

Registra sem conteúdo sensível:

- ator, plano e intenção;
- modelo/conector e versão da política;
- hash do snapshot sanitizado;
- hash da proposta;
- gates e decisões;
- confirmação humana;
- resultado e rollback;
- tempos e IDs opacos de correlação.

## 7. Perfis de permissão

### 7.1 Regra universal

Segurança não é benefício premium. Todos os planos devem receber bloqueios de
root, socket, secrets, ações destrutivas e aviso de exposição. Recursos de
produtividade podem variar, mas a plataforma nunca oferece um modo inseguro
para compensar limitação comercial.

### 7.2 Matriz funcional proposta

| Capacidade | free/free1/free2 | pro | pro-master |
|---|---:|---:|---:|
| Conteúdo educativo e FAQ | sim | sim | sim |
| Diagnóstico básico local e sanitizado | sim | sim | sim |
| Explicação por conector LLM configurado | conforme oferta | sim | sim |
| Criar proposta em workspace isolado | não inicialmente | sim | sim |
| Homologar candidato próprio em laboratório | não | conforme política futura | sim |
| Criar ou alterar políticas | não | não | sim |
| Aprovar exceção | não | não | sim |
| Importar no repositório canônico | não | não | sim |
| Publicar release | não | não | somente Workflow de Produção |

A matriz comercial final precisa ser confirmada antes da implementação. A
negação técnica deve existir no backend e nos componentes de execução, nunca
somente por botão oculto.

### 7.3 Permissões do agente

| Recurso | Padrão | Exceção possível |
|---|---|---|
| Ler snapshot sanitizado | permitido | nenhuma ampliação direta |
| Ler workspace próprio | permitido | somente caminho canônico |
| Escrever workspace próprio | permitido em modo proposta | nunca produção |
| Rede externa | negada | allowlist por tarefa e tempo |
| Secrets | negado | credencial efêmera específica |
| Docker socket | negado | nenhuma |
| Root/sudo | negado | nenhuma |
| `/root`, `/etc`, `/var/lib/docker` | negado | nenhuma |
| DNS/Cloudflare | negado | fluxo determinístico separado |
| Executar em produção | negado | Instalador Seguro, sem IA |

## 8. UX para leigos

### 8.1 Entrada por objetivo

Evitar termos como MCP, Raft, digest ou policy engine na primeira tela. As
quatro escolhas iniciais devem ser:

1. **Entender um problema**;
2. **Planejar uma nova aplicação**;
3. **Verificar a segurança**;
4. **Avaliar se o servidor precisa crescer**.

### 8.2 Jornada guiada

1. **Objetivo:** pergunta curta em linguagem natural.
2. **Escopo:** o Setup MNO mostra quais serviços ou métricas serão consultados.
3. **Privacidade:** lista simples do que será e não será enviado.
4. **Análise:** heartbeat real, operação atual e tempo decorrido.
5. **Resposta:** explicação curta, risco e recomendação.
6. **Proposta:** diff humano e resumo “o que mudaria”.
7. **Gates:** cartões verdes, amarelos e vermelhos com causa e solução.
8. **Laboratório:** execução opcional isolada, com aviso de que produção não foi
   alterada.
9. **Decisão:** voltar, exportar relatório ou abrir Instalador Seguro.
10. **Recibo:** evidências, resultado, limitações e rollback aplicável.

### 8.3 Linguagem obrigatória

- faixa persistente **Nenhuma alteração foi realizada** durante análise;
- diferenciar **sugestão da IA** de **resultado verificado**;
- proibir botão genérico “Corrigir tudo”;
- usar “Bloqueado por segurança” com explicação acionável;
- esconder comandos por padrão e oferecer **Ver detalhes técnicos**;
- informar quando não há evidência suficiente;
- informar quando rollback não é seguro para dados;
- sempre oferecer **Cancelar e sair sem alterações**.

### 8.4 Redução da fadiga de aprovação

O usuário não deve confirmar dezenas de operações técnicas. A interface agrupa
uma mudança em uma intenção clara, mas mantém confirmações separadas quando
houver:

- exposição pública;
- credencial ou provedor externo;
- dado persistente;
- mudança de banco;
- indisponibilidade prevista;
- ação sem rollback automático.

Confirmação nunca autoriza ação diferente da exibida. Mudança de hash invalida
o token e exige nova revisão.

### 8.5 Modo técnico

Operadores experientes podem ver YAML renderizado, digests, SBOM, recursos,
constraints, update config, logs sanitizados, policy IDs e plano de rollback.
Isso não concede shell ou autoridade adicional.

## 9. Gates obrigatórios

### G0 — Baseline

- versão e arquitetura;
- estado do plano e tipo de instalação;
- capacidade, disco e disponibilidade do Docker;
- estado do Swarm e inventário somente leitura;
- Git e runtime compatíveis, quando aplicável.

Falha ou dado ausente resulta em bloqueio.

### G1 — Identidade e sessão

- usuário autenticado;
- autorização no backend;
- sessão com expiração;
- uma intenção fixa;
- proteção contra duas mutações concorrentes no mesmo alvo.

### G2 — Isolamento

- usuário sem root e sem grupo Docker;
- sandbox ativo;
- mounts, capabilities, rede e limites conferidos;
- workspace canônico sem symlink ou fuga de caminho.

### G3 — Privacidade

- schema de entrada permitido;
- sanitização de hostname, IP, domínio, e-mail e imagens privadas;
- bloqueio de tokens, chaves, `.env` e logs brutos;
- tamanho e retenção limitados;
- `store: false` quando o conector suportar esse contrato.

### G4 — Cadeia de suprimentos

- origem e licença;
- imagem por digest;
- assinatura ou atestação quando disponível;
- SBOM;
- vulnerabilidades e secrets;
- plugins, skills e MCPs inventariados e permitidos.

Este gate depende da próxima etapa canônica de SBOM e atestação.

### G5 — Política da proposta

- schema fechado;
- nenhuma ação arbitrária;
- recursos, portas, rotas, secrets, mounts e privilégios permitidos;
- compatibilidade AMD64/ARM64 declarada e comprovável;
- limits, healthcheck e update/rollback config adequados;
- banco e storage classificados como stateful.

### G6 — Renderização e dry-run

- Bash/YAML/JSON válidos;
- stack renderizada sem interpolação inesperada;
- diff determinístico;
- nenhuma referência fora do workspace;
- hash do plano ligado à aprovação.

### G7 — Homologação isolada

- namespace exclusivo;
- portas verificadas antes de publicação;
- convergência, estabilidade, logs e resposta;
- digest real;
- reinício e persistência somente quando incluídos no escopo;
- inventário de limpeza completo.

### G8 — Segurança operacional

- scan de imagem, configuração e secrets;
- sem Docker socket, privileged ou host namespace;
- exposição mínima;
- credenciais por Docker Secret quando aplicável;
- exceções classificadas e nunca aprovadas pelo próprio modelo.

### G9 — Aprovação humana

- resumo leigo e diff técnico;
- risco, indisponibilidade e rollback;
- token ligado ao conteúdo exato;
- PRO MASTER para exceções e promoção canônica.

### G10 — Handoff para produção

- execução somente pelo Instalador Seguro ou Workflow de Produção;
- backup prévio quando há dados;
- janela e timeout definidos;
- imagem anterior e configuração anterior preservadas;
- sem publicação automática pela IA.

### G11 — Pós-deploy

- convergência e healthcheck;
- teste funcional mínimo;
- métricas e logs sanitizados;
- comparação com baseline;
- rollback acionado ou recomendado conforme política.

### G12 — Evidência

- recibo sanitizado e imutável;
- hashes, gates e decisão;
- resultado de limpeza do laboratório;
- limitações explícitas;
- nenhuma concessão automática de selo ou release.

## 10. Estratégia de rollback

Rollback deve ser projetado junto com a mudança. “Voltar a imagem anterior” não
é suficiente quando há migração de banco ou alteração de volume.

### 10.1 Classes

#### Classe A — diagnóstico

Não altera estado. Encerrar sessão e apagar dados temporários é suficiente.

#### Classe B — workspace

Usar snapshot ou commit local. Reverter somente arquivos do workspace e
revogar credenciais efêmeras.

#### Classe C — homologação

Remover apenas recursos presentes no inventário literal da execução. Confirmar
ausência de stack, serviço, container, volume, rede, config, secret e diretório
com o identificador atual.

#### Classe D — serviço stateless em produção

Preservar digest e spec anteriores, validar compatibilidade e usar rollback
controlado do serviço. Confirmar réplicas, healthcheck, rota e métricas.

#### Classe E — dados stateful

Exigir backup consistente e restore testado ou estratégia nativa de reversão.
Se a migração não for reversível, bloquear rollback automático e exigir plano
de recuperação específico aprovado antes do deploy.

#### Classe F — Swarm e infraestrutura crítica

Managers, quorum, Raft, storage, firewall, DNS e identidade ficam fora da
automação inicial. Mudanças futuras exigirão runbook, backup dedicado, janela,
operador experiente e recuperação ensaiada.

### 10.2 Gatilhos

- serviço não converge no timeout;
- healthcheck ou resposta funcional falha;
- crescimento anormal de erros ou reinícios;
- perda de rota esperada;
- consumo excede limite definido;
- gate pós-deploy diverge do plano aprovado;
- integridade ou hash muda durante a operação.

### 10.3 Recibo de rollback

Deve registrar causa, início, artefato restaurado, situação dos dados, testes
pós-rollback, duração e pendências. A IA pode explicar o recibo, mas não pode
declarar sucesso sem os checks determinísticos.

## 11. Diagnóstico e segurança

Arquitetura recomendada para a futura Central de Segurança:

- scanner de imagens, filesystem, configuração, secrets e SBOM;
- auditoria de práticas Docker/CIS em operação privilegiada separada e
  explicitamente autorizada;
- verificação TLS e exposição externa;
- detecção runtime opcional, pois sensores de kernel aumentam complexidade;
- correlação pelo Assistente somente depois da sanitização;
- severidade técnica separada de prioridade de negócio;
- exceções com prazo, responsável e justificativa.

Scanner não é oráculo. Resultado precisa registrar versão da base, alvo, digest,
escopo e limitações. Ausência de achado não equivale a ausência de risco.

## 12. Scale Advisor

O módulo futuro deve recomendar uma escada, não vender cluster por reflexo:

1. corrigir vazamento ou configuração;
2. otimizar a aplicação;
3. escala vertical;
4. replicar serviço stateless em workers;
5. alta disponibilidade do plano de controle com managers ímpares;
6. estado externo ou replicado;
7. considerar outra plataforma somente quando requisitos superarem o Swarm.

A IA pode produzir previsão e proposta. Gates determinísticos devem conferir
capacidade, placement, reservations, limits, portas, storage e tolerância a
falha. Promoção de manager, alteração de quorum, `force-new-cluster` e escala
automática de banco permanecem proibidas.

## 13. Observabilidade e métricas de sucesso

Métricas de produto:

- diagnósticos concluídos sem shell/root;
- propostas bloqueadas antes de produção;
- tempo entre problema e plano seguro;
- percentual de propostas comprovadas em laboratório;
- rollback testado antes de mudanças stateful;
- redução de tickets causados por instalações improvisadas;
- falsos positivos e exceções por política;
- dados sensíveis bloqueados antes do provedor;
- satisfação separada entre iniciantes e operadores experientes.

Métricas nunca devem incentivar aprovação automática ou redução artificial de
gates.

## 14. Fases propostas

### AI-0 — Projeto e documentação

Estado: concluído documentalmente neste arquivo. Nenhuma mudança de runtime.

### AI-1 — Pré-requisito de supply chain

Consumir SBOM, proveniência, inventário de dependências e política de digests.
Esta fase coincide com o primeiro item técnico pendente do roadmap canônico.

### AI-2 — Safe Diagnostics

Entregar jornada somente leitura, snapshot sanitizado, explicação local/LLM,
auditoria, FAQ e bloqueios universais. Nenhuma escrita ou sandbox executável.

### AI-3 — Workspace isolado

Permitir criação de propostas em ambiente restrito, com rede allowlisted,
limites, credenciais efêmeras e policy gate. Sem acesso ao Swarm de produção.

### AI-4 — Homologation Bridge

Converter proposta validada em candidato isolado, reaproveitar Runner e
importador canônico, coletar evidências e limpar recursos inventariados.

### AI-5 — Secure Handoff

Abrir fluxo determinístico do Instalador Seguro, com diff, token, backup,
monitoramento e rollback por classe. A IA continua sem executar em produção.

### AI-6 — Security Center e Scale Advisor

Traduzir scanners e métricas em recomendações, mantendo sensores privilegiados
separados do Assistente e operações críticas fora da autonomia.

## 15. Estratégia de compatibilidade

- Debian e Ubuntu em VPS devem ser validados separadamente;
- WSL2 + Docker Desktop precisa detectar daemon desligado e integração ausente;
- AMD64 e ARM64 exigem digests e testes próprios;
- instalações tradicionais não recebem Terminal Seguro remoto;
- Cloudflare Tunnel não amplia a autoridade da IA;
- indisponibilidade do provedor ativa fallback local;
- plano, instalação ou policy ausente resulta em negação;
- downgrade remove runtimes e credenciais exclusivas da capacidade superior.

## 16. Decisões pendentes antes da implementação

1. nomenclatura final apresentada na interface;
2. matriz comercial definitiva entre free, free1, free2 e pro;
3. formato do manifesto de proposta;
4. mecanismo de sandbox para VPS e WSL2;
5. política de egress e fornecedores permitidos;
6. scanners iniciais e orçamento de recursos;
7. retenção do ledger e relatórios;
8. critérios para publicação parcial no Help;
9. primeira versão alvo após a etapa de supply chain;
10. laboratório e testes adversariais obrigatórios.

Nenhuma dessas decisões autoriza relaxar root, Docker socket, secrets ou
publicação automática.

## 17. Critérios de aceite arquitetural

Antes da primeira implementação, deve ser possível demonstrar em revisão que:

- um modelo malicioso não alcança produção;
- um plugin ou MCP comprometido não recebe credenciais globais;
- o Assistente permanece sem socket e shell;
- toda proposta muda de hash ao mudar de conteúdo;
- todos os planos recebem bloqueios críticos;
- somente PRO MASTER governa políticas e promoção;
- instalações tradicionais continuam sem terminal remoto;
- uma falha do provedor preserva diagnóstico básico;
- recursos de laboratório têm inventário e limpeza literal;
- mudanças stateful sem restore comprovável são bloqueadas;
- nenhum fluxo cria commit, tag, release, DNS ou deploy automaticamente.

Este documento é o contrato de projeto. Implementações futuras devem reduzir o
escopo se necessário, nunca ampliar autoridade silenciosamente.
