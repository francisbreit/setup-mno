# Setup MNO Control Center

Painel web oficial do Setup MNO. O projeto é compilado localmente durante a
instalação e executado em três stacks obrigatórias e uma quarta opcional:

- `web`: autenticação, interface responsiva, catálogo, auditoria, feedback
  estruturado e proxy do terminal;
- `agent`: inventário somente leitura do Docker Swarm, métricas do host e leitura
  validada do manifesto e catálogo runtime;
- `terminal`: menu seguro para o instalador original e a Central de
  Configurações, acessível apenas pelo painel;
- `assistant` (opcional): conector consultivo para OpenAI, OpenRouter, DeepSeek
  ou Ollama, sem socket Docker, shell, terminal, mounts do host ou rota pública
  própria.

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
- OpenRouter e DeepSeek pelas APIs compatíveis de Chat Completions com
  streaming;
- um endpoint Ollama já existente, usando um modelo previamente baixado.

O navegador conserva somente as últimas mensagens da sessão. Antes de qualquer
consulta, o serviço reúne contexto por endpoints fixos de leitura e remove
hostname, IP, imagens, credenciais, secrets e comandos. A LLM recebe apenas
métricas agregadas, versão, arquitetura, estado de réplicas, os setups
relevantes e, quando os gates permitirem, trechos canônicos limitados. Se o
provedor falhar, o painel oferece contingência automática pelo diagnóstico
básico e registra o evento na auditoria.

O Assistente é estritamente consultivo: não possui ferramentas de escrita e não
executa deploys, comandos Docker ou ações destrutivas.

O domínio principal do Copiloto é o Setup MNO e sua infraestrutura: setups,
Blueprints, capacidade, Docker Swarm, Linux/WSL2, redes, bancos, armazenamento,
backups, segurança, observabilidade, integrações e deploys. A interface comunica
esse foco antes da pergunta e os conectores redirecionam consultas alheias ao
domínio, em vez de atuarem como assistentes generalistas.

### Roteador local de especialistas

Antes do retrieval e da chamada ao provedor, um roteador determinístico
classifica a consulta em um dos modos internos: diagnóstico de infraestrutura,
setups, integrações, troubleshooting, capacidade, Blueprints, segurança ou
redirecionamento de escopo. O roteamento não consome LLM e não registra nem
inclui o texto da pergunta em seu contrato.

O contrato versionado expõe somente valores permitidos: intenção, especialista,
setups canônicos identificados, domínios, arquitetura, risco, confiança e
evidências obrigatórias. Linguagem destrutiva eleva o risco para alto e torna
rollback uma evidência obrigatória. A interface mostra o especialista escolhido
e os gates aplicados, enquanto o prompt recebe um processo estável que não pode
ser reclassificado pelo modelo.

### Registro versionado de prompts

Os oito especialistas usam um registro local único, validado ao iniciar o
Assistente. Cada entrada possui ID, versão, missão, processo, política de
evidências, seções esperadas e exemplos positivo, negativo e de recusa. O
prefixo confiável e a definição do especialista produzem um SHA-256 estável;
pergunta, histórico, métricas e documentos recuperados não participam desse
hash.

O contrato de rota fixa a versão do registro, a versão e o SHA-256 do prompt
antes da chamada ao provedor. A interface mostra esses metadados para
homologação. O contexto operacional sanitizado é anexado somente depois do
prefixo confiável, com delimitador explícito de dados não executáveis. Assim,
OpenAI, OpenRouter, DeepSeek e Ollama recebem a mesma política especializada e
auditável, sem uma segunda chamada de LLM.

### Autoria por mensagem e resposta adaptativa

Cada resposta exibe no próprio cabeçalho o especialista local, o nível de risco
e a versão do prompt. O navegador cria um snapshot imutável a partir do evento
SSE de rota e aceita somente especialistas, riscos e versões permitidos. O
texto da LLM não consegue definir ou substituir essa autoria; pergunta,
histórico, contexto runtime e SHA completo não são copiados para o cabeçalho.

O contrato de resposta é versionado junto com o prompt e organiza o conteúdo em
camadas: conclusão prática primeiro e detalhes verificáveis depois. Termos
técnicos essenciais são preservados e explicados, sem rotular o usuário como
iniciante ou profissional. Respostas de risco alto exigem riscos, validação e
rollback. O mesmo cabeçalho funciona em LLM, catálogo local, modo básico e
contingência, inclusive em telas estreitas e zoom elevado.

### RAG fundamentado

Com um provedor configurado, o ranking local emite um relatório efêmero para a
resposta atual. Somente resultados de confiança alta ou média, sem fallback
legado e com documentos aprovados, entram na ativação controlada. O prompt
recebe no máximo quatro trechos, limitados individualmente a 1.800 caracteres e
a 6.000 no total.

As evidências são enviadas como uma mensagem de dados separada das instruções
do sistema. Documentos não podem mudar políticas ou autoridade, e comandos
presentes neles são apenas conteúdo explicativo. Afirmações factuais
fundamentadas devem citar `[Fonte N]`. Resultados insuficientes permanecem
somente na inspeção.

O relatório não contém pergunta, histórico, contexto operacional ou score
bruto e permanece somente na sessão do navegador. Modo básico e contingência
local não executam o RAG.

## Central de Configurações

A área Configurações aparece abaixo de Auditoria e exibe somente dados não
sensíveis: usuário, provedor e modelo ativos. Qualquer alteração abre o
Terminal Seguro, onde o Whiptail exige a senha administrativa atual e oferece
uma lista fixa de operações:

- alterar o usuário administrador;
- rotacionar a senha administrativa;
- alternar entre OpenAI, OpenRouter, DeepSeek, Ollama e diagnóstico básico;
- alterar o modelo e, quando aplicável, a chave da API.

Senha e chaves nunca passam pelo navegador. O terminal cria Docker Secrets
versionados, atualiza o serviço, aguarda o healthcheck e executa rollback em
caso de falha. A reinicialização do painel invalida as sessões abertas. Essa
capacidade não adiciona socket Docker, shell ou endpoint de escrita ao painel
web nem ao Assistente.

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

Na subetapa 5.1, o pacote também transporta a fábrica canônica de Blueprints:

- `blueprints/schema/blueprint.schema.json`: contrato JSON v1;
- `blueprints/index.json`: inventário seguro para futuras interfaces;
- `blueprints/manifest.json`: versão da fábrica, contagens e hashes;
- `blueprints/bundles/*.zip`: um bundle determinístico por Blueprint.

Blueprints com status `example` são obrigatoriamente fictícios, não
implantáveis e limitados a links `.invalid`. Seus `README.md` permanecem fora
do RAG. Na subetapa 5.2, cada exemplo possui um `knowledge.md` revisado que
percorre o mesmo índice, ranking, prompt especializado, citações e inspeção de
um Blueprint real. A recuperação exige simultaneamente o Arquiteto de
Blueprints e o modo explícito de homologação; a interface identifica a resposta
como simulação e nunca a apresenta como autorização de deploy.

Quando a pergunta resolve um `blueprintId` exato, o ranking fica restrito a
esse documento. O gate rejeita exemplos fora do especialista, fora do modo de
homologação ou com a combinação insegura `fictitious: true` e
`deployable: true`. Assim, o comportamento funcional é equivalente ao de um
Blueprint real, enquanto a procedência e a capacidade operacional continuam
inequivocamente separadas.

Na subetapa 5.3, a área **Blueprints** apresenta esse inventário diretamente no
Control Center, inclusive no modo básico. Homologados, exemplos fictícios e
itens em revisão ocupam grupos visuais distintos. Filtros locais e uma inspeção
detalhada mostram objetivo, componentes, arquitetura, risco, mídia declarada e
procedência, sempre sem botão de deploy. A API autenticada entrega somente uma
projeção tipada do índice validado: conteúdo RAG, URLs editoriais, caminhos
internos e downloads de bundles não são expostos.

Na subetapa 5.4, o mesmo painel oferece recomendação contextual local. O
usuário descreve o resultado desejado e o Control Center consulta arquitetura e
RAM pelo agente somente leitura. Versão, origem runtime, arquitetura, status
editorial e RAM mínima são gates bloqueantes executados antes do ranking.
Somente então aliases, tags, título, componentes, objetivo e resumo determinam
a aderência. O resultado explica os motivos, diferencia RAM recomendada de RAM
mínima e lista candidatos recusados. Ausência de evidência produz zero
recomendações; exemplos continuam fictícios, não implantáveis e abrem apenas a
inspeção segura.

A correção 6.3.1 tolera somente um erro ortográfico em tokens com pelo menos
sete caracteres, comparados exclusivamente com tags e aliases canônicos. A
aproximação aceita substituição, inserção, remoção ou transposição adjacente e
exige a mesma letra inicial. Títulos, componentes, objetivos e resumos não
participam da aproximação; os gates de arquitetura, status e RAM continuam
obrigatórios depois da identificação do candidato.

Na subetapa 5.5, o schema v2 torna o fluxo editorial parte obrigatória do
Blueprint. A fábrica aceita promoção para `homologated` somente após a sequência
`draft → reviewed → homologated`, revisão aprovada, homologação em ambiente
isolado, cobertura das arquiteturas e evidências com SHA-256 válido. O índice
publica histórico, gates, metadados das evidências e um selo determinístico da
versão, removendo seus caminhos internos. O Control Center apenas inspeciona
esses dados; edição, aprovação, upload e deploy continuam fora da API web.

Na subetapa 6.1, o pacote inclui `evals/dataset.json`, com 210 casos revisados,
schema estrito, versão e SHA-256 próprios. O comando local `evalcheck` executa o
retrieval e o roteador reais, calcula métricas agregadas e falha se Recall@5,
factualidade, groundedness, roteamento, Blueprints, rollback ou honestidade sem
evidência ficarem abaixo dos thresholds. Vazamentos, ações inventadas,
documentos obsoletos e mistura de arquitetura possuem tolerância zero.

O instalador executa esse gate na imagem final antes de criar secrets ou
stacks. Desde a v7.0.1, o Assistente mostra somente o selo simples **Qualidade
verificada** e a quantidade de testes aprovados. O relatório completo fica fora
da navegação principal e abre pelo botão **Ver relatório técnico**, com nomes
compreensíveis e siglas técnicas secundárias. Ele continua exibindo somente
contagens, percentuais, versões, baseline e hash do dataset. Perguntas,
respostas de referência, IDs de documentos e traces nunca são publicados pela
API.

Na subetapa 6.2, um canário opcional permite avaliar o provedor configurado com
quatro perguntas sintéticas críticas: ação destrutiva, credenciais, limite de
escopo e ausência de evidência. Ele só executa após confirmação explícita no
navegador, limita cada resposta a 450 tokens, usa no máximo duas requisições
simultâneas e bloqueia repetição por dez minutos. O modo básico permanece sem
consumo de IA.

O canário nunca coleta métricas, aplicações, hostname, IP ou credenciais do
servidor. As respostas são exibidas com `textContent`, exigem aprovação ou
reprovação humana em todos os quatro casos e não são persistidas pelo servidor;
somente as contagens finais entram na auditoria. Essa revisão mede a aderência
do modelo e não autoriza deploy, alteração de Swarm ou qualquer ação real.

## Feedback privado do Assistente

Cada resposta concluída recebe um token opaco válido por 30 minutos e utilizável
uma única vez. O usuário pode escolher avaliação, área e motivo em listas
fechadas e precisa autorizar explicitamente a retenção. O endpoint rejeita texto
livre e campos desconhecidos; pergunta, resposta, IP, hostname, credencial e
comando não fazem parte do schema persistido.

A fila usa um volume Docker dedicado montado somente no serviço web. O arquivo
JSON estrito é gravado atomicamente, rejeita symlinks, fica limitado a 200
registros e 256 KiB e retém dados por no máximo 30 dias. Na Auditoria, o
administrador pode aceitar um item como candidato a eval, descartá-lo ou
excluí-lo. Nenhuma dessas decisões altera automaticamente dataset,
conhecimento, prompt, Swarm ou aplicação instalada.

O mesmo pacote é distribuído para x86 e ARM. Na imagem do Assistente, a cópia
primária fica em `/knowledge-package`, somente leitura pela própria camada da
imagem. Uma segunda cópia é embutida no binário Go e entra em contingência se a
cópia primária estiver ausente ou inválida. A contingência é identificada como
desatualizada; conteúdo adulterado nunca é aceito silenciosamente.

Para preservar a compatibilidade com SHC, arquivos compactados não são
incorporados ao Base64 do script `setupmno_control.sh`. O pacote promovido e
validado em `.control/knowledge-package/` é copiado para o contexto temporário
do build, mantendo o mesmo SHA-256 no runtime, na imagem e no fallback Go.
O bundle compilável do painel segue a mesma regra: `control-source.tar.gz`
permanece em `.control-package/`, possui hash e tamanho no manifesto, é
promovido atomicamente para `.control/` e validado novamente pelo instalador.
Assim, o script protegido pelo SHC não carrega arquivos compactados ou Base64.

O modo básico continua sem LLM e sem stack adicional. O pacote não concede ao
Assistente socket Docker, shell, terminal, mount do host ou capacidade de
escrita.

## Sincronização

O Setup publica atomicamente em `/root/SetupLowCodeMno/.control/`:

- `release.json`: versão instalada, arquitetura, schema, quantidade e SHA-256;
- `catalog.json`: catálogo correspondente à release.
- `control-source.tar.gz`: fontes compiláveis do painel, externos ao SHC;
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
