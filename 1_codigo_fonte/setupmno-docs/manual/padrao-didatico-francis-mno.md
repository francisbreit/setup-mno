# Padrão didático para Francis MNO e sua comunidade

- Estado: `implemented`
- Público: Francis MNO, alunos, clientes e profissionais de infraestrutura
- Aplicação: explicações, entregas técnicas, manuais, FAQ, aulas e Help futuro

## Para iniciantes — por que este padrão existe

O Setup MNO reúne muitas peças técnicas: Linux, Docker, Docker Swarm, redes,
domínios, certificados e aplicações. Uma pessoa não precisa dominar todas elas
antes de começar, mas precisa entender o que está fazendo, reconhecer um
resultado correto e saber quando deve parar e pedir ajuda.

Este padrão organiza cada assunto em camadas. Primeiro vem a explicação simples.
Depois, quem quiser conferir os detalhes encontra a camada técnica. Assim, um
mesmo material pode ajudar um aluno iniciante e continuar útil para um
profissional de DevOps.

## Modelo mental

Pense no Setup MNO como uma oficina organizada:

- o instalador é o procedimento de montagem;
- o Docker Swarm é o encarregado que tenta manter os serviços funcionando como
  foram planejados;
- as stacks são as fichas de montagem de cada conjunto de aplicações;
- os volumes guardam dados que precisam sobreviver à troca de um container;
- os gates são inspeções obrigatórias antes de liberar uma mudança;
- o rollback é o plano de retorno quando a mudança não funciona.

A analogia ajuda a localizar cada peça, mas não substitui a documentação
técnica. Por exemplo, voltar a imagem de um container não restaura
automaticamente os dados de um banco.

## Estrutura obrigatória de uma boa explicação

1. **Problema:** o que estava difícil, quebrado ou arriscado.
2. **Benefício:** o que melhora para a pessoa que usa o Setup MNO.
3. **Modelo mental:** uma analogia curta, se for útil.
4. **Funcionamento:** os componentes envolvidos e a ordem dos acontecimentos.
5. **Experiência:** o que aparecerá na tela ou no terminal.
6. **Segurança:** o que é protegido, o que continua sendo risco e o que a
   ferramenta não promete fazer.
7. **Teste:** ação, resultado esperado e sinal de falha.
8. **Rollback:** como voltar com segurança, diferenciando aplicação e dados.
9. **Como ensinar:** uma síntese pronta para demonstração ou aula.

## Tradução de termos técnicos

### Réplicas 1/1

Para iniciantes: o Swarm recebeu a ordem de manter uma cópia do aplicativo e
conseguiu deixar essa cópia funcionando.

Nota técnica para DevOps: o estado desejado e o estado atual do serviço estão
em uma réplica. Isso não comprova sozinho que a aplicação responde corretamente;
healthcheck, logs e teste funcional ainda podem ser necessários.

### Serviço convergiu

Para iniciantes: depois da instalação ou atualização, o Swarm chegou ao estado
que foi pedido e parou de tentar substituir tarefas com erro.

Nota técnica para DevOps: todas as tarefas atingiram o estado desejado dentro do
tempo definido. Convergência não prova persistência, backup ou qualidade de
resposta da aplicação.

### Quorum

Para iniciantes: os servidores responsáveis por tomar decisões precisam formar
uma maioria. Sem essa maioria, o Swarm evita mudanças para não criar duas
verdades diferentes.

Nota técnica para DevOps: o quorum depende da maioria dos managers Raft. Um
Swarm de manager único não possui tolerância à perda desse nó.

### Certificado sem o endereço `www`

Para iniciantes: o cadeado pode reconhecer o domínio principal, mas não o
endereço iniciado por `www`. DNS, rota e certificado são verificações
diferentes.

Nota técnica para DevOps: confirme resolução DNS, regra do proxy e cobertura do
hostname no SAN do certificado antes de atribuir a falha apenas ao SSL.

### Rollback da imagem

Para iniciantes: voltar para a versão anterior do aplicativo não significa
voltar o banco de dados ao estado anterior.

Nota técnica para DevOps: mudanças stateful, como migrations, exigem backup
consistente e restauração testada. O rollback do serviço cobre a imagem e a
configuração declarada, não desfaz automaticamente dados persistentes.

## Como escrever testes para alunos

Cada teste deve responder quatro perguntas:

1. O que devo fazer?
2. O que devo ver quando estiver correto?
3. O que indica que algo deu errado?
4. Posso repetir ou desfazer esse teste sem perder dados?

Comandos isolados sem explicação não formam um tutorial. Logs e hashes devem
ser mostrados como evidências e acompanhados do significado prático.

## Como transformar documentação em aula

Uma aula curta pode seguir este roteiro:

1. apresente uma situação real do aluno;
2. mostre o resultado antes de explicar todos os detalhes;
3. desenhe o modelo mental dos componentes;
4. execute uma demonstração em ambiente fictício ou de homologação;
5. mostre um erro comum e como reconhecê-lo;
6. termine com segurança, limites e forma de rollback;
7. ofereça a nota técnica como aprofundamento opcional.

## Limites editoriais e de segurança

- Não tratar o Setup MNO como substituto de conhecimento, backup ou revisão
  humana.
- Não prometer alta disponibilidade em um Swarm com apenas um manager.
- Não chamar um serviço de seguro apenas porque o container está rodando.
- Não publicar credenciais, tokens, e-mails, IPs, domínios ou dados de clientes.
- Não apresentar uma funcionalidade em `draft` como se estivesse disponível.
- Não esconder limitações para tornar o conteúdo comercialmente mais atraente.

## Publicação futura no Help

O Help deve adotar leitura progressiva: resumo curto, passo a passo, resultado
esperado, erros comuns e uma área expansível com os detalhes técnicos. GIFs e
vídeos devem usar dados fictícios, legenda e alternativa em texto. A publicação
continua sendo uma etapa editorial separada; este arquivo não é copiado
automaticamente para o Control Center.
