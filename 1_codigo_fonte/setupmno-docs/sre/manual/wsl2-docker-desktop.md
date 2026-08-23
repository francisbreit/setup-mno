# WSL2 e Docker Desktop sem reinstalações indevidas

- Estado: `implemented`
- Atualizado em: 2026-08-23
- Público: mantenedor PRO MASTER e usuários de laboratório
- Ambientes: Windows 10/11, WSL2 e Docker Desktop

## Resumo para leigos

No Windows, o Ubuntu do WSL2 não é o Docker Desktop. O terminal pode abrir mesmo
quando o mecanismo Docker está desligado. Se o instalador interpretar essa
situação como “Docker nunca instalado”, ele pode tentar preparar o Swarm outra
vez. O diagnóstico correto verifica Windows, WSL, Desktop e integração nessa
ordem.

## Objetivo

Evitar que falha de integração ou Docker Desktop desligado seja confundida com
ambiente limpo.

## O que observar

No PowerShell:

```powershell
wsl --version
wsl --status
wsl -l -v
```

Confirme que a distribuição usada aparece como versão 2. Depois, na interface
do Docker Desktop, confirme:

1. Docker Desktop está iniciado;
2. o mecanismo baseado em WSL 2 está habilitado;
3. a integração está habilitada para a distribuição correta.

Dentro da distribuição WSL2, use consultas somente leitura:

```bash
uname -m
docker version
docker info --format '{{.OSType}} {{.Architecture}} {{.Swarm.LocalNodeState}}'
docker context show
```

Se `docker version` mostra o cliente, mas não alcança o servidor, o problema não
é resolvido reinstalando o Setup MNO.

## Árvore de diagnóstico

- **Comando `docker` inexistente:** verifique integração e distribuição antes de
  instalar um segundo Docker Engine dentro do Ubuntu.
- **Cliente existe, daemon não responde:** abra o Docker Desktop e aguarde o
  engine ficar pronto.
- **Funciona em outra distribuição:** habilite a integração para a distribuição
  usada pelo Setup MNO.
- **WSL aparece como versão 1:** converta ou reinstale corretamente como WSL2.
- **Projeto em `/mnt/c`:** para desempenho e permissões mais previsíveis,
  mantenha código usado por ferramentas Linux no sistema de arquivos Linux.
- **Dois daemons Docker:** remova o conflito somente após inventário e plano;
  não altere o daemon que possui os dados válidos por tentativa.

## Limites e segurança

- Não redefina o Docker Desktop, exclua distribuições nem apague dados sem backup
  e autorização específica.
- Não reinstale Swarm, Docker ou Setup MNO apenas porque o daemon está desligado.
- A instalação de referência em `/root/SetupLowCodeMno` e seus recursos são
  imutáveis durante homologações isoladas.
- Um terminal remoto do Setup MNO continua proibido no modo `TRADICIONAL`.

## Fontes oficiais

- [Docker Desktop WSL 2 backend](https://docs.docker.com/desktop/features/wsl/)
- [Docker Desktop WSL best practices](https://docs.docker.com/desktop/features/wsl/best-practices/)
- [Use WSL with Docker Desktop](https://docs.docker.com/desktop/features/wsl/use-wsl/)
- [Microsoft WSL troubleshooting](https://learn.microsoft.com/en-us/windows/wsl/troubleshooting)

## Publicação futura no Help

Criar uma animação com quatro luzes: WSL2, distribuição, Docker Desktop e
integração. A recomendação só avança quando a camada anterior estiver confirmada.
