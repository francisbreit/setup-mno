# Roadmap — Segurança do Servidor no Setup MNO

## Objetivo

Oferecer proteção progressiva para usuários com pouca experiência em infraestrutura, sem bloquear o acesso SSH, quebrar Docker/Swarm, interferir no WSL2 ou depender de uma provedora específica.

Princípio central: **diagnosticar primeiro, explicar o risco e só alterar o servidor em uma etapa futura, transacional e confirmada pelo usuário**.

## Compatibilidade obrigatória

- Ubuntu e Debian em VPS, incluindo AWS, DigitalOcean, Oracle Cloud, Hostinger e Hetzner.
- Windows 10/11 com WSL2 e Docker Desktop.
- Instalações antigas e atuais do Setup MNO.
- Acesso tradicional por SSH, console web da provedora e acesso remoto pelo Setup MNO Control Center.
- Docker Swarm, Traefik e Cloudflare Tunnel sem alteração de portas, rotas ou redes durante a auditoria.

## P0 — Diagnóstico de segurança do servidor (v7.15.0)

Status: **implementado em modo somente leitura**.

Entrada disponível imediatamente antes de `SAIR` em todos os menus e planos:

`DIAGNÓSTICO DE SEGURANÇA DO SERVIDOR`

O diagnóstico coleta e apresenta:

- identificação de WSL2, Linux/VPS, virtualização e indícios locais da provedora;
- versão do sistema, kernel e OpenSSH Server;
- validação da configuração do OpenSSH com `sshd -t`;
- configuração efetiva com `sshd -T`, incluindo portas, autenticação por senha, login de root, chaves públicas, autenticação interativa, senhas vazias, limites de tentativas e encaminhamentos;
- quantidade de entradas em `authorized_keys`, sem ler ou exibir o conteúdo das chaves;
- integrantes adicionais dos grupos `sudo` ou `wheel`;
- estado observável de `ssh.service`, `ssh.socket`, UFW, firewalld, nftables e Fail2ban;
- quantidade de falhas de autenticação SSH observáveis nas últimas 24 horas;
- índice local, severidade dos achados e checklist recomendado em linguagem acessível.

Limites declarados na interface:

- não é pentest, certificação nem prova de exposição pública;
- Security Groups, NSG, Security Lists e firewalls das provedoras não podem ser confirmados somente de dentro da máquina;
- no WSL2, a exposição também depende do Windows Defender Firewall, Hyper-V, NAT ou modo de rede espelhada;
- a porta 22 é tratada como redução de ruído operacional, não como mecanismo principal de segurança.

Garantias do P0:

- não escreve arquivos;
- não altera porta, usuário, senha, chave, firewall ou política;
- não reinicia nem recarrega SSH;
- não modifica Docker, Swarm, Traefik, Cloudflare ou recursos da provedora;
- o botão `VOLTAR` já recebe o foco e aceita `Enter` diretamente.

## P1 — Correção SSH assistida e transacional

Status: **planejado; não implementar sem autorização explícita**.

Fluxo seguro proposto:

1. confirmar que existe um usuário administrativo não-root;
2. confirmar uma chave pública válida sem exibir sua parte privada;
3. criar backup versionado da configuração;
4. gerar um snippet isolado em `sshd_config.d` quando suportado;
5. validar a configuração candidata com `sshd -t`;
6. manter a sessão atual aberta e iniciar um teste real em uma segunda conexão;
7. somente após confirmação do usuário, recarregar o serviço correto;
8. iniciar uma janela de rollback automático;
9. cancelar o rollback apenas depois que o novo acesso for confirmado.

Controles candidatos, oferecidos separadamente:

- criação de usuário sudo;
- autenticação por chave;
- desativação de senha somente depois do teste da chave;
- restrição de login direto do root;
- ajuste de `MaxAuthTries` e `LoginGraceTime`;
- mudança opcional da porta SSH;
- Fail2ban com política conservadora.

Regras anti-lockout:

- nunca desativar senha sem chave testada;
- nunca bloquear root sem usuário sudo testado;
- nunca trocar porta sem validar firewall local e instruir sobre o firewall da provedora;
- preservar console de emergência da provedora;
- rollback automático obrigatório se a confirmação expirar.

## P2 — Perfil SSH protegido por Cloudflare

Status: **possibilidade futura**.

- oferecer Cloudflare Tunnel/Access para SSH como perfil adicional, sem substituir compulsoriamente o acesso de emergência;
- preservar o modelo atual de API Cloudflare, múltiplos domínios e túnel principal;
- explicar as diferenças entre acesso pelo navegador, `cloudflared access ssh` e cliente tradicional;
- exigir política Access restritiva e MFA;
- evitar publicar uma rota SSH durante testes locais ou homologação sem autorização específica.

## P3 — Firewall local orientado ao Docker

Status: **planejado**.

- inventariar portas realmente publicadas pelo host e pelo Swarm;
- mostrar regras propostas antes de aplicar;
- preservar SSH atual, DNS, Traefik, VXLAN e portas do cluster;
- considerar que portas publicadas pelo Docker podem contornar expectativas comuns do UFW;
- utilizar cadeias compatíveis com Docker, sem apagar regras existentes;
- aplicar alterações individualmente, com validação e rollback.

## P4 — Integrações opcionais com firewalls de provedores

Status: **estrutural e opcional**.

- módulos separados para AWS Security Groups, DigitalOcean Cloud Firewalls, Oracle NSG/Security Lists, Hetzner Cloud Firewall e provedores compatíveis;
- princípio de privilégio mínimo para tokens;
- credenciais somente em Docker Secrets ou mecanismo equivalente protegido;
- modo de visualização antes de qualquer escrita;
- nenhuma dependência dessas APIs para o diagnóstico local funcionar.

## Perfis de experiência futura

- **Somente diagnóstico:** padrão universal e sem risco de lockout.
- **Recomendado para VPS:** usuário sudo, chave testada, senha desativada, root restrito, firewall e proteção contra força bruta.
- **Cloudflare protegido:** controles do perfil VPS mais Cloudflare Access para o caminho remoto principal.
- **WSL2 local:** orientações específicas para Windows e Docker Desktop, sem sugerir mudanças de SSH quando o serviço não for necessário.

## Gates de homologação futuros

- Debian e Ubuntu com `ssh.service` e com `ssh.socket`;
- VPS com porta 22 e porta personalizada;
- acesso por senha, chave, root e usuário sudo;
- UFW, firewalld, nftables e firewall externo não detectável;
- WSL2 com e sem systemd/OpenSSH;
- simulação de configuração SSH inválida;
- interrupção durante cada etapa e confirmação do rollback;
- verificação de que nenhum segredo, chave ou senha aparece em tela ou log;
- confirmação de que Docker/Swarm e o Control Center permanecem funcionais.

## Referências oficiais para o projeto

- Ubuntu OpenSSH: https://documentation.ubuntu.com/server/how-to/security/openssh-server/
- Debian SSH: https://www.debian.org/doc/manuals/securing-debian-manual/ssh.en.html
- Microsoft WSL networking: https://learn.microsoft.com/windows/wsl/networking
- Docker e UFW: https://docs.docker.com/engine/network/packet-filtering-firewalls/#docker-and-ufw
- Cloudflare SSH: https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/use-cases/ssh/

