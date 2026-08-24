# Como usar o diagnóstico seguro do Especialista SRE

- Estado: `implemented`
- Maturidade: `beta`
- Público: usuários free, free1, free2, pro e pro-master
- Ambientes: Debian, Ubuntu, WSL2, Docker Desktop e Docker Swarm
- Atualizado em: 2026-08-24

## Resumo para leigos

Este guia mostra como pedir uma leitura segura da saúde do servidor. A leitura
é uma fotografia: ajuda a enxergar sinais, mas não aperta nenhum botão do
servidor e não corrige nada automaticamente.

## Antes de começar

- o Setup MNO Control Center deve estar online;
- o agente interno deve aparecer saudável;
- no WSL2, o Docker Desktop precisa estar aberto e integrado ao Ubuntu;
- não é necessário abrir terminal, colar log ou fornecer credencial.

## Passo a passo

1. Entre no Control Center.
2. Abra **Assistente MNO**.
3. Leia a faixa **Especialista SRE · BETA**.
4. No modo Básico, clique em **Executar diagnóstico seguro (BETA)**.
5. Se houver LLM configurada, pergunte: “Analise a saúde do servidor”.
6. Leia primeiro **Fatos observados**.
7. Depois leia **Hipóteses e limites**. Hipótese não é confirmação de causa.
8. Use o próximo passo sugerido apenas como orientação. A tela não executa a
   correção.

## O que você deve ver

- a frase **Nenhuma alteração foi realizada**;
- memória e disco classificados por limites locais;
- situação das réplicas;
- quantidade de eventos consultados;
- contagem de sinais de logs, quando houver serviço degradado;
- aviso de que a fotografia é pontual.

## Exemplo fictício

```text
Fato observado: existe 1 serviço sem todas as réplicas desejadas.
Evidência: degradedServices=1.

Hipótese: foram encontrados sinais de permissão nos logs agregados, mas a causa
não está confirmada.
```

O exemplo não informa nome do cliente, serviço, domínio nem conteúdo do log.

## Erros comuns

### “Snapshot SRE indisponível”

Confirme se o agente está saudável em **Visão geral**. No WSL2, confirme o
Docker Desktop. Não recrie o Swarm nem apague recursos para tentar corrigir.

### “Nenhuma causa foi confirmada”

Isso é uma proteção, não uma falha. O snapshot pode comprovar a réplica
degradada sem possuir evidência suficiente sobre a causa.

### O serviço aparece como `service-...`

É uma referência opaca temporária. Para ver nomes reais, use a área
**Aplicações instaladas**, que permanece local e autenticada; nomes reais não
são enviados no contexto do Assistente.

## Como testar no WSL2

1. Abra o Docker Desktop e aguarde `Engine running`.
2. Entre no Control Center de homologação.
3. Execute o diagnóstico seguro duas vezes.
4. Confirme que os números continuam coerentes e que as referências
   `service-...` mudam entre as fotografias.
5. Confirme que nenhuma stack reiniciou e nenhuma réplica foi alterada.

Sinal de falha: nome real, hostname, domínio, linha de log, token ou comando
aparecer no diagnóstico.

## Como testar em VPS

Use uma VPS de homologação ou snapshot recuperável. Execute o diagnóstico com
os serviços saudáveis e, se já existir um serviço degradado de teste, confirme
que ele aparece apenas por referência opaca e contagens. Não provoque falha em
aplicação de cliente para testar esta feature.

## Como Francis MNO pode ensinar

“A IA não recebe a chave da casa. O agente interno olha medidores previamente
permitidos, apaga nomes e conteúdo sensível e entrega apenas uma fotografia.
Primeiro mostramos o fato; depois, se necessário, levantamos uma hipótese. Nada
é corrigido automaticamente.”

## Limites e segurança

O diagnóstico não contém nomes reais de serviços, logs brutos, credenciais ou
comandos. Uma contagem de alertas é apenas um indício e precisa ser interpretada
junto com os fatos observados. Em incidentes graves, preserve evidências e peça
revisão humana antes de qualquer ação.

## Fontes oficiais

- https://docs.docker.com/engine/swarm/services/
- https://docs.docker.com/engine/swarm/how-swarm-mode-works/swarm-task-states/
- https://docs.docker.com/desktop/features/wsl/

## Publicação futura no Help

O passo a passo completo será adaptado para cartões curtos, imagens fictícias e
vídeos após homologação. O Help atual mostra somente o aviso BETA e as proteções
essenciais, sem copiar toda a base de conhecimento.
