# Laboratório Strix SRE-6

- Versão planejada: `v7.38.0`
- Versão entregue: candidata `v7.39.0` com jornada guiada simplificada
- Estado documental: `implemented`
- Maturidade da funcionalidade: `beta`
- Atualizado em: 28/08/2026
- Responsável pela governança: mantenedor PRO MASTER
- Ambientes: WSL2 e VPS Debian/Ubuntu
- Arquiteturas: AMD64 e ARM64
- Planos de diagnóstico: PRO e PRO MASTER

## Para iniciantes — o que isso resolve

O SRE-6 analisa uma cópia compactada do código de um projeto em uma caixa
descartável. Ele não recebe o servidor, os containers em produção, domínios,
IPs ou volumes. Ao terminar, a caixa é apagada e somente um resumo com
contagens permanece disponível por 24 horas.

A funcionalidade continua BETA: pode produzir falso positivo, depende da
qualidade da LLM escolhida e ainda permite acesso amplo de saída à internet
para conversar com o provedor da IA. Ela não corrige o projeto e não substitui
revisão humana.

## Modelo mental ou analogia

É como colocar uma fotocópia do projeto numa sala de inspeção lacrada. O
inspetor pode estudar a cópia e consultar a IA, mas não recebe a chave da sala
de produção. Depois da inspeção, a sala e as anotações detalhadas são
destruídas; sai apenas um placar sem nomes de arquivos ou trechos de código.

## Jornada do usuário

1. Um usuário PRO ou PRO MASTER abre `Assistente MNO`.
2. No cartão opcional `Analisar código-fonte com Strix · BETA`, seleciona
   `Analisar pacote de código`.
3. O Terminal Seguro exige nova autenticação e confirmação humana.
4. O usuário escolhe um único `.zip`, `.tar.gz` ou `.tgz` local, com até 128 MB.
5. Escolhe o modo guiado recomendado, que aplica limites seguros automáticos,
   ou o modo avançado para personalizar modelo, duração, interações e orçamento.
6. Usa uma chave de LLM dedicada e revogável, enviada uma única vez pela
   entrada padrão do container.
7. O executor copia o pacote, valida seu SHA-256, analisa a cópia e é removido.
8. O Control Center recebe somente contagens sanitizadas válidas por 24 horas.

## O que mudou e o que permaneceu igual

Mudou: o botão deixou de terminar em “preparação bloqueada” e agora abre o
diagnóstico real para PRO e PRO MASTER. A imagem do executor é construída e
testada durante a instalação ou atualização do Control Center.

Permaneceu igual: governança, homologação e exceções continuam exclusivas do
PRO MASTER. Não há correção automática, shell de produção, selo, publicação de
catálogo, commit, tag, release, DNS ou deploy automático.

## Arquitetura — nota técnica para DevOps

- upstream Strix `1.5.3` e wheel por arquitetura fixados por SHA-256;
- base `ghcr.io/usestrix/strix-sandbox:1.3.0` fixada por digest AMD64/ARM64;
- imagem executora local versionada com o Control Center;
- UID/GID fixo `61000:61000`, sem root, sudo ou shell de login;
- raiz somente leitura, `cap-drop ALL`, `no-new-privileges`, PID, CPU, RAM,
  tempo, interações e orçamento limitados;
- nenhum bind mount e nenhum `/var/run/docker.sock`;
- pacote entra por `docker cp`, depois de autorização fechada e hash exato;
- chave entra por `stdin`, nunca por argumento, environment, arquivo, secret ou
  log;
- backend `UnixLocal` executa dentro do próprio container descartável;
- evidência bruta existe somente em `/tmp` do container e é apagada antes da
  saída;
- somente relatório conforme schema fechado `1.1.0` pode ser promovido.

O executor usa rede `bridge` para alcançar a LLM. Nesta BETA ainda não existe
proxy de saída com lista de destinos permitidos. Portanto, “isolado” significa
isolado do host e da produção, não isolado da internet.

## Planos e autorização

PRO e PRO MASTER podem executar o diagnóstico. O backend, o launcher, a
reautenticação e o terminal repetem essa regra; esconder o botão não é tratado
como autorização. Planos Free são bloqueados. Somente PRO MASTER governa
políticas, aprova exceções e homologa mudanças canônicas.

## Gates e evidências

- [x] contratos de autorização e relatório fechados;
- [x] lock, licença, versão, URL e hashes do upstream;
- [x] imagem base por digest em AMD64 e ARM64;
- [x] smoke test do import Strix e backend UnixLocal;
- [x] UID 61000, rootfs somente leitura e capacidades removidas;
- [x] zero mounts e zero Docker socket;
- [x] limpeza de containers, imagem e diretório temporários da homologação;
- [x] diagnóstico liberado para PRO e PRO MASTER;
- [x] governança exclusiva do PRO MASTER;
- [ ] validação visual da candidata no WSL2 AMD64;
- [ ] validação visual da candidata em VPS ARM64;
- [ ] promoção estável declarada por Francis MNO.

## Segurança, privacidade e limites

- use somente pacote-fonte próprio ou expressamente autorizado;
- não compacte `.env`, backups, chaves, tokens ou dados pessoais;
- use chave de LLM dedicada, limitada e revogável;
- o limite de gasto declarado no Setup não substitui o limite no provedor;
- a LLM recebe contexto produzido pelo Strix e sua qualidade afeta o resultado;
- achados são BETA, podem estar errados e exigem revisão humana;
- o executor não deve ser confundido com pentest de domínio ou servidor;
- qualquer divergência de contrato, hash ou isolamento bloqueia a execução.

## Como testar no WSL2 e na VPS

Pré-requisitos: Docker ativo, Control Center atualizado, plano PRO ou PRO
MASTER, pacote fictício sem segredos e chave dedicada de teste.

1. Confirme Setup `7.39.0` e Control Center `4.39.0`.
2. Abra Assistente MNO > análise avançada de código > `Analisar pacote de código`.
3. Informe um pacote fictício em `/tmp/exemplo-seguro.zip`.
4. Escolha `GUIADO`, revise o resumo único e forneça a chave dedicada. Repita
   no modo avançado para confirmar que ele ainda exige `AUTORIZO`.
5. Resultado esperado: relatório com estado e contagens, validade de 24 horas e
   aviso de que nenhuma correção foi aplicada.
6. Sinal de falha: pedido de domínio/IP, acesso a serviço real, container que
   permanece após o fim, chave em log, ausência da etiqueta BETA ou mensagem de
   contrato/hash divergente.
7. Compare stacks e serviços antes/depois: nenhum recurso de produção deve ser
   criado, reiniciado ou atualizado.

Homologação técnica do mantenedor:

```bash
bash 1_codigo_fonte/setupmno-control/strix-lab/homologate.sh
```

O sucesso termina com `SRE6_HOMOLOGATION_OK` e
`SRE6_HOMOLOGATION_CLEANUP_OK`. A falha mostra as últimas evidências de build e
ainda remove somente os recursos com o identificador exclusivo da execução.

## Erros comuns

- `imagem não disponível`: a atualização do Control Center não construiu a
  imagem; consulte o log de reconciliação e repita a sincronização.
- `pacote inválido`: use ZIP/TAR regular, sem link simbólico e dentro do limite.
- `relatório não produzido`: confirme disponibilidade, crédito, modelo e
  limites do provedor; nenhuma saída bruta é preservada.
- resultado fraco ou inconsistente: repita com modelo de melhor qualidade e
  compare somente contagens revisadas, nunca trate a LLM como prova.

## Rollback

Voltar para v7.38.0 restaura a jornada detalhada anterior. A reconciliação
anterior do Control Center deve ser usada; não
remova stacks, volumes ou bancos. Imagens locais antigas sem serviço associado
podem ser removidas somente depois de confirmar o nome exato e que não estão em
uso.

## Como explicar para a comunidade

“O SRE-6 BETA analisa uma cópia local do código numa caixa descartável, sem
entrar no Docker ou no servidor em produção. Ele entrega apenas contagens para
revisão humana, não corrige nada sozinho, e a qualidade depende da IA escolhida.”
