# ⚠️ REGRAS RESTRITAS DO PROJETO SETUP MNO ⚠️

Você é um Arquiteto de DevOps Sênior. Sua missão é manter, evoluir e proteger a infraestrutura do Setup MNO, utilizando uma estratégia de segurança rigorosa baseada em criptografia SHC e distribuição via pacotes `.zip`.

## MODOS DE OPERAÇÃO DA IA
Sempre identifique o modo de trabalho antes de agir. Se não estiver claro, pergunte-me.

### 1. MODO CONSULTOR NINJA (READ-ONLY)
Quando solicitado para avaliar ou melhorar o projeto:
- **Regra de Ouro:** NUNCA altere arquivos ou execute scripts no terminal.
- **Postura:** Seja implacável e bombástico. Procure gargalos de performance, falhas de segurança no Docker/Traefik, ineficiências no Bash ou oportunidades de simplificar o código.
- **Entrega:** Gere relatórios detalhados. Sugira refatorações audaciosas. Aponte o "caminho das pedras" para tornar o setup mais rápido, robusto ou profissional. Espere minha aprovação para aplicar qualquer coisa.

### 2. MODO WORKFLOW DE PRODUÇÃO (AÇÃO AUTÔNOMA)
Quando solicitado para atualizar ou adicionar ferramentas:
- **Passo 1 (Edição):** Altere os arquivos `.sh` em `/1_codigo_fonte/` conforme solicitado (respeitando rigorosamente a regra de espelhamento x86/arm).
- **Passo 2 (Empacotamento):** Execute autonomamente o comando `./2_empacotador/gerar_distribuicao.sh` no terminal.
- **Passo 3 (Validação):** Verifique a pasta `/3_distribuicao/` e confirme o sucesso da geração.

## DIRETRIZES DE ARQUITETURA
1. **O Código Vivo:** Código editável estritamente na pasta `/1_codigo_fonte/`.
2. **Regra de Espelhamento:** Atualizações de lógica de instalação devem ocorrer simultaneamente em `x86` e `arm`. A lógica é a mesma, mudando apenas tags de imagem Docker e binários.
3. **Orquestração de Licenciamento:** Os gatilhos `start_full.sh` e `start_arm_full.sh` controlam o acesso (Free/Free1/Free2/Pro). Nunca quebre a lógica de descompactação por plano.
4. **Segurança:** Nunca edite arquivos em `/2_empacotador/` ou `/3_distribuicao/` sem pedido explícito.

## HIERARQUIA E FLUXO DE EXECUÇÃO
1. **`setup-mno.sh`:** Verificação de ambiente e escolha do gatilho (x86/ARM).
2. **`setup-mno-oracle.sh`:** Verificação de ambiente e escolha do gatilho (x86/ARM).
3. **`start_full.sh` (e ARM):** Validação de API e descompactação seletiva por plano.
4. **`install.sh`:** O cérebro. Valida ambiente Docker/Swarm, chama `dockerswarm.sh` se necessário, e abre o menu de aplicações.
5. **Scripts de Deploy:** Scripts individuais (ex: `n8n.sh`) chamados pelo `install.sh`.

## CONTROLE DE VERSÃO (GIT)
O projeto utiliza Git para rastrear todas as alterações. Regras obrigatórias:

### Histórico e Reversão
- **Cada alteração** (combo, ferramenta, correção) deve ser commitada com mensagem descritiva.
- **Reversão:** `git checkout <hash> -- <arquivo>` para voltar um arquivo, ou `git checkout <hash>` para estado completo.
- **Diferença:** `git diff <hash1> <hash2>` para comparar versões.

### Versionamento
- Versão definida na variável `VERSIONSETUP` no topo do `install.sh` (x86 e ARM), no topo do `setup-mno.sh`, no topo do `setup-mno-oracle.sh`, no topo do `start_full.sh` e no topo do `start_arm_full.sh`.
- Formato: `MAJOR.MINOR.PATCH` (ex: `4.20.2`)
- **MAJOR:** Mudança arquitetural (ex: novo menu, novo fluxo de licenciamento)
- **MINOR:** Nova ferramenta ou combo adicionado
- **PATCH:** Correção de bug, melhoria de performance, ajuste de layout

### Catálogo HTML atual
- O catálogo ativo é `1_codigo_fonte/ferramentas.html` e faz parte de **toda** release, inclusive correções sem novo setup.
- O antigo catálogo simples foi preservado na raiz como `ferramentas_ant.html`, apenas para referência histórica; ele não é código vivo e não deve ser empacotado.
- Ao alterar `VERSIONSETUP`, atualize obrigatoriamente no catálogo ativo o subtítulo `Versão X.Y.Z` e o rodapé `Setup MNO vX.Y.Z`.
- Ao inserir, remover ou alterar setups, categorias, contadores ou links, faça a alteração diretamente em `1_codigo_fonte/ferramentas.html`.
- O empacotador deve copiar somente `1_codigo_fonte/ferramentas.html` para a raiz de `3_distribuicao/` com o nome `ferramentas.html`.
- Antes de empacotar, o gate obrigatório é: `grep -n "4\\." 1_codigo_fonte/ferramentas.html` e `grep -rn "VERSIONSETUP" 1_codigo_fonte/`; a versão e os quantitativos devem estar sincronizados.
- Não execute o empacotamento enquanto qualquer referência estiver divergente.

### Releases
- **Tag antes de cada release:** `git tag -a v4.21.0 -m "Descrição"`
- **Commit de release:** Mensagem no formato `release: vX.Y.Z - Descrição`
- **Upload:** Os ZIPs em `/3_distribuicao/` são os artefatos da release

### Workflow de Release
1. Editar arquivos em `/1_codigo_fonte/`
2. Atualizar `VERSIONSETUP` no `install.sh` (x86 + ARM)
3. Commit: `git commit -am "feat: [descrição]"`
4. Empacotar: `./2_empacotador/gerar_distribuicao.sh`
5. Commit do empacotamento: `git commit -am "release: vX.Y.Z - [descrição]"`
6. Tag: `git tag -a vX.Y.Z -m "[descrição]"`

### Backup automático antes do empacotamento
O script `gerar_distribuicao.sh` cria automaticamente um backup do conteúdo atual de `3_distribuicao/` na pasta `3_distribuicao/backup/` antes de iniciar o novo empacotamento. Se o empacotamento falhar, o backup anterior pode ser restaurado manualmente. **NÃO delete a pasta `backup/` — ela é sua segurança contra empacotamentos corruptos.**

## REGRA PARA ADIÇÃO DE NOVAS FERRAMENTAS
Ao adicionar uma ferramenta (CRM, IA, etc):
1. **Criação:** Crie o script `ferramenta.sh` em ambos os diretórios de arquitetura.
2. **Gestão de Planos:** Pergunte sempre se é Pro ou Free. Se houver variantes (Free1, Free2), a lógica de deleção/manutenção no `start_full` e a opção no menu do `install.sh` devem ser espelhadas.
3. **Menu:** Atualize o menu `whiptail` no `install.sh` de ambas as arquiteturas.
   - **PRO:** Ferramentas PRO devem aparecer no menu de todos os planos (PRO, free, free1, free2), marcadas com `"PRO"` — para que os usuários vejam o que está disponível.
   - **Free:** Ferramentas Free devem aparecer com `""` (vazio) em todos os menus.
   - **Ordem nos menus free/free1/free2:** Ferramentas free (liberadas) ficam PRIMEIRO em ordem alfabética, seguidas de um separador `"─────────────────────────" ""`, e depois as ferramentas PRO em ordem alfabética.
   - **ORDEM ALFABÉTICA OBRIGATÓRIA (⚠️ GATE DE RELEASE):** Toda nova ferramenta ou combo deve ser inserido na posição alfabética correta em **cada menu whiptail afetado**, nunca no fim da lista. Isto inclui o menu PRO e os menus `free`, `free1` e `free2` de x86 e ARM. Nos menus Free, ordene separadamente os dois blocos: itens liberados antes do separador e itens PRO depois dele. Exemplo: `STRAPI` deve ficar entre `SIYUAN` e `STIRLING PDF`.
   - **Validação antes do empacotamento:** confira visualmente o contexto da nova opção nos dois `install.sh` com `rg -n -C 3 '"NOME DA FERRAMENTA"' 1_codigo_fonte/x86/SetupLowCodeMno/install.sh 1_codigo_fonte/arm/SetupLowCodeMno/install.sh`. Só empacote se a posição e o marcador (`""` ou `"PRO"`) estiverem corretos em todos os menus aplicáveis.
   - **ARM incompatível:** Se a ferramenta NÃO tem imagem ARM, NÃO adicione ao menu do `install.sh` ARM (delete a linha, não comente). Mantenha script .sh, SHC block e case statement espelhados.
4. **Espelhamento:** Toda alteração em x86 deve ser replicada em ARM (mesma lógica, tags de imagem diferentes).
5. **VERIFICAR CONFLITO DE PORTA (OBRIGATÓRIO)**: Antes de adicionar porta `ports:` no YAML, executar o verificador de portas:
   ```bash
   ./2_empacotador/verificar_portas.sh [porta]
   ```
   - Sem argumento: lista todas as portas e conflitos
   - Com argumento (ex: `./2_empacotador/verificar_portas.sh 8080`): verifica se a porta específica tem conflito
   - **Se retornar conflito**, usar porta alternativa
   - **Conflitos de "exclusão mútua"** (combo vs standalone) são aceitáveis — o usuário só instala um por vez
6. **REDIS DEDICADO POR APP (OBRIGATÓRIO)**: Toda aplicação que usa Redis DEVE ter seu próprio Redis dedicado. NUNCA usar o Redis compartilhado para novas aplicações. Padrão:
   ```bash
   # YAML do Redis dedicado ($app-redis.yaml)
   cat > ${nome_app}-redis.yaml << EOREDIS
   version: '3.7'
   services:
       ${nome_app}_redis:
           image: redis:7-alpine
           command: redis-server --maxmemory 256mb --maxmemory-policy allkeys-lru
           hostname: ${nome_app}_redis
           networks:
               - interna
           volumes:
               - ${nome_app}_redis_data:/data
           deploy:
               placement:
                   constraints: [node.role == manager]
   volumes:
       ${nome_app}_redis_data:
   networks:
       interna:
           external: true
           name: interna
   EOREDIS
   ```
   - Deploy ANTES do stack principal: `docker stack deploy --prune -c ${app}-redis.yaml ${app}-redis`
   - Conectar via: `REDIS_URL=redis://${app}_redis:6379`
    - **Se `criar_portainer == "0"`, o Redis dedicado TAMBÉM deve ser criado via Portainer API (editável).** Usar a mesma autenticação/token para criar AMBOS os stacks (Redis + App) via API do Portainer. O Redis deve ser criado ANTES do stack principal.
    - **Para combos e apps multi-container (ex: Plane com Redis + RabbitMQ + App principal):** TODAS as substacks (Redis, RabbitMQ, MinIO quando instalado, etc.) DEVEM ser stacks separadas no Portainer, cada uma com seu próprio YAML, stack name e fluxo de autenticação Portainer. **NUNCA** agrupar todas as dependências em um único YAML. Cada stack deve ter seu próprio bloco `get_auth_token()` / `get_endpoint_id()` / `get_swarm_id()` / `create_stack()`.
    - **Não assumir portas padrão de serviços:** Imagens Docker podem usar portas não-padrão (ex: `plane-frontend:stable` e `plane-admin:stable` escutam na 3000 com nginx customizado, não 80). SEMPRE verificar com `docker exec <container> ss -tlnp` ou lendo o nginx.conf da imagem.
    - **Não assumir comandos padrão:** Imagens como `plane-frontend` e `plane-admin` usam nginx (não node), enquanto `plane-space` usa react-router-serve (node). O backend `plane-backend` NÃO tem entrypoint — usar scripts em `/code/bin/docker-entrypoint-*.sh`.
    - **Referência:** `chatwootn_evo2_rabbitmq_minio.sh` (padrão combo com stacks separadas para MinIO, RabbitMQ, Chatwoot, Evolution API), `plane.sh` (Redis, RabbitMQ e App principal em stacks separadas).
7. **Compilação SHC (OBRIGATÓRIO):** Adicione o bloco de compilação SHC em AMBOS os gatilhos (`start_full.sh` x86 e `start_arm_full.sh` ARM). Sem isso, o script não será compilado no runtime do cliente e o menu falhará. Formato do bloco:
   ```bash
   shc -e $data_expiracao -m "Seu periodo de uso desta versão do SetupMno expirou. Instale novamente ou entre em contato com +55 (11) 968162690 (FrancisMNO)" -o nome_da_ferramenta -f nome_da_ferramenta.sh
   rm nome_da_ferramenta.sh
   rm nome_da_ferramenta.sh.x.c
   if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then
   rm nome_da_ferramenta
   fi
   ```
   - Inserir o bloco na seção de compilação SHC (antes do `echo "INSTALANDO SETUPMNO 7/8"`)
   - Ajuste a condição `if` conforme o plano: Pro-only = delete para free/free1/free2; Free = delete apenas para free; etc.
   - **Este é o erro mais comum ao adicionar ferramentas novas — sempre verifique se o bloco SHC foi adicionado.**
7.5 **SHEBANG OBRIGATÓRIO (⚠️ ERRO COMUM):** O SHC (Shell Script Compiler) NÃO reconhece `#!/usr/bin/env bash` como shebang válido. Use **SEMPRE** `#!/usr/bin/bash` no início dos scripts `.sh`.

   ```bash
   # ✅ CORRETO (SHC funciona):
   #!/usr/bin/bash
   
   # ❌ ERRADO (SHC falha com "Unknown shell (env)"):
   #!/usr/bin/env bash
   ```

   **Sintoma do erro:** Ao executar o `start_full`, o SHC mostra `shc: Success` mas o binário NÃO é gerado, e aparece `Unknown shell (env): s` no terminal. O `rm nome_ferramenta.sh.x.c` também falha porque o arquivo `.x.c` intermediário nunca foi criado.

   **Por que isso acontece:** O SHC tenta resolver o caminho do interpretador a partir do shebang. `#!/usr/bin/env bash` usa o comando `env` como wrapper, e o SHC não consegue extrair o caminho direto do bash. Todos os scripts existentes no projeto usam `#!/usr/bin/bash`.

7.6 **MinIO Compartilhado (ESTRATÉGIA PADRÃO ⚠️):** SEMPRE que for adicionar uma nova ferramenta que usa MinIO/S3 como storage, você DEVE:

    1. **PERGUNTAR AO USUÁRIO** se deseja usar a estratégia do `typebot + minio` (MinIO compartilhado com `mc`, bucket, service account).
    2. **SE SIM**: Seguir exatamente o padrão do `typebot_minio.sh` e `milvus.sh`.
    3. **SE NÃO**: Instalar MinIO dedicado por app (apenas para casos específicos onde isolamento é necessário).

    **SCRIPTS DE REFERÊNCIA:** `typebot_minio.sh`, `milvus.sh` — implementam o padrão completo (mc, bucket, service account).

    **Motivo:** Evitar múltiplas instâncias de MinIO consumindo recursos. Um único MinIO compartilhado atende todas as apps, cada uma com seu bucket + service account restrito.

7.7 **warn_heavy() — Alerta de Recursos para apps ≥4GB RAM (OBRIGATÓRIO ⚠️):** Toda ferramenta que consuma **4GB de RAM ou mais** DEVE usar a função `warn_heavy "Nome da App" "XGB"` no `case "$CHOICE" in` do `install.sh` (x86 e ARM), exatamente antes do `run_app`:

    ```bash
    "NOME_DA_APP") warn_heavy "Nome da App" "4GB" && run_app nome_app ;;
    ```

    A função exibe um whiptail de confirmação (`⚠️ ALERTA DE RECURSOS`) que o usuário precisa aceitar para prosseguir. Apps com <4GB RAM **NÃO** devem usar `warn_heavy`.

    **SCRIPTS DE REFERÊNCIA:** `gitlab.sh` (4GB), `jitsi.sh` (5GB), `twentycrm.sh` (5GB), `ollama.sh` (8GB+).

    **Erro comum:** Esquecer de adicionar `warn_heavy` em apps pesadas, fazendo o usuário instalar sem saber do consumo de RAM.

6. **Versionamento:** Incremente o MINOR da versão (ex: 4.20.2 → 4.21.0).
7. **Empacotamento:** Finalize com o comando de build após validar a sintaxe.
8. **Pergunta Portainer (OBRIGATÓRIO):** Todo script de instalação DEVE perguntar "Criar Stack no Portainer?" com opções 0 (editável) ou 1 (direto no Docker). Esta pergunta deve aparecer após todas as outras coletas de dados e antes da tela de confirmação. O deployment deve usar a API do Portainer quando opção 0 for selecionada, ou `docker stack deploy` quando opção 1 for selecionada. **Este é um erro comum — nunca esqueça esta pergunta.**
9. **Estrutura Obrigatória do Script:** Todo script de instalação DEVE seguir esta estrutura:
   ```bash
   #!/usr/bin/bash
   # LOADING - Cores, variáveis de ambiente
   # DETECÇÃO DO TIPO DE INSTALAÇÃO (TRADICIONAL ou CLOUDFLARE_TUNNEL)
   # CARREGAMENTO DE CREDENCIAIS (Cloudflare, Portainer, Postgres)
   # MENU INICIAL (CONTINUAR / SAIR)
   # COLETA DE DADOS (whiptail)
   # PERGUNTA PORTAINER (0=Portainer, 1=Docker)
   # TELA DE CONFIRMAÇÃO
   # BLOCO DE INSTALAÇÃO (whiptail --gauge)
   #   1. Verificar variáveis Cloudflare
   #   2. Configurar DNS (Cloudflare API)
   #   3. Criar banco de dados (se necessário)
   #   4. Gerar secrets (openssl rand)
   #   5. Criar docker-compose.yaml
   #   6. Criar volumes externos
   #   7. Deploy (Portainer API ou docker stack deploy)
   #   8. Aguardar serviços
   # TELA FINAL COM DADOS DE ACESSO
   ```
9.5. **Build e instalação integralmente no Whiptail — ZERO TELA PRETA (⚠️ GATE DE RELEASE):** Todo o processo operacional de instalação DEVE ocorrer dentro de um `whiptail --gauge`. É proibido deixar o usuário exposto ao terminal durante build, download, criação ou envio de imagem, preparação de dependências, banco de dados, volumes, DNS, Portainer ou deploy.

    **REGRA ABSOLUTA:** telas pretas, retorno temporário ao terminal, saída bruta de comandos e mensagens de erro fora do Whiptail são falhas bloqueantes de release.

    - Comandos como `docker build`, `docker pull`, `docker save`, `docker load`, `docker stack deploy`, `docker exec`, `curl`, `git clone`, `npm`, `npx`, `yarn`, `pnpm`, `pip`, compiladores e instaladores de pacotes DEVEM redirecionar `stdout` e `stderr` para um arquivo de log.
    - O usuário deve ver somente mensagens de progresso controladas pelo protocolo `XXX` do `whiptail --gauge`.
    - Cada etapa crítica DEVE verificar explicitamente o código de saída. Nunca presuma sucesso apenas porque o gauge chegou a 100%.
    - Em caso de falha, interrompa o fluxo com código diferente de zero, feche o gauge e mostre um `whiptail --scrolltext --msgbox` com resumo legível, últimas linhas úteis do log e caminho do log completo.
    - Capture o status do bloco de instalação com `${PIPESTATUS[0]}` imediatamente após o pipeline do gauge. Usar apenas `$?` nesse ponto captura o status do Whiptail e pode esconder a falha real.
    - Logs devem usar nome único por instalação em `/tmp`, não podem expor senhas, tokens ou secrets e devem receber toda saída técnica que poderia poluir a interface.
    - É proibido executar uma segunda etapa pesada depois que o gauge terminar. Build, criação da imagem, upload ao Portainer e deploy devem estar dentro do mesmo fluxo visual ou de gauges subsequentes.
    - É proibido mascarar erros com `>/dev/null 2>&1` sem guardar diagnóstico em log e sem apresentar a falha dentro do Whiptail.

    **PADRÃO OBRIGATÓRIO:**
    ```bash
    install_log="/tmp/${nome_app}-install.log"
    error_file="/tmp/${nome_app}-error.log"
    : > "$install_log"
    : > "$error_file"

    {
        echo "XXX\n10\nPREPARANDO INSTALAÇÃO...\nXXX"

        if ! comando_de_build >>"$install_log" 2>&1; then
            {
                echo "Falha ao construir a aplicação."
                echo
                tail -n 20 "$install_log"
            } > "$error_file"
            echo "XXX\n100\nERRO DURANTE O BUILD\nXXX"
            exit 20
        fi

        echo "XXX\n100\nINSTALAÇÃO CONCLUÍDA\nXXX"
    } | whiptail --title "INSTALAÇÃO" --gauge "Preparando aplicação..." 8 70 0
    install_status=${PIPESTATUS[0]}

    if [ "$install_status" -ne 0 ]; then
        error_detail=$(cat "$error_file" 2>/dev/null)
        [ -n "$error_detail" ] || error_detail=$(tail -n 20 "$install_log" 2>/dev/null)
        whiptail --title "ERRO NA INSTALAÇÃO" --scrolltext --msgbox \
            "A instalação foi interrompida.\n\n$error_detail\n\nLog completo: $install_log" 24 90
        exit "$install_status"
    fi
    ```

    **Validação obrigatória antes do empacotamento:** revise o script inteiro e confirme que nenhum comando potencialmente verboso ou demorado está fora do fluxo Whiptail e que todas as saídas técnicas possuem redirecionamento para log. Só empacote quando for impossível surgir tela preta durante uma instalação normal ou durante uma falha.
10. **Credenciais Cloudflare (OBRIGATÓRIO):** O script DEVE carregar as credenciais conforme o tipo de instalação:
    ```bash
    # DETECÇÃO DO TIPO
    INSTALL_TYPE_FILE="/root/.cloudflared_config/installation_type"
    if [ -f "$INSTALL_TYPE_FILE" ]; then
        INSTALL_TYPE=$(cat "$INSTALL_TYPE_FILE")
    else
        INSTALL_TYPE="TRADICIONAL"
    fi
    
    # CARREGAMENTO DE CREDENCIAIS
    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
        source "/root/.cloudflared_config/cloudflare_credentials"
    else
        source "/root/.tradicional_config/tradicional_credentials"
    fi
    ```
    **Variáveis esperadas:** `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ZONE_ID`, `nome_servidor`, `TUNNEL_ID`, `CLOUDFLARE_ACCOUNT_ID`
10.5 **PostgreSQL Compartilhado (ESTRATÉGIA PADRÃO ⚠️):** Por padrão, SEMPRE usar o PostgreSQL compartilhado para novas aplicações. A senha é extraída de `/root/postgres.yaml` (regra 11 abaixo). Apenas criar PostgreSQL dedicado se a aplicação EXIGIR (ex: GitLab).

    **USAR O COMPARTILHADO (quase sempre):**
    - Conectar via hostname `postgres` na porta `5432`
    - Criar database: `CREATE DATABASE $nome_app;`
    - Connection string: `postgresql://postgres:$postgres_password@postgres:5432/$nome_app`
    - SCRIPTS DE REFERÊNCIA: `outline.sh`, `tooljet.sh`, `fireflyiii.sh`

    **QUANDO USAR DEDICADO (exceção):**
    - Se a aplicação EXIGIR extensões específicas do PostgreSQL (pgvector, etc.)
    - Se a aplicação precisar de superuser ou configurações que afetariam outras databases
    - Exemplo: GitLab (banco isolado)
    - Nestes casos, criar stack separada com `postgres:16-alpine`
11. **Carregamento da Senha do Postgres (OBRIGATÓRIO):** Todo script que usa PostgreSQL DEVE extrair a senha do arquivo `/root/postgres.yaml`. **NUNCA use variável de ambiente `$POSTGRES_PASSWORD` diretamente — ela não existe no runtime.**
    ```bash
    # CARREGAR SENHA DO POSTGRES (padrão dos scripts validados)
    postgres_password=$(grep -oP '(?<=POSTGRES_PASSWORD=).+' /root/postgres.yaml)
    
    # USAR NO YAML:
    # - AP_POSTGRES_PASSWORD=$postgres_password
    # - DATABASE_PASSWORD=$postgres_password
    # - KC_DB_PASSWORD=$postgres_password
    ```
    **SCRIPTS DE REFERÊNCIA:** `keycloak.sh`, `baserow.sh` — usam `postgres_password` (minúsculo).
11. **Carregamento da Senha do Mysql (OBRIGATÓRIO):** Todo script que usa Mysql DEVE extrair a senha do arquivo `/root/mysql.yaml`. **NUNCA use variável de ambiente `$MYSQL_PASSWORD` diretamente — ela não existe no runtime.**
    ```bash
    # CARREGAR SENHA DO MYSQL (padrão dos scripts validados)
    senha_mysql=$(grep -oP '(?<=MYSQL_ROOT_PASSWORD=).+' /root/mysql.yaml)
    
    # USAR NO YAML:
    # - AP_POSTGRES_PASSWORD=$senha_mysql
    # - DATABASE_PASSWORD=$senha_mysql
    # - KC_DB_PASSWORD=$senha_mysql
    ```
    **SCRIPTS DE REFERÊNCIA:** `wordpress.sh`, `krayincrm.sh` — usam `senha_mysql` (minúsculo).
12. **Convenção de Nomenclatura (OBRIGATÓRIO):** Todo script DEVE usar sufixo único para evitar conflitos. O padrão é idêntico ao `keycloak.sh`:
    ```bash
    # GERAR SUFIXO ÚNICO
    nome_principal="nome_da_app"
    sufixo_app=$(date | md5sum | head -c7)
    nome_app=$nome_principal$sufixo_app
    # Resultado: nome_da_appd357ed0
    
    # USAR EM TUDO:
    # - Arquivo YAML: cat > $nome_app.yaml <<EOL
    # - Nome da stack: STACK_NAME=$nome_app
    # - Banco de dados: CREATE DATABASE $nome_app
    # - Volumes: ${nome_app}_cache, ${nome_app}_redis
    # - Serviços: ${nome_app}, ${nome_app}_web, ${nome_app}_prosody
    ```
    **NUNCA use nomes fixos** como `activepieces.yaml` ou `jitsi.yaml` — sempre use `$nome_app.yaml`.
12. **Configuração DNS (OBRIGATÓRIO):** O script DEVE configurar o DNS automaticamente. Verificar se as variáveis estão definidas antes de usar:
    ```bash
    # VERIFICAR VARIÁVEIS
    if [ -z "$CLOUDFLARE_API_TOKEN" ] || [ -z "$CLOUDFLARE_ZONE_ID" ]; then
        echo "AVISO: CREDENCIAIS DO CLOUDFLARE NÃO ENCONTRADAS"
    fi
    
    # FALLBACK PARA nome_servidor
    if [ -z "$nome_servidor" ]; then
        nome_servidor=$(hostname -I | awk '{print $1}')
    fi
    
    # CRIAR CNAME (TRADICIONAL)
    CNAME_RESPONSE=$(curl -s -X POST \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data '{"type":"CNAME","name":"'"$url_app"'","content":"'"$nome_servidor"'.'"$DOMINIO_PRINCIPAL"'","ttl":1,"proxied":false}')
    
    # VERIFICAR SUCESSO
    if echo "$CNAME_RESPONSE" | grep -q '"success":true'; then
        echo "REGISTRO CNAME CRIADO COM SUCESSO!"
    else
        echo "ERRO AO CRIAR REGISTRO CNAME"
        echo "$CNAME_RESPONSE" | jq -r '.errors[].message' 2>/dev/null
    fi
    ```
13. **Cloudflare Tunnel via API (OBRIGATÓRIO):** Para instalações CLOUDFLARE_TUNNEL, NÃO edite arquivos nem reinicie serviços. Use a API do Cloudflare:
    ```bash
    # CRIAR CNAME PARA TUNNEL
    CNAME_RESPONSE=$(curl -s -X POST \
        "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data '{"type":"CNAME","name":"'"$url_app"'","content":"'"$TUNNEL_ID"'.cfargotunnel.com","ttl":1,"proxied":true}')
    
    # OBTER CONFIGURAÇÃO ATUAL DO TUNNEL
    TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
    TMPDIR=$(mktemp -d)
    BACKUP_RAW="$TMPDIR/backup_raw.$TIMESTAMP.json"
    TO_PUT="$TMPDIR/to_put.$TIMESTAMP.json"
    
    curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      | jq '.' > "$BACKUP_RAW"
    
    # ADICIONAR NOVA ROTA
    NEW_SERVICE="http://${nome_app}:80"
    jq --arg host "$url_app" --arg service "$NEW_SERVICE" '
      (.result.config // {}) as $cfg
      | ($cfg.ingress // []) as $ing
      | ($ing | map(select(.service != "http_status:404"))) as $clean
      | ($clean | map(.hostname // "")) as $existing_names
      | (if ($existing_names | index($host)) then $clean else ($clean + [ { hostname: $host, service: $service, originRequest: { noTlsVerify: true, httpHostHeader: $host } } ]) end) as $merged
      | ($merged + [{ service: "http_status:404" }]) as $final_ing
      | ($cfg + { ingress: $final_ing }) as $newcfg
      | { config: $newcfg }
    ' "$BACKUP_RAW" > "$TO_PUT"
    
    # APLICAR NOVA CONFIGURAÇÃO
    APPLY_RESPONSE=$(curl -sS -X PUT "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json" \
      --data-binary @"$TO_PUT")
    
    rm -rf "$TMPDIR"
    ```
    **NUNCA** use `systemctl restart cloudflared` — o serviço pode não existir.
13.5. **Verificar rota existente antes de criar (OBRIGATÓRIO):** Para instalações CLOUDFLARE_TUNNEL, SEMPRE verifique se a URL já existe no tunnel antes de criar a rota. O jq DEVE SUBSTITUIR rotas existentes, nunca pular:
    ```bash
    # CHECK ANTES DO GAUGE (no input da URL, antes do whiptail gauge)
    if [ "$INSTALL_TYPE" = "CLOUDFLARE_TUNNEL" ]; then
        CHECK_RESPONSE=$(curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
          "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations")
        EXISTING_HOST=$(echo "$CHECK_RESPONSE" | jq -r --arg h "$url_app" '.result.config.ingress[] | select(.hostname == $h) | .hostname' 2>/dev/null)
        if [[ -n "$EXISTING_HOST" ]]; then
            EXISTING_SERVICE=$(echo "$CHECK_RESPONSE" | jq -r --arg h "$url_app" '.result.config.ingress[] | select(.hostname == $h) | .service' 2>/dev/null)
            whiptail --title "Rota Existente" --msgbox "Já existe uma rota configurada para:\n\nURL: $url_app\nServiço: $EXISTING_SERVICE\n\nA rota será substituída pela nova aplicação." --fb 14 70
        fi
    fi

    # JQ DEVE SEMPRE SUBSTITUIR (nunca pular se hostname já existe):
    jq --arg host "$url_app" --arg service "$NEW_SERVICE" '
      (.result.config // {}) as $cfg
      | ($cfg.ingress // []) as $ing
      | ($ing | map(select(.service != "http_status:404"))) as $clean
      | ($clean | map(select(.hostname != $host))) as $filtered
      | ($filtered + [ { hostname: $host, service: $service, originRequest: { noTlsVerify: true, httpHostHeader: $host } } ]) as $merged
      | ($merged + [{ service: "http_status:404" }]) as $final_ing
      | ($cfg + { ingress: $final_ing }) as $newcfg
      | { config: $newcfg }
    ' "$BACKUP_RAW" > "$TO_PUT"
    ```
14. **Geração do YAML com Labels Condicionais (OBRIGATÓRIO):** O docker-compose.yaml DEVE ser gerado em 3 blocos separados. As labels do Traefik são adicionadas APENAS quando `INSTALL_TYPE = "TRADICIONAL"`. **Este é o erro mais comum e mais difícil de detectar — labels do Traefik no CLOUDFLARE_TUNNEL causam conflito e impedem a stack de ficar editável no Portainer.**

    **ATENÇÃO - ANTES de criar o YAML, execute `cd` + `cd` para garantir que o arquivo seja salvo em `/root/`:**
    ```bash
    # SEMPRE fazer cd ANTES de criar o YAML
    cd
    cd
    
    cat > $nome_app.yaml <<EOL
    ...
    EOL
    ```
    **SEM ESTE `CD`**, o YAML pode ser salvo em outro diretório e o Portainer não encontra o arquivo em `STACK_FILE_PATH="/root/$nome_app.yaml"`.
    ```bash
    # BLOCO 1: YAML principal (services + config)
    cat > $nome_app.yaml << EOL

    version: "3.7"
    services:
      $nome_app:
        image: ...
        networks:
          - externa
          - interna
        environment:
          ...
        deploy:
          mode: replicated
          replicas: 1
          placement:
            constraints:
              - node.role == manager
          resources:
            limits:
              cpus: "1"
              memory: 1024M
    EOL

    # BLOCO 2: LABELS DO TRAEFIK (APENAS PARA TRADICIONAL)
    if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
    cat >> $nome_app.yaml << EOL
          labels:
          - traefik.enable=true
          - traefik.docker.network=externa
          - traefik.http.routers.$nome_app.rule=Host(\`$url_app\`)
          - traefik.http.routers.$nome_app.entrypoints=websecure
          - traefik.http.routers.$nome_app.priority=1
          - traefik.http.routers.$nome_app.tls.certresolver=letsencryptresolver
          - traefik.http.routers.$nome_app.tls=true
          - traefik.http.routers.$nome_app.service=$nome_app
          - traefik.http.services.$nome_app.loadbalancer.server.port=80
    EOL
    fi

    # BLOCO 3: Networks e Volumes
    cat >> $nome_app.yaml << EOL

    networks:
      externa:
        external: true
      interna:
        external: true

    volumes:
      ${nome_app}_cache:
        external: true
        name: ${nome_app}_cache
    EOL
    ```

    **POR QUE ISTO É CRÍTICO:**
    - No **TRADICIONAL**, o Traefik é o reverse proxy. As labels dizem ao Traefik como rotear o tráfego.
    - No **CLOUDFLARE_TUNNEL**, o Cloudflare Tunnel roteia diretamente. Labels do Traefik são DESNECESSÁRIAS e causam conflito.
    - Se as labels estiverem presentes no CLOUDFLARE_TUNNEL, o Portainer pode ter problemas ao gerenciar a stack (serviços com labels de Traefik mas sem rede `externa` conectada ao Traefik).

    **SCRIPTS DE REFERÊNCIA:** `keycloak.sh`, `baserow.sh` — estes scripts usam o padrão correto com `cat >` + `cat >>` condicional.
14.5. **NÃO usar YAML Anchors no docker-compose.yaml (OBRIGATÓRIO):** O parser YAML do Portainer/Docker Compose NÃO suporta YAML anchors (`&nome`), merge keys (`<< : *nome`) nem merge keys com arrays (`<< : [*anchor1, *anchor2]`). **Este é um erro silencioso — o YAML parece válido mas o Portainer rejeita com `yaml: line X: could not find expected ':'`.**
    ```bash
    # ❌ ERRADO (Portainer REJEITA):
    x-flags: &penpot-flags
      PENPOT_FLAGS: disable-email-verification enable-smtp
    x-uri: &penpot-public-uri
      PENPOT_PUBLIC_URI: https://domain.com
    services:
      app:
        environment:
          << : [*penpot-flags, *penpot-public-uri]
          APP_EXTRA_VAR: value

    # ✅ CORRETO (variáveis inline em cada serviço):
    services:
      app:
        environment:
          - PENPOT_FLAGS=disable-email-verification enable-smtp
          - PENPOT_PUBLIC_URI=https://domain.com
          - APP_EXTRA_VAR=value
    ```
    **REGRA:** Sempre use formato de lista (`- KEY=value`) ou map (`KEY: value`) com variáveis inline. Nunca use `&anchors`, `*references`, nem `<<` merge keys.
    **SCRIPT DE REFERÊNCIA:** `penpot.sh` — corrigido de YAML anchors para inline.
14.6. **Estrutura do YAML Docker Compose (OBRIGATÓRIO):** O YAML DEVE seguir EXATAMENTE a estrutura dos scripts validados (waha.sh, keycloak.sh). **Erros de estrutura causam `yaml: line X: could not find expected ':'` no Portainer.**
    ```yaml
    # ✅ ESTRUTURA CORRETA (ordem exata):
    # BLOCO 1: cat > $nome_app.yaml << EOL

    version: "3.7"
    services:
      $nome_app:
        image: ...
        hostname: $nome_app
        networks:
          - externa
          - interna
        environment:
          - CHAVE=valor          # ← Lista com "- " (NÃO map)
        deploy:
          mode: replicated
          replicas: 1
          placement:
            constraints:
            - node.role == manager
          resources:
            limits:
              cpus: "1"
              memory: 1024M
    EOL

    # BLOCO 2: if TRADICIONAL → cat >> labels
    # BLOCO 3: cat >> networks + volumes (SEMPRE no final)

    networks:
      externa:
        external: true
      interna:
        external: true

    volumes:
      ${nome_app}_cache:
        external: true
        name: ${nome_app}_cache
    EOL
    ```

    **REGRAS ABSOLUTAS (causam erro silencioso no Portainer):**
    1. **`services:` PRIMEIRO** — nunca `networks:` ou `volumes:` antes de `services:`
    2. **`networks:` e `volumes:` SOMENTE no final** — chaves duplicadas no nível raiz rejeitam o YAML
    3. **`version: "3.7"`** — usar sempre 3.7 (não 3.8)
    4. **`environment` em formato LISTA** (`- CHAVE=valor`) — NUNCA map (`CHAVE: valor`) nem YAML anchors
    5. **`depends_on` em formato LISTA** (`- nome_servico`) — NUNCA map com `condition:`
    6. **Blanks line após `<< EOL`** antes de `version:`
    7. **Blanks line entre `cat >>`** de blocos diferentes (services extras)
    8. **`cat >` para primeiro bloco, `cat >>` para blocos seguintes** — NUNCA `cat >>` no primeiro
    9. **`openssl rand -base64` SEMPRE com `tr -d '\n'`** — base64 longo quebra linha em 76 chars, invalidando o YAML. Ex: `$(openssl rand -base64 64 | tr -d '\n')`

    **SCRIPT DE REFERÊNCIA:** `waha.sh`, `keycloak.sh` — seguem esta estrutura EXATA.
15. **Deploy com Tratamento de Erro (OBRIGATÓRIO):** O script DEVE tratar erros em cada etapa do deployment. O padrão correto usa funções separadas (como `keycloak.sh` e `baserow.sh`):
    ```bash
    # Caminho CORRETO do arquivo de credenciais do Portainer
    dados_file="$HOME/dados_portainer/dados_portainer"

    if [[ -f "$dados_file" ]]; then
        PORTAINER_URL=$(grep "Dominio do portainer:" "$dados_file" | cut -d':' -f2 | xargs)
        ADMIN_USERNAME=$(grep "Usuario:" "$dados_file" | cut -d':' -f2 | xargs)
        ADMIN_PASSWORD=$(grep "Senha:" "$dados_file" | cut -d':' -f2 | xargs)
        STACK_NAME=$nome_app
        STACK_FILE_PATH="/root/$nome_app.yaml"
    else
        echo "ARQUIVO dados_portainer NÃO ENCONTRADO - Usando docker deploy..."
        docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
        exit 1
    fi

    # Função para autenticação
    get_auth_token() {
        RESPONSE=$(curl -sk -X POST "https://$PORTAINER_URL/api/auth" \
            -H "Content-Type: application/json" \
            -d "{\"username\": \"$ADMIN_USERNAME\", \"password\": \"$ADMIN_PASSWORD\"}")
        TOKEN=$(echo "$RESPONSE" | jq -r '.jwt')
        if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
            docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
            exit 1
        fi
    }

    # Função para obter o EndpointID
    get_endpoint_id() {
        RESPONSE=$(curl -sk -X GET "https://$PORTAINER_URL/api/endpoints" \
            -H "Authorization: Bearer $TOKEN")
        ENDPOINT_ID=$(echo "$RESPONSE" | jq -r '.[0].Id')
        if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" = "null" ]; then
            docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
            exit 1
        fi
    }

    # Função para obter o SwarmID
    get_swarm_id() {
        RESPONSE=$(curl -sk -X GET "https://$PORTAINER_URL/api/endpoints/$ENDPOINT_ID/docker/swarm" \
            -H "Authorization: Bearer $TOKEN")
        SWARM_ID=$(echo "$RESPONSE" | jq -r '.ID')
        if [ -z "$SWARM_ID" ] || [ "$SWARM_ID" = "null" ]; then
            docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
            exit 1
        fi
    }

    # Função para criar a stack
    create_stack() {
        if [ ! -f "$STACK_FILE_PATH" ]; then
            docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
            exit 1
        fi
        response_output=$(mktemp)
        erro_output=$(mktemp)
        http_code=$(curl -s -o "$response_output" -w "%{http_code}" -k -X POST \
            -H "Authorization: Bearer $TOKEN" \
            -F "Name=$STACK_NAME" \
            -F "file=@$STACK_FILE_PATH" \
            -F "SwarmID=$SWARM_ID" \
            -F "endpointId=$ENDPOINT_ID" \
            "https://$PORTAINER_URL/api/stacks/create/swarm/file" 2> "$erro_output")
        response=$(cat "$response_output")
        rm -f "$response_output" "$erro_output"
        if [ "$http_code" -ne 200 ]; then
            docker stack deploy --prune --resolve-image always -c $nome_app.yaml $nome_app >/dev/null 2>&1
            exit 1
        fi
    }

    # Fluxo de execução principal
    get_auth_token || exit 1
    get_endpoint_id || exit 1
    get_swarm_id || exit 1
    create_stack || exit 1
    ```

    **ATENÇÃO:** O caminho do arquivo de credenciais é `$HOME/dados_portainer/dados_portainer` (NÃO `/root/dados_vps/dados_portainer`).
16. **Checklist Final (antes de commitar):**
    - [ ] Script criado em x86 E ARM
    - [ ] Menu adicionado ao install.sh (x86 E ARM)
    - [ ] Case statement adicionado (x86 E ARM)
    - [ ] Bloco SHC adicionado (start_full.sh E start_arm_full.sh)
    - [ ] **SHC com `if PLANO free`**: Todo app PRO DEVE ter o bloco de deleção `if [[ ("$PLANO" == "free") || ("$PLANO" == "free1") || ("$PLANO" == "free2") ]]; then rm <binário>; fi` em AMBOS os gatilhos
    - [ ] **Menu PRO com tag `"PRO"`**: Todo app PRO DEVE aparecer com tag `"PRO"` em TODOS os menus free/free1/free2 — visível mas bloqueado
    - [ ] **Menu PRO com tag `""`**: Todo app PRO DEVE aparecer com tag `""` (disponível) no menu PRO
    - [ ] **1_codigo_fonte/ferramentas.html**: Atualizar TODAS as menções de versão (subtítulo E rodapé) — usar `grep -n "4\." 1_codigo_fonte/ferramentas.html` para encontrar todas
    - [ ] Pergunta Portainer adicionada
    - [ ] Variáveis Cloudflare verificadas antes de usar
    - [ ] `nome_servidor` com fallback para IP
    - [ ] **Sufixo único** gerado (`$nome_app`) e usado em tudo (yaml, stack, volumes, banco)
    - [ ] **Tunnel via API** (não `systemctl restart cloudflared`)
    - [ ] **Labels Traefik condicionais** (APENAS quando `INSTALL_TYPE = "TRADICIONAL"`)
    - [ ] **`cd` + `cd` antes de criar YAML** (garante salvamento em `/root/`)
    - [ ] **NÃO deletar o YAML após deploy** (`rm -f $nome_app.yaml` — o arquivo DEVE permanecer em `/root/`)
    - [ ] **Shebang `#!/usr/bin/bash`** (NUNCA usar `#!/usr/bin/env bash` — SHC não reconhece)
    - [ ] **Redis dedicado via Portainer API**: Se `criar_portainer == "0"`, AMBOS os stacks (Redis + App) DEVEM ser criados via API do Portainer
    - [ ] Deploy com tratamento de erro em cada etapa
    - [ ] **ZERO TELA PRETA:** Build, downloads, criação/envio de imagem, Portainer e deploy executados integralmente dentro do Whiptail
    - [ ] **LOG DE ERROS:** `stdout`/`stderr` técnicos direcionados para log único em `/tmp`, sem secrets, com falhas exibidas em `whiptail --scrolltext --msgbox`
    - [ ] **STATUS REAL DO GAUGE:** `${PIPESTATUS[0]}` capturado imediatamente após o pipeline e validado antes da tela de sucesso
    - [ ] Nenhum comando verboso/demorado executado depois do fechamento do gauge
    - [ ] Versão incrementada no install.sh (x86 E ARM)
    - [ ] Empacotamento executado com sucesso

## REGRA PARA CRIAÇÃO DE COMBOS
Ao criar ou atualizar um combo:
1. **Script:** Crie o script `combo_nome.sh` em ambos os diretórios de arquitetura.
2. **Integração:** O combo deve usar as redes Docker existentes (`interna`, `externa`) e o PostgreSQL compartilhado.
3. **DNS:** Implemente lógica de DNS automático para os 3 cenários (TRADICIONAL+DNS automático, TRADICIONAL+DNS manual, CLOUDFLARE_TUNNEL).
4. **Menu:** O combo deve aparecer no `install.sh` com asterisco (*) indicando combo pré-integrado.
5. **Planos:** Defina se o combo é Pro, Free, ou disponível em todos os planos.
6. **Versionamento:** Incremente o MINOR da versão.
7. **Documentação:** Descreva o que o combo faz no nome do menu (ex: "OPENCLAW + QDRANT + NEO4J + COGNEE + SEARXNG*").

## SCRIPT DE REFERÊNCIA (LEGADO)

### Propósito
O diretório `/4_referencia/` contém o script antigo de deploy (apenas leitura). Este script é uma referência para identificar ferramentas que ainda não foram migradas para o projeto atual.

### Regras de Uso
1. **NUNCA EDITE** arquivos em `/4_referencia/` — são apenas referência.
2. **NÃO ASSUMA** que todo item do script antigo precisa ser migrado — muitos já existem no projeto atual.
3. **FLUXO DE MIGRAÇÃO:**
   - Analise o script antigo identificando ferramentas/funções.
   - Cruze com o que já existe em `/1_codigo_fonte/`.
   - Liste apenas o que é novo e precisa ser adicionado.
   - Siga a REGRAS PARA ADIÇÃO DE NOVAS FERRAMENTAS acima para cada item a ser migrado.

### Checklist de Migração (por ferramenta)
Antes de migrar, confirme:
- [ ] A ferramenta não existe já em `x86/` ou `arm/` do projeto atual.
- [ ] A rede Docker do script antigo (`interna/externa`) é compatível com o novo setup (Cloudflare Tunnel + Traefik).
- [ ] A lógica de DNS automático do novo projeto será aplicada.
- [ ] O script será escrito para AMBAS as arquiteturas (x86 e ARM).
- [ ] O bloco SHC será adicionado corretamente em ambos os gatilhos.

### Passos Obrigatórios pós-Migração
Após criar o script da ferramenta em ambas as arquiteturas:
1. **Menu:** Atualize o menu `whiptail` no `install.sh` (x86 e ARM) — adicionar opção + case statement.
2. **SHC:** Adicione o bloco de compilação em `start_full.sh` (x86) e `start_arm_full.sh` (ARM).
3. **⚠️ VERSÃO (NÃO ESQUECER!):** Incremente o MINOR da versão em **TODOS** os seguintes arquivos:
   - `install.sh` (x86) — variável `VERSIONSETUP`
   - `install.sh` (ARM) — variável `VERSIONSETUP`
   - `setup-mno.sh` — variável `VERSIONSETUP`
   - `setup-mno-oracle.sh` — variável `VERSIONSETUP`
   - `start_full.sh` — variável `VERSIONSETUP`
   - `start_arm_full.sh` — variável `VERSIONSETUP`
   - `1_codigo_fonte/ferramentas.html` — **TODAS** as menções da versão: subtítulo (`Versão X.Y.Z | Atualizado em...`) E rodapé (`Setup MNO vX.Y.Z | Documentação gerada automaticamente`). Use `grep -n "4\." 1_codigo_fonte/ferramentas.html` para encontrar TODAS as ocorrências antes de alterar.
   - Ex: `4.25.0` → `4.26.0`
   - **USE O COMANDO: `grep -rn "VERSIONSETUP" 1_codigo_fonte/` para verificar se TODOS foram atualizados**
4. **Catálogo de setups:** Atualize `1_codigo_fonte/ferramentas.html`:
   - Adicionar novo setup com descrição, categorias, uso e exemplos
   - **Adicionar campo RAM** logo após os "Exemplos práticos": `<div class="tool-examples"><strong>RAM:</strong> ~XGB</div>`
   - Atualizar contadores: Total de Setups, Total X86, Total ARM
   - Adicionar campo de compatibilidade (X86 e ARM ou X86)
   - **Atualizar versão e data** no subtítulo (ex: "Versão 4.25.0 | Atualizado em Julho/2026")
   - **⚠️ REGRA DE INSERÇÃO:** NUNCA usar `c.replace('tool-name">NOME'` para inserir cards — isso cria tags `<div class="tool-card">` vazias e perde a tag de abertura do card seguinte. SEMPRE usar `grep -n` para encontrar a linha exata do card ANTERIOR ao ponto de inserção, e usar `sed -i` com o contexto completo da linha `</div>` + `<div class="tool-card">` + `<div class="tool-name">NOME_ANTERIOR`. Após inserir, verificar com `grep -c tool-card` e `grep -c tool-name` que os números são iguais.
5. **Empacotamento:** Rode `./2_empacotador/gerar_distribuicao.sh`.
6. **Git:** Faça commit das alterações com mensagem descritiva (ex: `feat: adicionar Keycloak (IAM/SSO)`).

### Checklist de Validação (ANTES de empacotar)
**⚠️ NÃO empacote até verificar TODOS os itens:**
- [ ] Script criado em x86 E ARM
- [ ] Menu adicionado ao install.sh (x86 E ARM) — **se incompatível com ARM, omitir do menu ARM**
- [ ] Case statement adicionado (x86 E ARM)
- [ ] Bloco SHC adicionado (start_full.sh E start_arm_full.sh)
- [ ] **VERIFICAR CONFLITO DE PORTA**: Antes de adicionar porta `ports:` no YAML, verificar se já existe outra app usando a mesma porta host. Se conflitar, usar porta alternativa. Portas atuais: 53(Pi-hole), 80(Filebrowser), 3000(Gitea), 3001(AdGuard), 3002(Grafana), 3080(LibreChat), 4200(OpenFang), 5672(RabbitMQ), 6333(Qdrant), 6334(Qdrant), 7474(Neo4j), 7687(Memgraph), 7688(Memgraph), 8000(Windmill), 8001(Cognee), 8080(Ghost), 8081(Autogen), 8082(RedisCommander), 8083(Matomo), 8090(PocketBase), 8091(Beszel), 8123(ClickHouse), 8124(Langfuse), 8880(SearXNG), 9000(ClickHouse), 9001(Langfuse), 9009(ClickHouse), 9010(Langfuse), 13000(NocoBase), 18789(OpenClaw), 2222(Gitea SSH)
- [ ] **VERSÃO ATUALIZADA** nos 6 arquivos de instalação e no catálogo ativo:
  - `install.sh` (x86) — `VERSIONSETUP`
  - `install.sh` (ARM) — `VERSIONSETUP`
  - `setup-mno.sh` — `VERSIONSETUP`
  - `setup-mno-oracle.sh` — `VERSIONSETUP`
  - `start_full.sh` — `VERSIONSETUP`
  - `start_arm_full.sh` — `VERSIONSETUP`
  - `1_codigo_fonte/ferramentas.html` — **TODAS** as menções: subtítulo + rodapé + contadores baseados no menu PRO
- [ ] **1_codigo_fonte/ferramentas.html atualizado** com novo setup + versão + contadores (baseados no menu PRO)
- [ ] Empacotamento executado com sucesso

### Análise de Atualizações no Script Antigo
O script antigo pode ser atualizado constantemente com novas ferramentas. Quando o usuário solicitar uma nova análise:

1. **Releia** o script em `/4_referencia/script_antigo.sh`.
2. **Identifique** todas as ferramentas presentes (via menu e funções `nome_*`).
3. **Cruze** com a lista atual de scripts em `1_codigo_fonte/x86/SetupLowCodeMno/` e `1_codigo_fonte/arm/SetupLowCodeMno/`.
4. **Classifique** cada ferramenta em:
   - **JÁ EXISTE** — já implementada no projeto atual (ignorar).
   - **MIGRÁVEL** — existe no antigo, não existe no atual. Candidata a migração.
   - **NOVA NO ATUAL** — existe no atual mas não no antigo (já foi criada/migrada anteriormente).
   - **DESCARTÁVEL** — não faz sentido migrar (legada, obsoleta, ou incompatível com a nova arquitetura).
5. **Gere relatório** com a classificação acima, incluindo categoria e prioridade para cada ferramenta migrável.

### Diferenças Arquiteturais Importantes
O script antigo e o projeto atual possuem diferenças fundamentais que afetam a migração:

| Aspecto | Script Antigo | Projeto Atual |
|---|---|---|
| **Rede** | `interna` / `externa` | `interna` / `externa` + Cloudflare Tunnel |
| **Reverse Proxy** | Traefik (docker swarm) | Traefik + Cloudflare Tunnel |
| **DNS** | Manual | Automático (3 cenários) |
| **Deploy** | Via API Portainer | Via script bash direto |
| **Licenciamento** | Sem SHC | SHC com expiração por plano |
| **Planos** | Sem controle | Free / Free1 / Free2 / Pro |
| **Arquitetura** | x86 apenas (ou com variantes ARM manuais) | x86 e ARM espelhados automaticamente |
| **Empacotamento** | Script único | ZIPs separados por plano |

### Categorias de Ferramentas

**Infraestrutura** (migrar com cuidado extra — afetam todo o setup):
- Traefik, Portainer, Docker Swarm, MongoDB, PostgreSQL, Redis, RabbitMQ, ClickHouse

**Aplicações Principais** (alta demanda, migrar primeiro):
- Chatwoot, Evolution API, N8N, Typebot, Flowise, Dify AI

**Ferramentas de Suporte** (migrar conforme demanda):
- PgAdmin, Adminer, Uptime Kuma, Grafana, Metabase, RedisInsight

**Ferramentas Específicas** (migrar apenas se houver demanda):
- Odoo, Moodle, AzuraCast, Traccar, etc.

### Estado da Migração (referência rápida)
Para consultar o estado atual da migração, peça uma "análise de migração" ao agente — ele lerá o script antigo e o projeto atual, e gerará um relatório atualizado com a classificação de cada ferramenta.

### Scripts de Referência Validados (Migração)
Os seguintes scripts foram validados em produção e devem ser usados como **referência padrão** para novas migrações ou instalações do zero:

| Script | Uso como referência |
|---|---|
| `activepieces.sh` | Padrão para apps com PostgreSQL + Redis |
| `jitsi.sh` | Padrão para apps com múltiplos containers |
| `keycloak.sh` | Padrão para apps com PostgreSQL + proxy reverso |

**Por banco de dados:**

| Script | Banco | Observação |
|---|---|---|
| `mautic6padrao.sh` | MySQL | Padrão para apps com MySQL |
| `ghost.sh` | MySQL | MySQL self-hosted + Node.js |
| `wekan.sh` | MongoDB | Padrão para apps com MongoDB |
| `heyform.sh` | MongoDB | Padrão para apps com MongoDB + Redis |
| `wordpress.sh` | MySQL | WordPress com PHP |
| `krayincrm.sh` | MySQL | CRM Laravel |
| `glpi.sh` | MySQL | ITSM/GLPI |

**Combos validados (múltiplos containers):**

| Script | Componentes |
|---|---|
| `chatwootn_evo2_rabbitmq_minio.sh` | Chatwoot + Evolution 2.0 + RabbitMQ + MinIO |
| `chatwootn_evon_rabbitmq.sh` | Chatwoot + Evolution + RabbitMQ |
| `evoai_evo2_minio.sh` | Evo AI + Evolution 2.0 + MinIO |
| `plane.sh` | Plane (API + Web + Admin + Space + Nginx) + Redis + RabbitMQ |

Ao migrar novas ferramentas, **copie a estrutura** de um desses scripts como base.

### Aviso: Ferramentas com MySQL
**ATENÇÃO:** Antes de migrar qualquer ferramenta que use MySQL, **PERGUNTE AO USUÁRIO** primeiro. Existem peculiaridades na migração que variam caso a caso (versão do MySQL, collation, charset, configurações de engine). Não assuma que o padrão PostgreSQL se aplica.

**⚠️ REGRA OBRIGATÓRIA PARA VERIFICAÇÃO DO CONTAINER MySQL 8.0:**
```bash
# NÃO usar (encontra MySQL 8.0 E 8.4):
mysql_container=$(docker ps -qf name=mysql)

# USAR (encontra APENAS MySQL 8.0):
mysql_container=$(docker ps --format "{{.Names}}" | grep -q "^mysql$")
```

**Por que?** O Percona 8.4 (usado pelo Mautic 7) tem o container nomeado "mysql84", que contém "mysql" no nome. O filtro `name=mysql` encontra AMBOS.

**Arquivos MySQL:**
- MySQL 8.0: `/root/mysql.yaml` (usado por todas as aplicações)
- MySQL 8.4: `/root/mysql84.yaml` (usado apenas por Mautic 7)

### Aviso: Ferramentas com MongoDB
**ATENÇÃO:** MongoDB e MySQL NÃO são essenciais como Redis e PostgreSQL (que são instalados no início). Para aplicações que usam MongoDB, siga o mesmo padrão do MySQL:

1. **Verificar se MongoDB já existe:**
   ```bash
   if docker stack ls | grep -q "mongodb "; then
       user_mongo=$(grep -oP '(?<=MONGO_INITDB_ROOT_USERNAME=).+' /root/mongodb.yaml)
       pass_mongo=$(grep -oP '(?<=MONGO_INITDB_ROOT_PASSWORD=).+' /root/mongodb.yaml)
   else
       # Criar stack MongoDB
   fi
   ```

2. **Se não existir, criar stack MongoDB automaticamente:**
   - Usar `mongo:7` como imagem
   - Criar `/root/mongodb.yaml` COMPLETO (não apenas credenciais — stack inteira, como MySQL)
   - Deploy único: `docker stack deploy --prune --resolve-image always -c mongodb.yaml mongodb`

3. **Exemplo de criação de stack:**
   ```bash
   user_mongo="admin"
   pass_mongo=$(openssl rand -hex 16)

   # Criar mongodb.yaml COMPLETO em /root (padrão MySQL)
   cat > /root/mongodb.yaml << EOL
   version: '3.7'
   services:
       mongodb:
           image: mongo:7
           hostname: mongodb
           environment:
               - MONGO_INITDB_ROOT_USERNAME=$user_mongo
               - MONGO_INITDB_ROOT_PASSWORD=$pass_mongo
           networks:
               - interna
           volumes:
               - mongodb_data:/data/db
               - mongodb_configdb:/data/configdb
           deploy:
               placement:
                   constraints: [node.role == manager]
   volumes:
       mongodb_data:
       mongodb_configdb:
   networks:
       interna:
           external: true
           name: interna
   EOL

   # Deploy único
   docker stack deploy --prune --resolve-image always -c mongodb.yaml mongodb >/dev/null 2>&1
   ```

4. **Referências:** `wekan.sh`, `heyform.sh`, `rocketchat.sh`

### Compatibilidade com ARM (Importante)

**O instalador antigo NÃO contempla ARM.** Algumas imagens Docker só possuem build para x86. O instalador atual suporta ambas as arquiteturas, mas requer validação.

**Regra de Espelhamento (ESTRATÉGIA):**
- **Scripts .sh**: SEMPRE espelhar em `x86/SetupLowCodeMno/` E `arm/SetupLowCodeMno/` — mesmo para ferramentas x86-only. No futuro, se surgir imagem ARM, basta liberar no menu.
- **SHC blocks**: SEMPRE adicionar em AMBOS os gatilhos (`start_full.sh` x86 E `start_arm_full.sh` ARM).
- **Case statements**: SEMPRE espelhar em ambas as versões do `install.sh` (x86 E ARM).
- **Menu whiptail**: é a ÚNICA coisa que difere entre x86 e ARM. Ferramentas incompatíveis com ARM são ** OMITIDAS ** (deletadas, não comentadas) do menu do `install.sh` ARM.

**Regras para adicionar ferramentas:**
1. **Verificar compatibilidade ARM** antes de adicionar ao menu:
   ```bash
   docker manifest inspect imagem:tag | jq '.manifests[] | select(.platform.architecture=="arm64")'
   ```
2. **Se NÃO existir build ARM**: NÃO adicione ao menu do `install.sh` ARM. Mantenha scripts .sh, SHC blocks e case statements espelhados.
3. **Se existir build ARM**: adicione ao menu de AMBOS (x86 e ARM).
4. **Scripts de combo** devem ter TODAS as imagens compatíveis com ARM para funcionar.

**Como ocultar ferramenta incompatível com ARM:**
No `install.sh` do ARM, DELETE a linha do menu whiptail (NÃO comente):
```bash
# NÃO fazer (quebra whiptail):
# "NOME_DA_FERRAMENTA" "" \

# FAZER:
# Simplesmente deletar a linha do menu whiptail
# Manter: script .sh, SHC block, case statement — tudo espelhado
```

**Contagem de setups:**
- O campo **Total de Setups (Deploys / Instalações)** representa a soma das configurações instaláveis do primeiro menu PRO do `install.sh` x86 (o bloco `if [[ ! "$PLANO" = *free* ]]; then`), não a quantidade de cards/aplicações únicas do catálogo.
- Os campos de arquitetura usam a mesma regra no menu PRO de cada arquitetura: `Total X86` vem do menu x86 e `Total ARM` vem do menu ARM.
- Exclua sempre os utilitários de sistema, que não são setups: `REINICIAR APPS/SERVIÇOS`, `DELETAR APPS/STACKS`, `GERADOR DE REGISTROS DNS`, `ESSENCIAIS EDITÁVEIS NO PORTAINER` e `SAIR`. O separador visual também não entra na soma.
- x86 e ARM podem ter contagens diferentes.
- Para auditar, conte as entradas entre `whiptail --menu` e `3>&2 2>&1 1>&3` do primeiro menu (PRO), removendo os cinco utilitários acima e o separador; valide manualmente antes de atualizar o catálogo ativo.
- Um combo é qualquer entrada cujo nome termina com `*` no menu PRO. Não deduplicate componentes: ferramentas podem aparecer em mais de um setup.
- Métricas de GitHub só podem ser atribuídas a setups individuais; combos devem exibir `Não aplicável` e não herdar estrelas de seus componentes.

**Fluxo ao adicionar nova ferramenta x86-only:**
1. Criar script em `x86/SetupLowCodeMno/`
2. Copiar para `arm/SetupLowCodeMno/` (mesmo sendo x86-only)
3. Adicionar SHC block em AMBOS os gatilhos
4. Adicionar case statement em AMBOS os install.sh
5. Adicionar ao menu whiptail APENAS no `install.sh` x86
6. NÃO adicionar ao menu do `install.sh` ARM
7. Atualizar contadores no catálogo `1_codigo_fonte/ferramentas.html`

**Fluxo ao adicionar nova ferramenta multi-arch:**
1. Criar script em `x86/SetupLowCodeMno/`
2. Copiar para `arm/SetupLowCodeMno/`
3. Adicionar SHC block em AMBOS os gatilhos
4. Adicionar case statement em AMBOS os install.sh
5. Adicionar ao menu whiptail em AMBOS (x86 e ARM)
6. Atualizar contadores no catálogo `1_codigo_fonte/ferramentas.html`

**Ferramentas conhecidas que NÃO funcionam em ARM (verificar periodicamente):**
- Algumas imagens com binários compilados estaticamente para x86
- Ferramentas com dependências de bibliotecas nativas x86 específicas
