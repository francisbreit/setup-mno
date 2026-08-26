# Motores determinísticos do Especialista SRE

- Estado: `implemented`
- Público: usuários dos planos Free, Free1, Free2, PRO e PRO MASTER; governança do mantenedor PRO MASTER
- Ambientes: WSL2 com Docker Desktop e VPS Debian/Ubuntu
- Atualizado em: 2026-08-25
- Maturidade da funcionalidade: `beta`
- Versão candidata: Setup MNO 7.34.0 e Control Center 4.34.0

## Resumo para leigos

O SRE-3 adiciona três instrumentos de medição ao diagnóstico do servidor:
Trivy conta vulnerabilidades conhecidas nas imagens usadas pelo Docker, Lynis
confere itens de segurança do Linux e Docker Bench verifica controles do padrão
CIS para Docker. CIS é o Center for Internet Security, organização que publica
referências de configuração segura.

Pense nesses motores como três termômetros independentes. O Assistente MNO pode
explicar a leitura, mas não pode trocar o número, esconder uma falha nem dizer
que a medição foi completa quando uma parte não foi executada.

O recurso não corrige o servidor, não instala atualizações, não remove imagens
e não prova sozinho que o ambiente está seguro. Ele produz uma fotografia com
validade de 24 horas, formada apenas por contagens sanitizadas.

## Jornada do usuário

1. Abra Assistente MNO e localize **Motores determinísticos · BETA**.
2. Clique em **Executar auditoria segura**.
3. Redigite a senha administrativa para entrar no Terminal Seguro.
4. Leia o aviso de consumo de CPU, disco e internet e confirme uma única vez.
5. Aguarde Trivy, Lynis e Docker Bench terminarem ou informarem cobertura parcial.
6. Atualize o painel. O Assistente passa a exibir estado, validade, contagens e limitações.

Em instalação Tradicional, o botão remoto continua bloqueado. O administrador
acessa a VPS por SSH e executa:

```bash
sudo bash /root/SetupLowCodeMno/.control/sre-engine/run.sh
```

## Objetivo e critérios de sucesso

- Objetivo: fornecer fatos repetíveis e independentes da qualidade da LLM.
- Sucesso: versões e hashes fixos, confirmação humana, resultado fechado e
  sanitizado, validade de 24 horas e cobertura incompleta sempre visível.
- Falha: pacote adulterado, hash divergente, formato desconhecido, resultado
  expirado ou scanner que não concluiu produz estado inválido/incompleto; nunca
  um falso estado saudável.

## Limites e segurança

- O pacote do motor é externo ao SHC, mas cada arquivo possui tamanho e SHA-256
  ancorados no release promovido pelo gatilho protegido.
- SHA-256 é uma impressão digital criptográfica: qualquer byte alterado produz
  outra impressão e bloqueia a promoção ou a execução.
- Trivy usa a imagem oficial fixada por digest. O banco de vulnerabilidades é
  baixado antes da análise; a leitura das imagens ocorre depois, sem rede e sem
  Docker socket. A documentação oficial do Trivy explica o uso de imagens e
  alvos: https://github.com/aquasecurity/trivy/blob/main/docs/getting-started/installation.md
- Lynis 3.1.7 é baixado do fornecedor, validado por SHA-256 e executado sem
  rede. No Terminal Seguro, `--root-dir` examina o host montado somente para
  leitura, mas essa cobertura é parcial. Fonte oficial:
  https://cisofy.com/documentation/lynis/get-started/
- Docker Bench 1.6.1 vem do release oficial fixado e implementa o CIS Docker
  Benchmark 1.6.0: https://github.com/docker/docker-bench-security/releases/tag/v1.6.1
- Docker Bench precisa consultar a API Docker. Somente esse scanner recebe o
  socket, montado no container temporário de fonte fixa; Trivy, Lynis, agente,
  painel e LLM não recebem o socket.
- Os checks `5.7` e `7.5` do upstream ficam excluídos porque respectivamente
  usam `docker exec` nos containers e consultam a chave de desbloqueio do
  Swarm. Essa exclusão aparece como cobertura parcial.
- Containers temporários usam nomes `setupmno-sre3-*`, limites de CPU, memória,
  processos e tempo, rede desligada durante as análises e limpeza ao encerrar.
- Achados brutos, nomes de imagens, CVEs, paths, hostname, IP e credenciais não
  entram em `latest.json`. Apenas contagens e códigos de evidência permitidos
  chegam ao agente.
- Um aviso do scanner exige revisão humana; ele não prova exploração nem autoriza
  alteração automática.

## Nota técnica para DevOps

O registro `tools.json` fixa versão, URL ou digest, hash e limites. O instalador
gera `manifest.json`, promove os quatro arquivos permitidos para
`.control/sre-engine/` por arquivo temporário e `mv` atômico, e recusa caminhos
extras. O runner volta a verificar manifesto, tamanho e hash antes de executar.

O normalizador implementa um contrato JSON fechado de 32 KiB. Ele converte os
resultados efêmeros em contagens por motor, `overallStatus`, `complete`,
`generatedAt`, `expiresAt`, fatos observados e limitações. O agente aceita
somente arquivo regular 0600, schema conhecido, versões fixas, estados e campos
permitidos. Ausência, expiração, adulteração ou campo desconhecido falham de
forma fechada.

O disclosure determinístico é acrescentado no servidor depois da resposta do
provedor. Portanto, nem prompt injection nem uma LLM de baixa qualidade podem
removê-lo. O Assistente continua consultivo e sem ferramenta de execução.

## Permissões e planos

As proteções e o resumo existem para todos os planos. A execução exige root e
confirmação humana no Terminal Seguro. O terminal web continua permitido apenas
em Cloudflare Tunnel; no modo Tradicional, use SSH. A governança do pacote,
exceções, homologação e promoção canônica permanecem exclusivas do PRO MASTER.

## Como testar no WSL2 e na VPS

### WSL2

Pré-requisitos: Docker Desktop em execução, integração WSL ativa, Swarm ativo e
Control Center atualizado.

1. No painel, execute **Motores determinísticos · BETA**.
2. Confirme a auditoria no Whiptail e aguarde.
3. Atualize a página e faça `Analise a saúde do servidor`.

Resultado esperado: aparece a seção **Auditoria determinística SRE-3 BETA** com
validade, contagens e a cobertura parcial de Lynis/Docker Bench. Um scanner com
falha continua visível como auditoria incompleta.

Sinal de falha: mensagem de pacote inválido, hash divergente, ferramenta
`failed`, resultado expirado ou ausência do cartão. Consulte somente o resumo
sanitizado e o terminal; não envie tokens nem achados brutos ao suporte.

### VPS Debian/Ubuntu

Em Cloudflare Tunnel, repita o fluxo do botão. No modo Tradicional, conecte por
SSH e execute o comando mostrado na jornada. O resultado esperado é o mesmo,
mas Lynis pode obter cobertura completa quando executado diretamente no host.

A auditoria não cria volumes, redes, stacks ou serviços persistentes. O cache
do banco do Trivy permanece em `/root/.cache/setupmno-sre3/trivy` para evitar
downloads repetidos; containers e arquivos brutos temporários são removidos.

## Rollback

Volte ao commit ou pacote estável anterior e execute novamente a reconciliação
do Control Center. O runtime anterior não lê `latest.json`. Não há rollback de
dados porque nenhum banco, volume, stack ou configuração da aplicação é
alterado. Não apague recursos Docker do usuário para desfazer esta feature.

## FAQ

**Uma LLM gratuita pode mudar o resultado dos scanners?**

Não. Ela pode explicar pior ou melhor, mas o bloco determinístico é validado e
anexado pelo servidor depois da resposta da LLM.

**Cobertura parcial significa que o servidor está inseguro?**

Não. Significa apenas que alguns controles não foram medidos. É uma limitação,
não uma aprovação nem uma condenação do ambiente.

**Por que o Docker Bench recebe o socket?**

Porque seus controles precisam consultar o estado do Docker. A permissão fica
restrita ao scanner oficial de hash fixo e confirmado pelo usuário. O projeto
não trata o sufixo `:ro` como autorização suficiente e exclui os checks
intrusivos conhecidos.

## Evidências

- teste de normalização com dados fictícios e prova de sanitização;
- teste de cobertura incompleta e expiração;
- teste de adulteração/permissões do resultado;
- prova de que somente Docker Bench recebe o socket;
- paridade x86/ARM, manifesto, gerador, testes Go e empacotamento;
- hash oficial do Docker Bench conferido contra o tarball do release.

## Publicação futura no Help

O cartão BETA, o aviso de cobertura parcial, a validade e o fluxo de execução já
podem aparecer no Help. Um tutorial visual futuro deve usar ambiente fictício e
mostrar como diferenciar `attention`, `incomplete` e `no-critical-signals`, sem
publicar CVEs, nomes de imagens, IPs ou dados reais.

## Como ensinar esta feature

Explique à comunidade que o SRE-3 é um painel com três instrumentos, não um
robô que conserta o servidor. Demonstre uma auditoria, a validade de 24 horas e
uma cobertura parcial. O aluno deve reconhecer que “nenhum sinal crítico” não
significa “servidor garantidamente seguro” e que toda correção continua no
Instalador Seguro com decisão humana.
