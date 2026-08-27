# Gate de qualidade da saída do Assistente MNO

- Versão planejada: Setup MNO 7.36.1 / Control Center 4.36.1
- Versão corrigida: candidata v7.36.2 / Control Center 4.36.2
- Estado: `implemented`
- Maturidade da funcionalidade: `beta`
- Atualizado em: 2026-08-27
- Responsável: mantenedor PRO MASTER
- Público: usuários de todos os planos e mantenedor PRO MASTER
- Ambientes: VPS Debian/Ubuntu e WSL2 com Docker Desktop
- Arquiteturas: AMD64 e ARM64
- Planos afetados: Free, Free1, Free2, PRO e PRO MASTER

## Resumo para leigos

Modelos de linguagem gratuitos ou congestionados podem devolver símbolos como
`<unk>`, repetir trechos, misturar instruções internas em inglês ou afirmar que
existem falhas que a fotografia do servidor não mostrou. O gate de qualidade
inspeciona a resposta antes que ela apareça na conversa.

Quando encontra um defeito objetivo, o texto externo é descartado e o usuário
recebe um diagnóstico local, sanitizado e somente leitura. O gate não promete
que toda resposta aceita está correta: recomendações continuam exigindo revisão
humana e a qualidade também depende do modelo escolhido.

## Modelo mental ou analogia

É como um filtro instalado antes da torneira: se detectar sujeira conhecida, a
água daquele fluxo não chega ao copo e uma reserva segura é usada. A analogia
termina aí, pois o filtro não consegue provar que toda água que passou é
perfeita; ele reconhece apenas sinais e contradições definidos no código.

## Objetivo e critérios de sucesso

- Objetivo: impedir que uma saída externa objetivamente inválida seja exibida
  como diagnóstico confiável.
- Evidência esperada: resposta armazenada em memória até a validação, evento SSE
  `output_gate`, banner BETA e fallback local quando houver rejeição.
- Condição de falha: `<unk>`, instrução interna, repetição anormal, idioma
  incompatível ou contradição conhecida chega ao navegador como resposta do
  Assistente.

SSE significa *Server-Sent Events*: um fluxo de eventos de texto enviado pelo
servidor ao navegador. Nesta candidata, o texto da LLM só entra nesse fluxo
depois de aprovado.

## Jornada do usuário

1. O usuário envia uma pergunta ao Assistente MNO.
2. O roteador local, o RAG e o provedor trabalham como antes.
3. O backend mantém a resposta externa temporariamente em memória.
4. O gate compara formato, idioma e afirmações objetivas com o snapshot SRE.
5. Se aprovada, a resposta normal é exibida.
6. Se rejeitada, um aviso `Gate de qualidade BETA acionado` aparece e o
   diagnóstico local seguro substitui integralmente o texto externo.
7. O plano SRE-4 e os limites de confirmação humana continuam visíveis.

## Visibilidade da maturidade

- [x] BETA visível no aviso apresentado quando o gate atua;
- [x] Help explica o comportamento antes do uso;
- [x] a substituição informa que a saída externa foi rejeitada;
- [x] a qualidade da LLM continua apresentada separadamente do motor local;
- [ ] promoção depende de homologação no WSL2, em VPS e declaração de Francis MNO.

## Como funciona por dentro — nota técnica para DevOps

O cliente do provedor deixa de encaminhar cada fragmento da LLM diretamente ao
`ResponseWriter`. A resposta completa fica limitada a 128 KiB em memória e só
é enviada após passar pelos validadores de fundamentação e de saída.

O gate 1.0.0 rejeita, de forma determinística:

- resposta vazia, grande demais ou com UTF-8 inválido;
- marcadores de token desconhecido, como `<unk>` e `[unk]`;
- assinaturas conhecidas de prompt ou política interna;
- repetição excessiva de tokens ou linhas;
- texto predominantemente em inglês numa resposta esperada em português;
- afirmação de serviço degradado quando o snapshot sanitizado registra zero;
- afirmação de vulnerabilidade crítica ou alta diferente da contagem SRE-3;
- identidade de provedor incompatível com o provedor configurado.

As contradições são avaliadas sentença por sentença. Assim, uma frase correta
como “não há falhas” não mascara outra frase posterior que inventa serviços em
estado `failed`.

Uma rejeição gera somente um motivo estruturado de uma lista fechada. O proxy
web lê esse resultado por um trailer HTTP autenticado e grava o evento
`assistant_output_rejected`; a resposta rejeitada não é copiada para a
auditoria. O navegador recebe o evento SSE `output_gate` e, em seguida, apenas
o fallback determinístico.

## Arquitetura e dados

- nenhum novo serviço, imagem, porta, volume, mount, config ou Docker Secret;
- resposta externa transitória somente em memória e limitada a 128 KiB;
- nenhum texto rejeitado persistido em feedback ou auditoria;
- fallback usa o snapshot SRE já sanitizado e o conhecimento local permitido;
- backend, proxy e frontend compartilham apenas estado fechado de aceitação ou
  rejeição; o frontend não decide segurança.

## Permissões e planos

O gate protege todos os planos e não cria uma permissão nova. Planos sem LLM
continuam no diagnóstico Básico. PRO e PRO MASTER continuam sujeitos ao mesmo
controle, independentemente do provedor ou modelo. PRO MASTER governa o código
canônico, mas não consegue desativar o gate pela conversa.

## Gates

- [x] testes unitários de aceitação, rejeição e fallback;
- [x] teste de contradições em sentenças diferentes;
- [x] frontend reconhece o evento e mostra BETA;
- [x] texto externo não é transmitido antes da decisão;
- [x] auditoria recebe somente motivo estruturado;
- [x] fontes incluídas no gerador e nos artefatos AMD64/ARM64;
- [ ] homologação visual no WSL2 x86-64;
- [ ] homologação visual em VPS AMD64 ou ARM64.

## Limites e segurança

O comportamento é *fail closed*: quando a resposta externa não pode ser
validada, ela não é mostrada. O fallback não possui shell, Docker socket, root,
credenciais ou autorização de mudança. O gate também não armazena a pergunta,
a resposta ou fragmentos rejeitados.

Limite importante: uma resposta plausível, em português e sem contradição
mensurável ainda pode estar incompleta ou errada. O RAG, o plano SRE-4, a
revisão humana e um modelo adequado continuam necessários.

## Rollback

Se a candidata causar regressão, reinstale a última estável v7.35.0 pelo fluxo
oficial. Não há migração de banco nem dado persistente criado pelo gate. Após o
rollback, confira Setup 7.35.0 e Control Center 4.35.0 na Visão geral. Não apague
volumes, secrets ou stacks para fazer a reversão.

## FAQ e falhas conhecidas

- Pergunta: usar uma LLM paga garante resposta correta?
  Resposta: não. Modelos mais capazes tendem a melhorar consistência, mas toda
  resposta operacional continua consultiva e revisável.
- Pergunta: o gate traduz uma resposta em inglês?
  Resposta: não. Quando o idioma é claramente incompatível, o texto é rejeitado
  e substituído pelo fallback local para evitar alterar seu significado.
- Pergunta: por que o banner aparece somente em algumas perguntas?
  Resposta: ele aparece apenas quando o gate rejeita a saída daquela consulta.
- Falha conhecida: afirmações sem correspondência em um campo objetivo do
  snapshot podem passar. O gate não substitui avaliação factual completa.

## Evidências

- Teste: suíte Go do Control Center, testes do frontend e gates de release.
- Ambiente: build multi-arquitetura reproduzível; homologação visual pendente.
- Resultado esperado: saída externa aceita ou fallback local, nunca mistura.
- Limitação: a precisão semântica ampla ainda depende do modelo e do RAG.

## Como testar no WSL2 e na VPS

### WSL2

1. Pré-requisito: Docker Desktop ativo, Setup MNO 7.36.2 candidata e provedor
   configurado sem revelar a chave.
2. No Assistente, pergunte `Faça uma revisão de segurança do servidor`.
3. Resultado esperado: resposta coerente em português ou aviso BETA seguido do
   diagnóstico local seguro.
4. Sinal de falha: `<unk>`, política interna em inglês ou número incompatível
   aparece na conversa. Consulte somente logs sanitizados do serviço web.
5. Limpeza: nenhuma; o teste não cria recurso Docker nem dado persistente.

### VPS

Repita a mesma pergunta em VPS Debian ou Ubuntu. Confirme também que o plano
SRE-4 informa que nenhuma ação foi executada. Falha é qualquer texto rejeitado
visível, ausência do fallback ou reinício/degradação dos serviços do painel.
Não envie token, domínio, hostname ou resposta bruta contendo dado pessoal ao
suporte.

## Glossário mínimo

- LLM: modelo de linguagem que gera a resposta externa.
- Gate: verificação obrigatória que permite ou bloqueia a próxima etapa.
- Fallback: resposta alternativa local usada quando o provedor falha ou é
  rejeitado.
- Snapshot SRE: fotografia sanitizada e pontual dos fatos permitidos do servidor.

## Como ensinar esta feature

- Objetivo: mostrar que conectar uma IA não significa confiar cegamente nela.
- Demonstração: comparar uma resposta normal com uma saída rejeitada e seu
  fallback local.
- Resultado: o aluno reconhece o banner BETA e sabe que nenhuma ação ocorreu.
- Erro comum: dizer que o gate elimina todas as alucinações.
- Limite obrigatório: modelo, RAG, gates e revisão humana são camadas
  complementares; nenhuma delas isoladamente garante verdade.

## Publicação futura no Help

O resumo para iniciantes, o aviso BETA, a lista curta de sinais bloqueados e a
FAQ podem permanecer no Help. Detalhes de assinaturas, limites internos e
auditoria pertencem à documentação técnica e não devem lotar a interface.

## Referências oficiais

- [OWASP GenAI — Prompt Injection](https://genai.owasp.org/llmrisk/llm012025-prompt-injection/)
- [NIST SP 800-218A — Secure Software Development Practices for Generative AI](https://csrc.nist.gov/pubs/sp/800/218/a/final)
