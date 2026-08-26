# Fronteira de proteção SHC e módulos externos verificados

- Versão planejada: `7.33.5`
- Versão entregue: `7.33.5` candidata
- Estado: `implemented`
- Maturidade da funcionalidade: `beta`
- Atualizado em: 25/08/2026
- Responsável: mantenedor PRO MASTER
- Ambientes: VPS Debian/Ubuntu e WSL2
- Arquiteturas: AMD64 e ARM64
- Planos afetados: todos

## Para iniciantes — o que isso resolve

O Setup MNO deixa de colocar todo código novo dentro do grande executável SHC.
O SHC continua protegendo os gatilhos, o instalador, os scripts das aplicações e
o núcleo inicial. Novos motores auxiliares, como os futuros Trivy, Lynis e
Docker Bench do SRE-3, ficam em arquivos separados e legíveis, mas somente são
aceitos quando tamanho, nome e impressão digital SHA-256 correspondem ao pacote
oficial.

Isso reduz o risco de ultrapassar o limite técnico do SHC e facilita manutenção
e auditoria. Não transforma Bash em segredo impossível de copiar e não protege
uma máquina já dominada por um invasor com acesso root.

## Modelo mental ou analogia

O SHC passa a ser o lacre da caixa, não a caixa inteira. Dentro dela existem
peças identificadas por uma lista de conferência. Se uma peça ou a própria lista
for trocada depois que o lacre foi produzido, o instalador recusa o pacote. A
analogia termina aí: hashes detectam alteração, mas não escondem o conteúdo dos
módulos externos.

## Objetivo e critérios de sucesso

- Objetivo: congelar uma fronteira pequena e explícita para o SHC antes do
  SRE-3, mantendo módulos auxiliares fora da compilação monolítica.
- Evidência esperada: fronteira igual em x86 e ARM, inventário completo do
  pacote, hash do `release.json` embutido no gatilho protegido e rejeição de
  adulterações.
- Condição de falha: entrada SHC não classificada, módulo SRE dentro do SHC,
  arquivo ausente, symlink, hash/tamanho divergente ou manifesto substituído.

## O que mudou e o que permaneceu igual

Mudou:

- existe uma política canônica que classifica núcleo, aplicações legadas e
  módulos externos;
- cada `.control-package` recebe `protection-boundary.json` com caminho,
  tamanho, escopo e SHA-256 de cada arquivo externo;
- `release.json` referencia esse inventário;
- o hash exato de `release.json` é gravado nos gatilhos x86 e ARM antes da
  compilação SHC;
- o runtime valida a cadeia completa antes da promoção atômica.

Permaneceu igual:

- `start_full.sh`, `start_arm_full.sh`, `install.sh`, scripts das aplicações e
  núcleo inicial continuam protegidos por SHC;
- planos, autenticação, expiração de sete dias e seleção de arquivos por plano
  não foram afrouxados;
- nenhum módulo recebe root, Docker socket ou permissão de execução apenas por
  estar inventariado;
- SRE-3 continua pendente e BETA; esta etapa não instala Trivy, Lynis ou Docker
  Bench.

## Jornada do usuário

1. O usuário executa o bootstrap oficial como antes.
2. O gatilho protegido recebe o pacote correspondente à arquitetura.
3. Antes de promover o Control Center, o gatilho confere o lacre do release e
   cada módulo externo.
4. Pacote válido continua normalmente, sem uma nova pergunta.
5. Pacote alterado para com mensagem de estado runtime inválido e não substitui
   a cópia válida anterior.

## Visibilidade da maturidade

- a política e o manifesto declaram `maturity: beta`;
- a nota da candidata identifica a preparação como BETA;
- não há novo botão ou promessa de SRE-3 disponível;
- a promoção para estável exige homologação em WSL2, VPS AMD64 e VPS ARM64 e
  declaração explícita de Francis MNO.

## Como funciona por dentro — nota técnica para DevOps

SHC (Shell Script Compiler) gera um executável C a partir de um script Bash. Ele
é usado como camada de distribuição e expiração, não como criptografia perfeita.
SHA-256 é uma função de hash que produz uma impressão digital de 64 caracteres;
qualquer mudança no arquivo muda essa impressão.

`shc_boundary.py audit` obtém os instaladores canônicos do registro de setups,
compara as entradas `shc -f` de AMD64 e ARM64 e bloqueia padrões reservados ao
SRE-3. `generate` cria um inventário determinístico de arquivos regulares. Em
seguida, o gerador escreve os dados do inventário no release e `bind` grava o
SHA-256 desse release no `start_full.sh` ou `start_arm_full.sh`. Como o gatilho é
compilado depois pelo empacotador, o release não pode ser recalculado por fora
sem invalidar a âncora protegida.

Na instalação, a validação ocorre em quatro níveis: âncora do release, metadados
do inventário, conjunto exato de caminhos e hash/tamanho de cada artefato. O
diretório é promovido com arquivos temporários e `mv`, preservando o
comportamento fail closed: falhar fechado significa negar a atualização quando
não é possível comprovar sua integridade.

## Arquitetura e dados

- Fonte da política: `setupmno-control/shc-boundary-policy.json`.
- Gate e gerador: `setupmno-control/shc_boundary.py`.
- Manifesto distribuído: `.control-package/protection-boundary.json`.
- Âncora: `EXPECTED_CONTROL_RELEASE_SHA256` dentro do gatilho SHC.
- Destino promovido: `/root/SetupLowCodeMno/.control/`.
- Não cria rede, porta, volume, secret nem coleta dado pessoal.
- O inventário do pacote recebido descreve também artefatos PRO MASTER; a
  filtragem por plano continua removendo do runtime vivo o que o plano não pode
  usar.

## Permissões e planos

A verificação é obrigatória para todos os planos. Ela não concede recursos PRO
ou PRO MASTER e não substitui as autorizações existentes no backend, agente,
terminal e instalador. Estado ausente ou divergente é negado.

## Gates

- sintaxe Bash e Python;
- política idêntica para AMD64 e ARM64;
- limite de 120 KiB para scripts que entram no SHC;
- proibição explícita de `trivy*`, `lynis*`, `docker-bench*` e `sre-*` no SHC;
- inventário sem symlinks, caminhos absolutos, `..` ou duplicatas;
- teste de arquivo alterado;
- teste de arquivo, inventário e release alterados em conjunto;
- smoke test real do executável SHC;
- promoção por plano e rollback do runtime;
- empacotamento ZIP e conferência da distribuição.

## Segurança e privacidade

O desenho melhora integridade e manutenção. Ele não promete confidencialidade
para módulos externos, não impede engenharia reversa do SHC e não resiste a um
administrador root que modifique simultaneamente o executável já instalado e o
restante do host. Nenhuma credencial entra nos manifestos ou nos logs do gate.

## Rollback

O rollback de código é restaurar os arquivos da release estável anterior `v7.33.4`, gerar
novamente os instaladores e empacotar. No runtime, uma promoção inválida não
remove a cópia válida de `.control`; o pacote candidato é rejeitado antes da
substituição. Esse rollback não altera volumes, bancos, stacks ou dados das
aplicações.

## FAQ e falhas conhecidas

- **Os módulos externos estão criptografados?** Não. Estão legíveis e têm
  integridade verificada.
- **Uma nova aplicação deixa de usar SHC?** Não. Uma aplicação adicionada ao
  catálogo canônico deve continuar entrando no monólito e o gate bloqueia a
  release se ela não estiver nos dois gatilhos.
- **O SRE-3 já está funcionando?** Não. A fronteira apenas deixa o lugar seguro
  para seus motores determinísticos.
- **Por que não assinar tudo apenas com outro JSON?** Porque um invasor poderia
  recalcular os dois JSONs. A âncora do release fica no gatilho compilado.

## Como testar no WSL2 e na VPS

Pré-requisitos: checkout limpo, Bash, Python 3, `jq`, `shc`, `tar` e Docker para
os gates completos.

```bash
bash 1_codigo_fonte/setupmno-control/shc-boundary_test.sh
python3 -B 1_codigo_fonte/setupmno-control/shc_boundary.py audit \
  --source-root 1_codigo_fonte \
  --policy 1_codigo_fonte/setupmno-control/shc-boundary-policy.json
```

Resultado esperado: mensagens de aprovação e `177` entradas SHC por
arquitetura. Sinal de falha: `ERRO`, diferença entre arquiteturas, arquivo não
classificado ou módulo adulterado aceito. Os testes criam apenas diretórios
temporários em `/tmp` e os removem ao terminar.

Para validar a release completa em WSL2 e VPS:

```bash
./1_codigo_fonte/setupmno-control/generate-installers.sh
./2_empacotador/gerar_distribuicao.sh
```

O resultado esperado é a geração dos dois instaladores e dos ZIPs sem alterar
stacks, volumes ou a instalação de referência. Uma falha deve interromper o
empacotamento e indicar o gate responsável.

## Glossário mínimo

- SHC: compilador usado para distribuir e expirar scripts Bash.
- Hash SHA-256: impressão digital usada para detectar mudança em arquivo.
- Âncora de confiança: valor pequeno protegido que permite validar o restante.
- Manifesto: lista versionada dos arquivos e de suas impressões digitais.
- Fail closed: negar a operação quando a validação não consegue provar que é
  segura.

## Como ensinar esta feature

Explique para a comunidade: “o coração e os instaladores continuam no cofre;
as novas ferramentas auxiliares ficam em gavetas transparentes, mas cada gaveta
tem lacre conferido pelo cofre”. Demonstre alterando uma cópia temporária de um
módulo e mostrando que o gate recusa. Corrija a ideia de que SHC torna o código
impossível de recuperar e nunca omita que root controla a máquina.

## Publicação futura no Help

A analogia, o FAQ e o significado de “pacote alterado” podem virar um artigo
curto. A política completa e os caminhos internos não devem ser copiados
automaticamente para o Help.
