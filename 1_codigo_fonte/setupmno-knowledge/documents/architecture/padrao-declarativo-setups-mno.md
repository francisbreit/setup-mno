# Padrão Arquitetural Canônico para Setups e Combos no Setup MNO

## 1. Visão Geral e Propósito

Este documento estabelece o **Padrão Canônico de Infraestrutura como Código (IaC)** para a criação, homologação e manutenção de aplicações e combos no Setup MNO.

O objetivo deste padrão é garantir que:
1. Todo setup funcione imediatamente no primeiro carregamento no navegador (**zero dor de cabeça e zero 502**), tanto em servidores locais com Traefik quanto em servidores protegidos por **Cloudflare Tunnel**.
2. O arquivo de manifesto Docker Swarm (`$nome_app.yaml`) seja **100% declarativo e auto-contido**, permitindo que o **Fleet Hub** (`fleet-clone.sh`) descubra o domínio, a porta interna e o serviço responsável sem depender de adivinhações.
3. Migrações, clones e backups ocorram com comutação atômica de DNS e rotas de Ingress na Cloudflare sem downtime e sem requisições manuais.

---

## 2. O Padrão Canônico de Labels Traefik (Dual-Mode)

Historicamente, o modo `CLOUDFLARE_TUNNEL` omitia as labels Traefik do arquivo YAML. A partir da versão `v7.48.16`, **todos os setups devem injetar as labels no YAML independentemente do modo de instalação**, utilizando o controle de ativação `traefik.enable`:

```bash
cat >> $nome_app.yaml << EOL
      labels:
        - traefik.enable=$([ "$INSTALL_TYPE" = "TRADICIONAL" ] && echo "1" || echo "0")
        - traefik.http.routers.${nome_app}.rule=Host(\`$dominio\`)
        - traefik.http.routers.${nome_app}.service=${nome_app}
        - traefik.http.services.${nome_app}.loadbalancer.server.port=$porta
        - traefik.http.services.${nome_app}.loadbalancer.passHostHeader=1
EOL

if [ "$INSTALL_TYPE" = "TRADICIONAL" ]; then
cat >> $nome_app.yaml << EOL
        - traefik.http.routers.${nome_app}.entrypoints=websecure
        - traefik.http.routers.${nome_app}.priority=1
        - traefik.http.routers.${nome_app}.tls.certresolver=letsencryptresolver
EOL
fi
```

### Por que esse formato é obrigatório?
- Se `INSTALL_TYPE == "TRADICIONAL"`: O Traefik assume a porta 443, emite o certificado Let's Encrypt e roteia a requisição.
- Se `INSTALL_TYPE == "CLOUDFLARE_TUNNEL"`: O `traefik.enable=0` instrui o Traefik a ignorar a stack. Porém, o `fleet-clone.sh` lê a regra `Host(\`...\`)` e a porta `server.port`, sabendo exatamente como configurar a regra de Ingress e o CNAME na Cloudflare!

---

## 3. O Padrão de Variáveis de Ambiente no YAML

Todo container com interface web ou API externa deve declarar no seu bloco `environment:` a variável padronizada de domínio:

```yaml
    environment:
      - WEB_DOMAIN=$dominio
      - APP_URL=https://$dominio # (ou a variável nativa que a aplicação consome)
```

Para aplicações utilitárias ou de fila (ex: RabbitMQ):
```yaml
    environment:
      - RABBITMQ_MANAGEMENT_URL=https://$painel
      - RABBITMQ_MANAGEMENT_HOST=$painel
```

---

## 4. Registro no Gravador Universal de Manifestos (`mno-manifest-writer.sh`)

Ao final da instalação da stack ou do combo, o script deve obrigatoriamente chamar o gravador de manifestos informando os domínios utilizados:

```bash
/root/SetupLowCodeMno/mno-manifest-writer.sh \
    "$nome_principal" \
    "$nome_app" \
    "$combo_id" \
    "$combo_name" \
    "$db_engine" \
    "$db_name" \
    "$s3_bucket" \
    "$rabbitmq_vhost" \
    "$lista_dominios" \
    "$lista_volumes"
```

Onde `$lista_dominios` é uma string com os domínios separados por vírgula (ex: `atendi.dominio.com,fila.dominio.com`).

---

## 5. Regras para Combos Multi-Stack

Em combos onde várias stacks são orquestradas em conjunto (ex: Chatwoot + Evolution + RabbitMQ + MinIO):
1. Cada stack que possui painel ou interface web (`chatwoot`, `evolution`, `minio`, `rabbitmq`) deve possuir seu próprio arquivo YAML com seu respectivo `Host(\`...\`)` e porta declarados.
2. Stacks puramente de suporte interno (ex: `${nome_app}-redis`, `${nome_app}_db`, `${nome_app}_worker`, `${nome_app}-mq`) devem ser nomeadas com sufixos identificadores (`-redis`, `-worker`, `-mq`, `database`) e **não devem possuir router Traefik**, para que o Fleet Hub as trate automaticamente como stacks de background, sem tentar comutar rotas web inexistentes.

---

## 6. Checklist de Homologação de Novos Setups

Antes de enviar qualquer nova ferramenta para `1_codigo_fonte/`:
1. **Verificação de Portas:** Executar `./2_empacotador/verificar_portas.sh <porta>` para garantir que a porta interna escolhida não colida.
2. **Registro de Porta:** Adicionar a porta padrão da nova aplicação no `case "$app_norm"` dentro da função `resolve_host_service_port` em `fleet-clone.sh`.
3. **Paridade x86/ARM:** Garantir que o script exista e seja idêntico em `1_codigo_fonte/x86/SetupLowCodeMno/` e `1_codigo_fonte/arm/SetupLowCodeMno/`.
4. **Gates de Release:** Executar `generate-installers.sh`, testes de certificação e `./2_empacotador/gerar_distribuicao.sh`.
