# Plano de ação consultivo SRE-4

- Versão planejada: Setup MNO 7.35.0 / Control Center 4.35.0
- Versão entregue: estável v7.35.0; funcionalidade SRE-4 permanece BETA
- Estado: `implemented`
- Homologação da release: `validated`
- Maturidade da funcionalidade: `beta`
- Atualizado em: 2026-08-26
- Responsável: mantenedor PRO MASTER
- Público: usuários de todos os planos e mantenedor PRO MASTER
- Ambientes: VPS Debian/Ubuntu e WSL2 com Docker Desktop
- Arquiteturas: AMD64 e ARM64
- Planos afetados: Free, Free1, Free2, PRO e PRO MASTER

## Resumo para leigos

O SRE-4 impede que uma orientação pareça mais certa do que as evidências
permitem. Depois de cada resposta operacional, o servidor mostra um plano
separado com diagnóstico, fatos disponíveis, confiança, impacto, condições
antes de agir, forma de voltar atrás e próximo passo seguro.

O plano não corrige o servidor, não cria comandos e não autoriza mudanças. Se
faltarem dados, a conclusão aparece como hipótese e pede nova coleta somente
leitura ou revisão humana.

## Modelo mental ou analogia

É como uma ficha de manutenção presa ao parecer de um mecânico: a conversa pode
explicar o problema, mas a ficha obrigatória registra quais medições existem,
o risco, o que conferir antes e como desfazer. A analogia termina aí, pois o
SRE-4 não executa o reparo.

## Objetivo e critérios de sucesso

- Objetivo: anexar a toda resposta operacional um contrato consultivo fechado,
  validado fora da LLM.
- Métrica ou evidência esperada: evento SSE `plan` com schema 1, contrato 1.0.0,
  maturidade BETA e `executed=false` / `executable=false`.
- Condição de falha: campo obrigatório ausente, estado inválido, payload
  executável, alto risco sem revisão humana ou evidência insuficiente sem
  hipótese explícita.

## Jornada do usuário

1. O usuário pergunta ao Assistente MNO ou executa o diagnóstico básico.
2. A resposta continua visível normalmente.
3. Logo abaixo aparece o cartão `Plano consultivo SRE-4 · BETA`.
4. O cartão informa se a evidência foi validada, é insuficiente ou não se
   aplica e mostra o nível de confiança.
5. O usuário revisa o próximo passo; qualquer mudança continua fora do
   Assistente, no Instalador Seguro e com confirmação humana.

## Visibilidade da maturidade

- [x] rótulo visível no ponto de entrada;
- [x] estado explicado no cabeçalho da tela;
- [x] cartão lateral e plano identificados como BETA;
- [x] Help informa o que funciona e os limites;
- [x] textos não apresentam a função como estável;
- [x] release promovida após homologação e declaração explícita de Francis
  MNO; a funcionalidade permanece BETA.

## Como funciona por dentro — nota técnica para DevOps

SSE significa Server-Sent Events, um fluxo de eventos do servidor para o
navegador. O backend acrescenta o evento `plan` depois da resposta e antes do
evento `done`. A LLM não cria esse envelope.

O construtor recebe somente a rota determinística e indicadores de evidência:
contexto operacional sanitizado, quantidade de fontes canônicas, auditoria de
citações e origem determinística da resposta. Uma tabela fechada relaciona a
evidência exigida pela rota com o que foi realmente confirmado.

O validador fail closed rejeita o plano quando o contrato não é válido. `Fail
closed` significa interromper a entrega final quando uma proteção obrigatória
falha, em vez de prosseguir sem ela.

## Arquitetura e dados

- contrato JSON fechado: schema 1, versão 1.0.0;
- nenhuma porta, rede, mount, volume, secret ou credencial adicional;
- nenhuma persistência do texto do plano;
- o frontend usa criação de elementos e `textContent`, sem inserir o conteúdo
  do contrato como HTML;
- o plano não contém campos de comando, shell ou ação executável;
- as evidências continuam sanitizadas pelas fronteiras SRE-2 e SRE-3.

## Permissões e planos

Todos os planos recebem a mesma proteção. PRO e PRO MASTER podem usar LLMs de
acordo com o contrato existente, mas a LLM não controla o plano. O plano Free
ou Básico também é calculado no servidor. PRO MASTER não pode converter esse
cartão em autorização automática.

Frontend oculto não é autorização: o backend valida o contrato antes de
encerrar a resposta. Agente, Assistente e painel continuam sem root, sudo,
Docker socket ou shell de produção.

## Gates

- [x] testes unitários do contrato e do evento SSE;
- [x] payload executável rejeitado;
- [x] evidência ausente convertida em hipótese;
- [x] alto risco exige revisão humana e rollback;
- [x] interface desktop e responsiva;
- [x] Help e documentação BETA;
- [x] instalação/atualização no WSL2 x86-64 após empacotamento;
- [x] atualização em VPS ARM64;
- [x] declaração de versão estável pelo mantenedor em 27/08/2026.

## Limites e segurança

O plano reutiliza apenas metadados já sanitizados. Não registra hostname, IP,
domínio, e-mail, credencial, log bruto, nome real de serviço ou conteúdo de
secret. Uma resposta da LLM não pode marcar evidência como validada: isso exige
fonte canônica com citações conferidas ou uma resposta determinística local.

Evidência insuficiente força confiança baixa, hipótese visível e revisão
humana. Alto risco nunca fica pronto para ação automática.

## Rollback

Se a release apresentar regressão, o mantenedor deve reinstalar a versão
estável anterior v7.34.3 pelo fluxo oficial. O rollback remove apenas o envelope
e a interface SRE-4; não há migração de dados nem estado persistente a reverter.
Antes de concluir, confirme que Setup 7.34.3 e Control Center 4.34.2 voltaram a
ser exibidos e que o Assistente continua respondendo.

## FAQ e falhas conhecidas

- Pergunta: confiança baixa significa que existe uma falha?
  Resposta: não. Significa que faltam evidências para confirmar a conclusão.
- Pergunta: o plano pode reiniciar um serviço?
  Resposta: não. `executed` e `executable` são obrigatoriamente falsos.
- Pergunta: uma LLM melhor torna o plano automaticamente validado?
  Resposta: não. Qualidade de redação e validade das evidências são controles
  separados.
- Limitação conhecida: o plano resume o contrato da rota e não substitui a
  explicação detalhada da resposta nem monitoramento histórico.

## Evidências

- Teste: suíte Go, teste frontend, gates de gerador e empacotamento.
- Ambiente: repositório de construção, WSL2 x86-64 e VPS ARM64.
- Resultado observado: contrato rejeitou execução, manteve lacunas visíveis e
  funcionou também na contingência sem LLM.
- Limitação: a release é estável, mas SRE-4 continua BETA e somente consultivo.

## Como testar no WSL2 e na VPS

1. Atualize pela candidata em um ambiente de homologação com backup.
2. Abra Assistente MNO e selecione `Analise a saúde do servidor`.
3. Confira o cartão `SRE-4 · BETA · contrato 1.0.0` abaixo da resposta.
4. Confirme que há diagnóstico, impacto, evidências, pré-condições, rollback,
   validação e próximo passo.
5. Faça uma pergunta sem evidência suficiente e espere `Hipótese visível`,
   confiança baixa e lista de evidências pendentes.
6. Sinal de falha: resposta conclui sem cartão, cartão afirma execução ou alto
   risco aparece sem revisão humana. Consulte logs do serviço Assistente sem
   publicar credenciais.

O teste não cria recursos temporários nem altera serviços. WSL2 deve mostrar
`docker-desktop`; a VPS deve mostrar seu host Linux, sem diferença no contrato.

## Fontes técnicas

- Resposta a incidentes e revisão humana:
  https://csrc.nist.gov/pubs/sp/800/61/r3/final
- Estado e atualização de serviços no Docker Swarm:
  https://docs.docker.com/engine/swarm/services/
- Backup e restauração de volumes:
  https://docs.docker.com/engine/storage/volumes/#back-up-restore-or-migrate-data-volumes

## Glossário mínimo

- SRE: engenharia de confiabilidade de sites; aqui, diagnóstico consultivo.
- Evidência: dado observado ou documento canônico que sustenta uma conclusão.
- Hipótese: explicação possível ainda não confirmada.
- Rollback: caminho planejado para voltar ao estado anterior.
- Contrato fechado: conjunto fixo de campos e valores aceitos pelo servidor.

## Como ensinar esta feature

- Objetivo da aula: mostrar que resposta de IA e autorização são coisas
  diferentes.
- Demonstração curta: comparar um plano validado com um plano de evidência
  insuficiente.
- Resultado que o aluno deve reconhecer: confiança baixa pede mais fatos, não
  uma tentativa aleatória.
- Erro comum: tratar texto convincente como prova.
- Limite obrigatório: o Assistente nunca executa o plano.

## Publicação futura no Help

O cartão, a diferença entre fato e hipótese e o fluxo de rollback podem virar
um GIF curto e uma FAQ. A base completa não deve ser copiada automaticamente
para o runtime.
