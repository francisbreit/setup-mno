# Setup MNO Control Center

Painel web oficial do Setup MNO. O projeto é compilado localmente durante a
instalação e executado em três stacks obrigatórias e uma quarta opcional:

- `web`: autenticação, interface responsiva, catálogo, auditoria e proxy do terminal;
- `agent`: inventário somente leitura do Docker Swarm, métricas do host e leitura
  validada do manifesto e catálogo runtime;
- `terminal`: sessão isolada do instalador original, acessível apenas pelo painel.
- `assistant` (opcional): conector consultivo para OpenAI ou Ollama, sem socket
  Docker, shell, terminal, mounts do host ou rota pública própria.

O agente não oferece endpoints de escrita nem uma API genérica de arquivos ou
comandos. O único componente com acesso ao
instalador original é o terminal, protegido pela autenticação e pela sessão do
painel.

Web e Assistente executam como usuário não-root e sem capabilities Linux. O
agente também remove todas as capabilities e monta somente o diretório runtime
`.control` do Setup, além de `/proc` e do socket Docker necessários às métricas.
Agente e terminal possuem healthchecks internos para permitir a recuperação
automática de tarefas não saudáveis pelo Swarm.

## Assistente MNO

O diagnóstico básico permanece disponível sem LLM e sem stack adicional. Em
servidores com recursos suficientes, a instalação permite conectar:

- OpenAI pela Responses API, com streaming, `store: false` e chave protegida
  exclusivamente por Docker Secret;
- um endpoint Ollama já existente, usando um modelo previamente baixado.

O navegador conserva somente as últimas mensagens da sessão. Antes de qualquer
consulta, o serviço reúne contexto por endpoints fixos de leitura e remove
hostname, IP, imagens, credenciais, secrets e comandos. A LLM recebe apenas
métricas agregadas, versão, arquitetura, estado de réplicas e os setups
relevantes para a pergunta. Se o provedor falhar, o painel oferece contingência
automática pelo diagnóstico básico e registra o evento na auditoria.

O Assistente é estritamente consultivo: não possui ferramentas de escrita e não
executa deploys, comandos Docker ou ações destrutivas.

O plano completo para transformar o Beta em um especialista de infraestrutura,
setups e Blueprints está registrado em
[`ASSISTENTE_MNO_ROADMAP.md`](ASSISTENTE_MNO_ROADMAP.md).
A fonte editorial criada na Etapa 1 está em
[`../setupmno-knowledge/`](../setupmno-knowledge/).

## Conhecimento versionado

A Etapa 2 transforma a fonte editorial em um pacote determinístico, validado e
independente do provedor de LLM. O gerador produz:

- `knowledge-package.tar.gz`: documentos homologados e índice textual
  pré-construído;
- `manifest.json`: versões do Setup, Control Center e conhecimento, inventário,
  contagens, limites de tamanho e hashes SHA-256.

O mesmo pacote é distribuído para x86 e ARM. Na imagem do Assistente, a cópia
primária fica em `/knowledge-package`, somente leitura pela própria camada da
imagem. Uma segunda cópia é embutida no binário Go e entra em contingência se a
cópia primária estiver ausente ou inválida. A contingência é identificada como
desatualizada; conteúdo adulterado nunca é aceito silenciosamente.

Para preservar a compatibilidade com SHC, arquivos compactados não são
incorporados ao Base64 do script `setupmno_control.sh`. O pacote promovido e
validado em `.control/knowledge-package/` é copiado para o contexto temporário
do build, mantendo o mesmo SHA-256 no runtime, na imagem e no fallback Go.

O modo básico continua sem LLM e sem stack adicional. O pacote não concede ao
Assistente socket Docker, shell, terminal, mount do host ou capacidade de
escrita.

## Sincronização

O Setup publica atomicamente em `/root/SetupLowCodeMno/.control/`:

- `release.json`: versão instalada, arquitetura, schema, quantidade e SHA-256;
- `catalog.json`: catálogo correspondente à release.
- `knowledge-package/manifest.json`: manifesto validado do conhecimento;
- `knowledge-package/knowledge-package.tar.gz`: pacote canônico reproduzível.

Ao carregar a página, retornar à aba, usar a atualização manual ou a cada cinco
minutos, o painel consulta esses arquivos pelo agente. A versão do Setup MNO é
mostrada separadamente da versão do Control Center. Se a validação falhar, o
catálogo embutido entra em contingência com aviso visual e evento de auditoria.

Depois de alterar o painel, o catálogo ou `VERSIONSETUP`:

```bash
./1_codigo_fonte/setupmno-control/generate-installers.sh
```

O comando recria mecanicamente os scripts `setupmno_control.sh` de x86 e ARM
com o mesmo bundle de fontes e gera os pacotes `.control-package/` de cada
arquitetura. Durante uma instalação ou atualização, os gatilhos validam esses
pacotes e promovem os arquivos para `.control/` com arquivos temporários e
renomeação atômica.
