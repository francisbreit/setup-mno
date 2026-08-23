# Baseline seguro para Debian e Ubuntu

- Estado: `implemented`
- Atualizado em: 2026-08-23
- Público: mantenedor PRO MASTER e autores do futuro Help
- Ambientes: Debian e Ubuntu em VPS

## Resumo para leigos

Antes de “consertar” um servidor, registre o que ele é e quanto recurso ainda
possui. Uma atualização de pacotes não corrige falta de disco, perda de quorum
ou repositório externo quebrado. Também não deve ser o primeiro reflexo durante
um incidente.

## Objetivo

Criar uma fotografia somente leitura do host e separar manutenção planejada de
resposta emergencial.

## O que observar

Comandos abaixo apenas consultam o estado:

```bash
cat /etc/os-release
uname -m
uname -r
date --iso-8601=seconds
uptime
free -h
df -hT
df -ih
systemctl is-system-running
docker version
docker info --format '{{json .}}'
```

Registre somente os campos necessários. O resultado completo de `docker info`
pode conter nomes e endereços internos e deve ser sanitizado antes de ser
compartilhado.

## Manutenção planejada

1. Confirme backup e capacidade real de restauração.
2. Verifique espaço em disco e inodes.
3. Liste repositórios oficiais e de terceiros.
4. Leia a documentação da versão e mudanças incompatíveis.
5. Planeje janela, critérios de sucesso e rollback.
6. Atualize primeiro um ambiente de homologação comparável.
7. Só então aplique a manutenção no host autorizado.

Repositórios de terceiros são uma fonte frequente de falhas no `apt`. O erro deve
ser tratado no repositório específico, sem desabilitar verificação de assinatura
globalmente e sem transformar uma chave ilegível em fonte “confiável”.

## Árvore de diagnóstico

- **Disco ou inode acima do limite:** estabilize gravações e identifique o
  consumidor; não limpe volumes Docker às cegas.
- **Memória esgotada:** identifique processos e tarefas reiniciando; aumentar
  swap não resolve vazamento nem limite incorreto.
- **`apt` falha em um repositório externo:** preserve o erro, confira arquivo de
  origem, keyring, permissões e documentação do fornecedor.
- **Docker indisponível:** diferencie serviço parado, daemon travado, socket sem
  permissão e armazenamento cheio.
- **Host em versão sem suporte:** planeje migração ou upgrade com backup; não
  faça salto de release durante incidente ativo.

## Limites e segurança

- Não execute `apt upgrade`, reinício, limpeza ou alteração de repositório como
  simples diagnóstico.
- Nunca contorne `apt-secure` com repositório não assinado.
- Não use `docker system prune`, remoção de volumes ou limpeza recursiva como
  “otimização”.
- Uma IA pode explicar evidências; não deve receber `sudo`, root ou shell.

## Fontes oficiais

- [Debian Securing Manual](https://www.debian.org/doc/manuals/securing-debian-manual/)
- [Ubuntu security updates](https://documentation.ubuntu.com/security/security-updates/)
- [Ubuntu Server release upgrade](https://documentation.ubuntu.com/server/how-to/software/upgrade-your-release/index.html)
- [Docker Engine installation overview](https://docs.docker.com/engine/install/)

## Publicação futura no Help

Criar um checklist visual “meu servidor está pronto?” com indicadores de disco,
memória, versão e Docker. A tela deve explicar cada item sem oferecer um botão
genérico de correção automática.
