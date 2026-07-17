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
2. **`start_full.sh` (e ARM):** Validação de API e descompactação seletiva por plano.
3. **`install.sh`:** O cérebro. Valida ambiente Docker/Swarm, chama `dockerswarm.sh` se necessário, e abre o menu de aplicações.
4. **Scripts de Deploy:** Scripts individuais (ex: `n8n.sh`) chamados pelo `install.sh`.

## CONTROLE DE VERSÃO (GIT)
O projeto utiliza Git para rastrear todas as alterações. Regras obrigatórias:

### Histórico e Reversão
- **Cada alteração** (combo, ferramenta, correção) deve ser commitada com mensagem descritiva.
- **Reversão:** `git checkout <hash> -- <arquivo>` para voltar um arquivo, ou `git checkout <hash>` para estado completo.
- **Diferença:** `git diff <hash1> <hash2>` para comparar versões.

### Versionamento
- Versão definida na variável `VERSIONSETUP` no topo do `install.sh` (x86 e ARM), no topo do `setup-mno.sh`, no topo do `start_full.sh` e no topo do `start_arm_full.sh`.
- Formato: `MAJOR.MINOR.PATCH` (ex: `4.20.2`)
- **MAJOR:** Mudança arquitetural (ex: novo menu, novo fluxo de licenciamento)
- **MINOR:** Nova ferramenta ou combo adicionado
- **PATCH:** Correção de bug, melhoria de performance, ajuste de layout

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

## REGRA PARA ADIÇÃO DE NOVAS FERRAMENTAS
Ao adicionar uma ferramenta (CRM, IA, etc):
1. **Criação:** Crie o script `ferramenta.sh` em ambos os diretórios de arquitetura.
2. **Gestão de Planos:** Pergunte sempre se é Pro ou Free. Se houver variantes (Free1, Free2), a lógica de deleção/manutenção no `start_full` e a opção no menu do `install.sh` devem ser espelhadas.
3. **Menu:** Atualize o menu `whiptail` no `install.sh` de ambas as arquiteturas.
4. **Espelhamento:** Toda alteração em x86 deve ser replicada em ARM (mesma lógica, tags de imagem diferentes).
5. **Compilação SHC (OBRIGATÓRIO):** Adicione o bloco de compilação SHC em AMBOS os gatilhos (`start_full.sh` x86 e `start_arm_full.sh` ARM). Sem isso, o script não será compilado no runtime do cliente e o menu falhará. Formato do bloco:
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
    - [ ] Pergunta Portainer adicionada
    - [ ] Variáveis Cloudflare verificadas antes de usar
    - [ ] `nome_servidor` com fallback para IP
    - [ ] **Sufixo único** gerado (`$nome_app`) e usado em tudo (yaml, stack, volumes, banco)
    - [ ] **Tunnel via API** (não `systemctl restart cloudflared`)
    - [ ] **Labels Traefik condicionais** (APENAS quando `INSTALL_TYPE = "TRADICIONAL"`)
    - [ ] **`cd` + `cd` antes de criar YAML** (garante salvamento em `/root/`)
    - [ ] **NÃO deletar o YAML após deploy** (`rm -f $nome_app.yaml` — o arquivo DEVE permanecer em `/root/`)
    - [ ] Deploy com tratamento de erro em cada etapa
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

### Passos Obrigatórios pós-Migraçãols
Após criar o script da ferramenta em ambas as arquiteturas:
1. **Menu:** Atualize o menu `whiptail` no `install.sh` (x86 e ARM) — adicionar opção + case statement.
2. **SHC:** Adicione o bloco de compilação em `start_full.sh` (x86) e `start_arm_full.sh` (ARM).
3. **Versão:** Incremente o MINOR da versão nos 2 arquivos `install.sh` (x86 e ARM), no arquivo `setup-mno.sh`, no arquivo `start_full.sh` e no arquivo `start_arm_full.sh` — ex: `4.22.0` → `4.23.0`.
4. **Empacotamento:** Rode `./2_empacotador/gerar_distribuicao.sh`.
5. **Git:** Faça commit das alterações com mensagem descritiva (ex: `feat: adicionar Keycloak (IAM/SSO)`).

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
- Chatwoot, Evolution API, N8N, Typebot, Flowise, Dify AI, Supabase

**Ferramentas de Suporte** (migrar conforme demanda):
- PgAdmin, Adminer, Uptime Kuma, Grafana, Metabase, RedisInsight

**Ferramentas Específicas** (migrar apenas se houver demanda):
- Frappe/ERPNext, Odoo, Moodle, AzuraCast, Traccar, etc.

### Estado da Migração (referência rápida)
Para consultar o estado atual da migração, peça uma "análise de migração" ao agente — ele lerá o script antigo e o projeto atual, e gerará um relatório atualizado com a classificação de cada ferramenta.

### Scripts de Referência Validados (Migração)
Os seguintes scripts foram validados em produção e devem ser usados como **referência padrão** para novas migrações:

| Script | Uso como referência |
|---|---|
| `activepieces.sh` | Padrão para apps com PostgreSQL + Redis |
| `jitsi.sh` | Padrão para apps com múltiplos containers |
| `keycloak.sh` | Padrão para apps com PostgreSQL + proxy reverso |

Ao migrar novas ferramentas, **copie a estrutura** de um desses scripts como base.

### Aviso: Ferramentas com MySQL
**ATENÇÃO:** Antes de migrar qualquer ferramenta que use MySQL, **PERGUNTE AO USUÁRIO** primeiro. Existem peculiaridades na migração que variam caso a caso (versão do MySQL, collation, charset, configurações de engine). Não assuma que o padrão PostgreSQL se aplica.