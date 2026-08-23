# Modelo operacional do especialista SRE

- Estado: `implemented`
- Atualizado em: 2026-08-23
- Público: mantenedor PRO MASTER e autores do futuro Help
- Ambientes: Debian, Ubuntu, WSL2, Docker Desktop e Docker Swarm

## Resumo para leigos

Um erro visto no navegador pode nascer no DNS, no certificado, no Traefik, no
Swarm, no container ou na própria aplicação. Reiniciar tudo esconde a causa e
pode destruir a melhor evidência. O modelo operacional investiga uma camada por
vez e só propõe uma ação quando os fatos sustentam o diagnóstico.

## Objetivo

Padronizar a linguagem e a ordem de análise do Setup MNO. O mesmo contrato será
reutilizado, no futuro, pelo especialista somente leitura, pelos coletores
determinísticos e pelos runbooks aprovados.

## Camadas de análise

| Ordem | Camada | Pergunta objetiva | Exemplo de evidência |
|---|---|---|---|
| 1 | Cliente | O nome resolve e a conexão chega à borda? | código DNS/HTTP e horário |
| 2 | Cloudflare | DNS, Access e Tunnel apontam para o recurso esperado? | estado sanitizado da rota |
| 3 | Traefik | Existe router compatível com host, entrypoint e TLS? | regra e serviço de destino |
| 4 | Swarm | O manager tem quorum e o serviço convergiu? | nós, réplicas e tarefas |
| 5 | Container | A imagem iniciou e permaneceu saudável? | estado, healthcheck e logs |
| 6 | Aplicação | A porta interna e o fluxo mínimo respondem? | resposta local controlada |
| 7 | Dados | Volumes e bancos estão íntegros e restauráveis? | backup e restore testado |

No WSL2 há duas camadas adicionais antes do Docker: Windows/WSL e Docker
Desktop. Se o Desktop estiver desligado ou sem integração com a distribuição,
não existe motivo para reinstalar o Swarm.

## Fluxo fatos, diagnóstico, plano e execução

1. **Fatos:** dados obtidos por consultas fixas e sanitizadas.
2. **Diagnóstico:** explicação que liga os fatos a uma hipótese, com confiança e
   lacunas explícitas.
3. **Plano:** ação sugerida, impacto, pré-condições e rollback.
4. **Gate:** política determinística decide se a ação é permitida.
5. **Execução:** somente um runbook versionado realiza a mudança após aprovação.
6. **Verificação:** compara o estado final com os critérios definidos antes da
   ação.

A IA participa das etapas 2 e 3. Ela não substitui o gate nem executa a etapa 5.

## O que observar

- horário, duração e escopo do incidente;
- versão do host, Docker, Setup MNO e imagens;
- diferença entre estado desejado e estado observado;
- primeira falha, não apenas mensagens posteriores em cascata;
- mudanças recentes;
- capacidade de rollback de configuração e de dados;
- dados que precisam ser sanitizados antes de entrar em relatório.

## Limites e segurança

Estado desconhecido resulta em bloqueio, não em permissão. Logs podem conter
tokens, URLs privadas, e-mails e conteúdo de usuários; por isso o futuro agente
deverá expor apenas campos permitidos e logs sanitizados. Montar o Docker socket
em um chatbot equivale, na prática, a entregar administração do host e continua
proibido.

## Evidência mínima de um diagnóstico

Todo diagnóstico futuro deverá apresentar:

- conclusão em linguagem simples;
- fatos usados e origem de cada fato;
- nível de confiança;
- hipóteses descartadas;
- impacto provável;
- ação proposta;
- pré-condições;
- rollback;
- validação após a ação;
- indicação clara de que nada foi executado, quando aplicável.

## Fontes oficiais

- [Docker Swarm administration guide](https://docs.docker.com/engine/swarm/admin_guide/)
- [Traefik HTTP routers](https://doc.traefik.io/traefik/reference/routing-configuration/http/routing/router/)
- [Cloudflare Tunnel](https://developers.cloudflare.com/tunnel/)
- [WSL troubleshooting](https://learn.microsoft.com/en-us/windows/wsl/troubleshooting)

## Publicação futura no Help

Transformar as camadas em um fluxograma interativo: “o domínio não abre”, “o
serviço não converge” e “o Docker não responde”. Cada resposta deve mostrar o
próximo teste somente leitura e explicar por que ele é seguro.
