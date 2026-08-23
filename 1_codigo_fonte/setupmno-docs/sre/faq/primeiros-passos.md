# FAQ — primeiros passos em SRE no Setup MNO

- Estado: `implemented`
- Atualizado em: 2026-08-23
- Público: mantenedor PRO MASTER e autores do futuro Help
- Ambientes: Debian, Ubuntu, WSL2 e Docker Swarm

## Resumo para leigos

Estas respostas evitam os atalhos mais perigosos: reinstalar sem diagnóstico,
entregar root a uma IA, apagar volumes e acreditar que um container “Up” prova
que a aplicação e os dados estão saudáveis.

## Perguntas frequentes

### Posso pedir ao Codex ou Claude Code para administrar a pasta `/root`?

Não é o desenho seguro do Setup MNO. Uma IA deve analisar fatos sanitizados e
preparar um plano. Root, sudo, grupo `docker`, Docker socket, shell e credenciais
globais continuam proibidos ao assistente.

### Se o Docker não responder no WSL2, reinstalo o Setup MNO?

Não. Primeiro confirme WSL2, Docker Desktop ligado e integração da distribuição.
Um daemon desligado não significa ambiente limpo.

### Container `Up` significa aplicação homologada?

Não sozinho. No mínimo verifique arquitetura, serviço, convergência, estabilidade,
logs, resposta web e imagem por digest. O Selo Essencial possui escopo limitado e
não afirma backup, restore ou todas as funções internas.

### Posso executar `docker system prune` para liberar espaço?

Não como tentativa genérica. Inventarie o consumo, a propriedade dos recursos e
o impacto. Volumes podem conter os únicos dados válidos.

### Um backup criado com sucesso basta?

Não. É preciso validar integridade e testar restauração isolada. Registre versão,
duração, RPO, RTO e resultado.

### Reiniciar o serviço é um diagnóstico?

Não. Pode ser uma ação de estabilização autorizada, mas antes preserve a primeira
falha e o estado das tarefas. O reinício pode apagar a melhor pista.

### Cloudflare com nuvem laranja muda o destino que aparece no DNS?

Sim, o proxy pode responder com endereços da borda. Diagnostique DNS, borda,
Tunnel/Traefik, TLS e origem separadamente.

### Redirecionar `www` resolve `NXDOMAIN`?

Não. O navegador precisa resolver o hostname e concluir TLS antes de receber o
redirecionamento HTTP. `www` precisa existir no DNS e estar coberto pelo TLS.

### A futura IA SRE poderá corrigir tudo sozinha?

Não. Ela explicará diagnóstico e plano. Ações reais passarão por política,
runbook versionado, dry-run, confirmação humana, backup e rollback.

### Quem poderá aprovar novas skills e exceções?

Somente o PRO MASTER. Proteções críticas, porém, valem para todos os planos.

## O que observar

Quando pedir ajuda, informe sem segredos: ambiente, arquitetura, versão, horário,
impacto, primeira mensagem de erro e mudança recente. Não envie senha, token,
chave, cookie ou dados reais de clientes.

## Limites e segurança

Esta FAQ ensina decisões; ela não autoriza comandos. Em dúvida sobre propriedade
de um recurso, trate-o como preexistente e imutável.

## Fontes oficiais

- [Docker security](https://docs.docker.com/engine/security/)
- [Docker Desktop WSL 2 backend](https://docs.docker.com/desktop/features/wsl/)
- [Cloudflare Tunnel](https://developers.cloudflare.com/tunnel/)
- [Traefik HTTP routers](https://doc.traefik.io/traefik/reference/routing-configuration/http/routing/router/)

## Publicação futura no Help

Converter cada pergunta em um bloco pesquisável com resposta curta, botão “ver
detalhes” e link para a trilha correspondente. Nenhum bloco deve aceitar ou
armazenar credenciais.
