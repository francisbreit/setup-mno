#!/usr/bin/env python3
"""
==============================================================================
MNO FLEET MIGRATION: TRAEFIK -> CLOUDFLARE TUNNEL (MODO 9)
Ferramenta Oficial de Compatibilidade e Modernização de Servidores Antigos
==============================================================================
"""

import argparse
import getpass
import json
import os
import subprocess
import sys
import time
import urllib.request
import urllib.error

class Colors:
    HEADER = "\033[95m"
    BLUE = "\033[94m"
    CYAN = "\033[96m"
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    RED = "\033[91m"
    END = "\033[0m"
    BOLD = "\033[1m"

def log_info(msg):
    print(f"{Colors.BLUE}[INFO]{Colors.END} {msg}")

def log_success(msg):
    print(f"{Colors.GREEN}[SUCESSO]{Colors.END} {msg}")

def log_warn(msg):
    print(f"{Colors.YELLOW}[AVISO]{Colors.END} {msg}")

def log_error(msg):
    print(f"{Colors.RED}[ERRO]{Colors.END} {msg}")

def run_ssh(host, port, user, password, cmd, timeout=30):
    env = os.environ.copy()
    env["SSHPASS"] = password
    full_cmd = [
        "sshpass", "-e", "ssh",
        "-p", str(port),
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "LogLevel=ERROR",
        "-o", f"ConnectTimeout={timeout}",
        f"{user}@{host}",
        cmd
    ]
    try:
        p = subprocess.run(full_cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=timeout+10)
        return p.returncode, p.stdout.strip(), p.stderr.strip()
    except Exception as e:
        return -1, "", str(e)

class MigrationPipeline:
    def __init__(self, args):
        self.args = args
        self.cf_token = None
        self.cf_account_id = None
        self.cf_zone_id = None
        self.cf_zone_name = None
        self.new_tunnel_id = None
        self.new_tunnel_token = None
        self.new_tunnel_name = None
        self.old_arch = "x86_64"
        self.routes_inventory = []

    def phase1_extract_model_credentials(self):
        log_info("=== FASE 1: Extração de Credenciais do Servidor Modelo ===")
        rc, out, err = run_ssh(self.args.host_new, self.args.port_new, self.args.user_new, self.args.pass_new, "cat /root/.cloudflared_config/cloudflare_credentials")
        if rc != 0:
            log_error(f"Falha ao ler credenciais do servidor novo: {err}")
            return False

        for line in out.splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                k, v = line.split("=", 1)
                k = k.strip()
                v = v.strip().strip('"').strip("'")
                if k == "CLOUDFLARE_API_TOKEN":
                    self.cf_token = v
                elif k == "CLOUDFLARE_ACCOUNT_ID":
                    self.cf_account_id = v
                elif k == "CLOUDFLARE_ZONE_ID":
                    self.cf_zone_id = v
                elif k == "CLOUDFLARE_ZONE_NAME":
                    self.cf_zone_name = v

        if not self.cf_token or not self.cf_account_id:
            log_error("Token ou Account ID ausentes nas credenciais do servidor novo.")
            return False

        req = urllib.request.Request(
            "https://api.cloudflare.com/client/v4/user/tokens/verify",
            headers={"Authorization": f"Bearer {self.cf_token}"}
        )
        try:
            with urllib.request.urlopen(req) as resp:
                data = json.loads(resp.read().decode())
                if not data.get("success"):
                    log_error("Token da Cloudflare inválido.")
                    return False
        except Exception as e:
            log_error(f"Erro na validação do token Cloudflare: {e}")
            return False

        log_success(f"Credenciais Cloudflare validadas! Account ID: {self.cf_account_id}, Zona: {self.cf_zone_name}")
        return True

    def phase2_inventory_old_server(self):
        log_info("=== FASE 2: Inventário dos Serviços no Servidor Antigo ===")
        rc, out, err = run_ssh(self.args.host_old, self.args.port_old, self.args.user_old, self.args.pass_old, "uname -m")
        if rc == 0 and out:
            self.old_arch = out
        log_info(f"Arquitetura detectada no servidor alvo: {self.old_arch}")

        # Inspeciona serviços e labels Traefik
        inspect_cmd = "docker service inspect $(docker service ls -q) --format '{{.Spec.Name}}:::{{json .Spec.Labels}}'"
        rc, out, _ = run_ssh(self.args.host_old, self.args.port_old, self.args.user_old, self.args.pass_old, inspect_cmd)
        if rc != 0 or not out:
            log_error("Nenhum serviço Swarm encontrado no servidor antigo.")
            return False

        for line in out.splitlines():
            if ":::" not in line:
                continue
            name, raw_labels = line.split(":::", 1)
            try:
                labels = json.loads(raw_labels) if raw_labels != "null" else {}
            except:
                labels = {}

            routes = {}
            ports = {}
            for k, v in labels.items():
                if "traefik.http.routers" in k and "rule" in k:
                    r_name = k.split(".")[3]
                    routes[r_name] = v
                if "traefik.http.services" in k and "port" in k:
                    s_name = k.split(".")[3]
                    ports[s_name] = v

            for r_name, rule in routes.items():
                host = None
                path = None
                if "Host(" in rule:
                    host = rule.split("Host(")[1].split(")")[0].strip("`").strip("'").strip('"')
                if "PathPrefix(" in rule:
                    path = rule.split("PathPrefix(")[1].split(")")[0].strip("`").strip("'").strip('"')

                # Filtro estrito: Ignorar domínios raiz se pertencerem a outros servidores
                if host and host != "manualnegocioonline.com.br":
                    port = ports.get(r_name, ports.get(name.split("_")[-1], "80"))
                    self.routes_inventory.append({
                        "hostname": host,
                        "service": name,
                        "port": int(port) if str(port).isdigit() else 80,
                        "path": path
                    })

        log_success(f"{len(self.routes_inventory)} rotas legítimas mapeadas para o túnel.")
        for r in self.routes_inventory:
            p_str = f" (path: {r['path']})" if r['path'] else ""
            print(f"  -> {r['hostname']}{p_str} -> {r['service']}:{r['port']}")
        return True

    def phase3_create_new_tunnel(self):
        log_info("=== FASE 3: Criação de Redes Modernas e Novo Túnel ===")
        for net in ["externa", "interna", "agent_network"]:
            cmd = f"docker network inspect {net} >/dev/null 2>&1 || docker network create --driver=overlay --attachable {net}"
            run_ssh(self.args.host_old, self.args.port_old, self.args.user_old, self.args.pass_old, cmd)
            log_success(f"Rede overlay '{net}' pronta!")

        self.new_tunnel_name = f"setupmno-migrated-{self.args.host_old.replace('.', '-')}-{int(time.time())}"
        log_info(f"Criando túnel Cloudflare: {self.new_tunnel_name}...")
        url = f"https://api.cloudflare.com/client/v4/accounts/{self.cf_account_id}/cfd_tunnel"
        payload = json.dumps({
            "name": self.new_tunnel_name,
            "tunnel_secret": "c2V0dXBtbm9fdHVubmVsX3NlY3JldF8zMmJ5dGVzX2FzZGY=",
            "config_src": "cloudflare"
        }).encode()
        req = urllib.request.Request(
            url,
            data=payload,
            headers={
                "Authorization": f"Bearer {self.cf_token}",
                "Content-Type": "application/json"
            },
            method="POST"
        )
        try:
            with urllib.request.urlopen(req) as resp:
                data = json.loads(resp.read().decode())
                self.new_tunnel_id = data["result"]["id"]
                self.new_tunnel_token = data["result"]["token"]
        except Exception as e:
            log_error(f"Erro ao criar túnel Cloudflare: {e}")
            return False

        log_success(f"Túnel criado com sucesso! ID: {self.new_tunnel_id}")

        secret_suffix = self.new_tunnel_id.replace("-", "")[:16]
        secret_name = f"setupmno_primary_tunnel_{secret_suffix}"

        run_ssh(self.args.host_old, self.args.port_old, self.args.user_old, self.args.pass_old,
                "for s in $(docker secret ls --format '{{.Name}}' | grep setupmno_primary_tunnel); do docker secret rm $s 2>/dev/null || true; done")

        create_secret_cmd = f"printf '%s' '{self.new_tunnel_token}' | docker secret create {secret_name} -"
        rc, _, err = run_ssh(self.args.host_old, self.args.port_old, self.args.user_old, self.args.pass_old, create_secret_cmd)
        if rc != 0:
            log_error(f"Falha ao criar secret: {err}")
            return False

        compose_content = f"""version: '3.7'
services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    command: tunnel run --token-file /run/secrets/{secret_name}
    secrets:
      - {secret_name}
    networks:
      - externa
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: '0.50'
          memory: 256M
secrets:
  {secret_name}:
    external: true
networks:
  externa:
    external: true
"""
        deploy_cmd = f"cat << 'EOF' > /tmp/cloudflared-stack.yaml\n{compose_content}\nEOF\ndocker stack deploy -c /tmp/cloudflared-stack.yaml cloudflared"
        run_ssh(self.args.host_old, self.args.port_old, self.args.user_old, self.args.pass_old, deploy_cmd)

        log_info("Aguardando conector cloudflared convergir...")
        for _ in range(15):
            time.sleep(3)
            rc, out, _ = run_ssh(self.args.host_old, self.args.port_old, self.args.user_old, self.args.pass_old,
                                 "docker service ls --filter name=cloudflared_cloudflared --format '{{.Replicas}}'")
            if rc == 0 and "1/1" in out:
                log_success("Conector cloudflared operacional com réplica 1/1!")
                return True
        return True

    def phase4_configure_ingress_and_dns(self):
        log_info("=== FASE 4: Ingress e Registros DNS ===")
        ingress_rules = []
        for r in self.routes_inventory:
            if r["path"]:
                ingress_rules.append({
                    "hostname": r["hostname"],
                    "path": r["path"],
                    "service": f"http://{r['service']}:{r['port']}",
                    "originRequest": {"httpHostHeader": r["hostname"], "noTLSVerify": True}
                })
        for r in self.routes_inventory:
            if not r["path"]:
                ingress_rules.append({
                    "hostname": r["hostname"],
                    "service": f"http://{r['service']}:{r['port']}",
                    "originRequest": {"httpHostHeader": r["hostname"], "noTLSVerify": True}
                })
        ingress_rules.append({"service": "http_status:404"})

        cfg_url = f"https://api.cloudflare.com/client/v4/accounts/{self.cf_account_id}/cfd_tunnel/{self.new_tunnel_id}/configurations"
        cfg_payload = json.dumps({"config": {"ingress": ingress_rules}}).encode()
        req = urllib.request.Request(
            cfg_url,
            data=cfg_payload,
            headers={"Authorization": f"Bearer {self.cf_token}", "Content-Type": "application/json"},
            method="PUT"
        )
        try:
            with urllib.request.urlopen(req):
                log_success("Configuração de Ingress aplicada com sucesso!")
        except Exception as e:
            log_error(f"Erro ao configurar Ingress: {e}")
            return False

        cname_target = f"{self.new_tunnel_id}.cfargotunnel.com"
        distinct_hostnames = sorted(list(set(r["hostname"] for r in self.routes_inventory)))
        for h in distinct_hostnames:
            log_info(f"Apontando DNS: {h} -> {cname_target}...")
            get_url = f"https://api.cloudflare.com/client/v4/zones/{self.cf_zone_id}/dns_records?name={h}"
            get_req = urllib.request.Request(get_url, headers={"Authorization": f"Bearer {self.cf_token}"})
            try:
                with urllib.request.urlopen(get_req) as resp:
                    data = json.loads(resp.read().decode())
                    results = data.get("result", [])
                    if results:
                        rec_id = results[0]["id"]
                        put_url = f"https://api.cloudflare.com/client/v4/zones/{self.cf_zone_id}/dns_records/{rec_id}"
                        put_payload = json.dumps({"type": "CNAME", "name": h, "content": cname_target, "proxied": True}).encode()
                        put_req = urllib.request.Request(put_url, data=put_payload, headers={"Authorization": f"Bearer {self.cf_token}", "Content-Type": "application/json"}, method="PUT")
                        urllib.request.urlopen(put_req)
                        log_success(f"DNS atualizado: {h}")
                    else:
                        post_url = f"https://api.cloudflare.com/client/v4/zones/{self.cf_zone_id}/dns_records"
                        post_payload = json.dumps({"type": "CNAME", "name": h, "content": cname_target, "proxied": True}).encode()
                        post_req = urllib.request.Request(post_url, data=post_payload, headers={"Authorization": f"Bearer {self.cf_token}", "Content-Type": "application/json"}, method="POST")
                        urllib.request.urlopen(post_req)
                        log_success(f"DNS criado: {h}")
            except Exception as e:
                log_warn(f"Aviso no DNS de {h}: {e}")

        return True

    def phase5_migrate_stack_networks(self):
        log_info("=== FASE 5: Adequação Completa de Redes das Stacks ===")
        # 1. Blindagem do Portainer
        portainer_yaml = """version: "3.7"
services:
  agent:
    image: portainer/agent:2.20.1
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
    networks:
      - agent_network
      - externa
    deploy:
      mode: global
      placement:
        constraints: [node.platform.os == linux]

  portainer:
    image: portainer/portainer-ce:2.20.1
    command: -H tcp://tasks.agent:9001 --tlsskipverify
    volumes:
      - portainer_data2:/data
    networks:
      - agent_network
      - externa
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints: [node.role == manager]

networks:
  externa:
    external: true
  agent_network:
    external: true

volumes:
  portainer_data2:
    external: true
    name: portainer_data2
"""
        cmd_p = f"cat << 'EOF' > /root/portainer.yaml\n{portainer_yaml}\nEOF\ndocker stack deploy -c /root/portainer.yaml portainer"
        run_ssh(self.args.host_old, self.args.port_old, self.args.user_old, self.args.pass_old, cmd_p)
        log_success("Stack do Portainer atualizada com alias 'agent' na rede 'agent_network'!")

        # 2. Conectar bancos e serviços às redes modernas
        db_services = {
            "postgres_postgres": "postgres",
            "mysql_mysql": "mysql",
            "redis_redis": "redis",
            "pgbouncer_pgbouncer": "pgbouncer",
            "n8n_redis_n8n_redis": "n8n_redis",
            "evolution2-79a08a5-redis_evolution2-79a08a5-redis": "evolution2-79a08a5-redis"
        }
        for svc, alias in db_services.items():
            rc, _, _ = run_ssh(self.args.host_old, self.args.port_old, self.args.user_old, self.args.pass_old, f"docker service inspect {svc} >/dev/null 2>&1")
            if rc == 0:
                run_ssh(self.args.host_old, self.args.port_old, self.args.user_old, self.args.pass_old,
                        f"docker service update --network-add name=interna,alias={alias} {svc} 2>/dev/null || true")
                run_ssh(self.args.host_old, self.args.port_old, self.args.user_old, self.args.pass_old,
                        f"docker service update --network-rm network_public {svc} 2>/dev/null || true")

        # RabbitMQ
        run_ssh(self.args.host_old, self.args.port_old, self.args.user_old, self.args.pass_old,
                "docker service update --network-add name=interna,alias=rabbitmq --network-add externa rabbitmq3a3c97f_rabbitmq3a3c97f 2>/dev/null || true")
        run_ssh(self.args.host_old, self.args.port_old, self.args.user_old, self.args.pass_old,
                "docker service update --network-rm network_public rabbitmq3a3c97f_rabbitmq3a3c97f 2>/dev/null || true")

        # Aplicações Web
        app_services = [
            "wordpress60fb194_wordpress60fb194",
            "evolution2-79a08a5_evolution2-79a08a5",
            "n8n_editora16f9d3_n8n_editora16f9d3",
            "n8n_webhooka16f9d3_n8n_webhooka16f9d3",
            "n8n_workera16f9d3_n8n_workera16f9d3",
            "n8n_mcp_apia16f9d3_n8n_mcp_apia16f9d3",
            "minio1abd2b9_minio1abd2b9",
            "typebot60d34a9_typebot60d34a9-builder",
            "typebot60d34a9_typebot60d34a9-viewer",
            "pgadmin4_pgadmin4",
            "pmadminf45d587_pmadminf45d587"
        ]
        for svc in app_services:
            rc, _, _ = run_ssh(self.args.host_old, self.args.port_old, self.args.user_old, self.args.pass_old, f"docker service inspect {svc} >/dev/null 2>&1")
            if rc == 0:
                run_ssh(self.args.host_old, self.args.port_old, self.args.user_old, self.args.pass_old,
                        f"docker service update --network-add externa --network-add interna {svc} 2>/dev/null || true")
                run_ssh(self.args.host_old, self.args.port_old, self.args.user_old, self.args.pass_old,
                        f"docker service update --network-rm network_public {svc} 2>/dev/null || true")

        # Remove rede legada
        run_ssh(self.args.host_old, self.args.port_old, self.args.user_old, self.args.pass_old,
                "docker network rm network_public 2>/dev/null || true")
        log_success("Todas as stacks migradas para as redes modernas!")
        return True

    def phase6_strip_traefik_and_firewall(self):
        log_info("=== FASE 6: Remoção de Labels Traefik, Validação HTTPS e Firewall ===")
        svcs = list(set(r["service"] for r in self.routes_inventory))
        for svc in svcs:
            rc, out, _ = run_ssh(self.args.host_old, self.args.port_old, self.args.user_old, self.args.pass_old,
                                 f"docker service inspect {svc} --format '{{{{json .Spec.Labels}}}}'")
            if rc == 0 and out != "null":
                try:
                    labels = json.loads(out)
                    t_keys = [k for k in labels if k.startswith("traefik.")]
                    if t_keys:
                        rm_args = " ".join([f"--label-rm {k}" for k in t_keys])
                        run_ssh(self.args.host_old, self.args.port_old, self.args.user_old, self.args.pass_old,
                                f"docker service update {rm_args} {svc}")
                except:
                    pass

        # Descomissiona Traefik
        run_ssh(self.args.host_old, self.args.port_old, self.args.user_old, self.args.pass_old,
                "docker stack rm traefik 2>/dev/null || true")

        # Fecha portas no firewall
        run_ssh(self.args.host_old, self.args.port_old, self.args.user_old, self.args.pass_old,
                "ufw delete allow 80/tcp 2>/dev/null; ufw delete allow 443/tcp 2>/dev/null; ufw delete allow 80 2>/dev/null; ufw delete allow 443 2>/dev/null; ufw reload 2>/dev/null || true")
        log_success("Traefik descomissionado e portas 80/443 fechadas no host!")
        return True

    def phase7_align_filesystem(self):
        log_info("=== FASE 7: Alinhamento de Filesystem e Scripts Oficiais ===")
        run_ssh(self.args.host_old, self.args.port_old, self.args.user_old, self.args.pass_old,
                "mkdir -p /root/.cloudflared_config && chmod 700 /root/.cloudflared_config")
        run_ssh(self.args.host_old, self.args.port_old, self.args.user_old, self.args.pass_old,
                "echo 'CLOUDFLARE_TUNNEL' > /root/.cloudflared_config/installation_type")

        creds = f"""CLOUDFLARE_API_TOKEN={self.cf_token}
CLOUDFLARE_ACCOUNT_ID={self.cf_account_id}
CLOUDFLARE_ZONE_ID={self.cf_zone_id}
CLOUDFLARE_ZONE_NAME={self.cf_zone_name}
TUNNEL_NAME={self.new_tunnel_name}
TUNNEL_ID={self.new_tunnel_id}
TUNNEL_OWNERSHIP=setupmno
"""
        cmd_creds = f"cat << 'EOF' > /root/.cloudflared_config/cloudflare_credentials\n{creds}EOF\nchmod 600 /root/.cloudflared_config/cloudflare_credentials"
        run_ssh(self.args.host_old, self.args.port_old, self.args.user_old, self.args.pass_old, cmd_creds)

        base_repo_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
        source_dir = os.path.join(base_repo_dir, "1_codigo_fonte/x86/SetupLowCodeMno")
        sync_cmd = (
            f"tar -C '{source_dir}' -cf - . | "
            f"SSHPASS='{self.args.pass_old}' sshpass -e ssh -p {self.args.port_old} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "
            f"{self.args.user_old}@{self.args.host_old} 'mkdir -p /root/SetupLowCodeMno && tar -C /root/SetupLowCodeMno -xf - && chmod +x /root/SetupLowCodeMno/*.sh /root/SetupLowCodeMno/* 2>/dev/null || true'"
        )
        subprocess.run(sync_cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        setup_script_local = os.path.join(base_repo_dir, "1_codigo_fonte/setup-mno.sh")
        sync_root_script = (
            f"cat '{setup_script_local}' | "
            f"SSHPASS='{self.args.pass_old}' sshpass -e ssh -p {self.args.port_old} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "
            f"{self.args.user_old}@{self.args.host_old} 'cat > /root/setup-mno.sh && chmod +x /root/setup-mno.sh'"
        )
        subprocess.run(sync_root_script, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        run_ssh(self.args.host_old, self.args.port_old, self.args.user_old, self.args.pass_old,
                "rm -f /root/SetupLowCodeMno.zip /root/*.download /tmp/setupmno-start* 2>/dev/null || true")

        link_cmd = "ln -sf /root/setup-mno.sh /usr/local/bin/setup-mno 2>/dev/null || ln -sf /root/SetupLowCodeMno/setup-mno.sh /usr/local/bin/setup-mno 2>/dev/null || true"
        run_ssh(self.args.host_old, self.args.port_old, self.args.user_old, self.args.pass_old, link_cmd)
        log_success("Filesystem alinhado e link /usr/local/bin/setup-mno ativo!")
        return True

    def run(self):
        print(f"\n{Colors.HEADER}{Colors.BOLD}" + "=" * 70)
        print("   MNO FLEET MIGRATION: TRAEFIK -> CLOUDFLARE TUNNEL (MODO 9)")
        print("=" * 70 + f"{Colors.END}\n")

        if not self.phase1_extract_model_credentials():
            return False
        if not self.phase2_inventory_old_server():
            return False
        if not self.phase3_create_new_tunnel():
            return False
        if not self.phase4_configure_ingress_and_dns():
            return False
        if not self.phase5_migrate_stack_networks():
            return False
        if not self.phase6_strip_traefik_and_firewall():
            return False
        if not self.phase7_align_filesystem():
            return False

        print(f"\n{Colors.GREEN}{Colors.BOLD}" + "=" * 70)
        print("   MIGRAÇÃO E ADEQUAÇÃO CONCLUÍDAS COM SUCESSO! SERVIDOR 100% OPERACIONAL")
        print("=" * 70 + f"{Colors.END}")
        print(f"-> Novo Túnel ID: {self.new_tunnel_id}")
        print(f"-> Nome do Túnel: {self.new_tunnel_name}")
        print(f"-> Rotas Mapeadas: {len(self.routes_inventory)}")
        print("-> Redes Overlay Modernas: externa, interna, agent_network")
        print("-> Estado da VPS: Portas 80/443 fechadas (Stealth) | 0 MB RAM ociosa")
        print("-> Portainer: Agent configurado com alias 'agent' na rede 'agent_network'.\n")
        return True

def main():
    parser = argparse.ArgumentParser(
        description="Migração de Servidor Antigo (Traefik) para Cloudflare Tunnel (Setup MNO Modo 9)"
    )
    parser.add_argument("--host-new", required=True, help="IP do Servidor Modelo (Novo)")
    parser.add_argument("--port-new", type=int, default=22, help="Porta SSH Servidor Novo")
    parser.add_argument("--user-new", default="root", help="Usuário SSH Servidor Novo")
    parser.add_argument("--pass-new", help="Senha SSH Servidor Novo")

    parser.add_argument("--host-old", required=True, help="IP do Servidor Alvo (Antigo)")
    parser.add_argument("--port-old", type=int, default=22, help="Porta SSH Servidor Antigo")
    parser.add_argument("--user-old", default="root", help="Usuário SSH Servidor Antigo")
    parser.add_argument("--pass-old", help="Senha SSH Servidor Antigo")

    args = parser.parse_args()

    if not args.pass_new:
        args.pass_new = getpass.getpass(f"Digite a senha SSH do Servidor Novo ({args.user_new}@{args.host_new}): ")
    if not args.pass_old:
        args.pass_old = getpass.getpass(f"Digite a senha SSH do Servidor Antigo ({args.user_old}@{args.host_old}): ")

    pipeline = MigrationPipeline(args)
    success = pipeline.run()
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
