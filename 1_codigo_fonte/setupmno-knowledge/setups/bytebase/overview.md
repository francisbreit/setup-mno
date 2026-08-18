---
{
  "schemaVersion": 1,
  "documentId": "setup-bytebase-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "96bd10dba83b6a4b121070ced2c1d77f29049aeab25f429b1d48675fa084da74",
  "documentType": "setup",
  "title": "Bytebase no Setup MNO",
  "setupId": "bytebase",
  "setupVersion": "7.22.0",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-14",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["bytebase", "database-devops", "sql-review", "schema", "governanca", "postgresql"],
  "sources": [
    {"sourceId":"bytebase-installer","title":"Instalador Bytebase","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/bytebase.sh","license":"project-internal","verifiedAt":"2026-08-14"},
    {"sourceId":"bytebase-docker","title":"Deploy oficial do Bytebase com Docker","sourceType":"official-documentation","location":"https://docs.bytebase.com/get-started/self-host/deploy-with-docker","license":"documentation-reference","verifiedAt":"2026-08-14"},
    {"sourceId":"bytebase-postgres","title":"PostgreSQL externo no Bytebase","sourceType":"official-documentation","location":"https://docs.bytebase.com/get-started/self-host/external-postgres","license":"documentation-reference","verifiedAt":"2026-08-14"},
    {"sourceId":"bytebase-production","title":"Requisitos de produção do Bytebase","sourceType":"official-documentation","location":"https://docs.bytebase.com/get-started/self-host/production-setup","license":"documentation-reference","verifiedAt":"2026-08-14"},
    {"sourceId":"bytebase-release","title":"Bytebase 3.21.0","sourceType":"official-documentation","location":"https://github.com/bytebase/bytebase/releases/tag/3.21.0","license":"documentation-reference","verifiedAt":"2026-08-14"}
  ],
  "homologation": {
    "verifiedAt": "2026-08-14",
    "verifiedPorts": [8080],
    "verifiedImages": [
      "bytebase/bytebase:3.21.0@sha256:ce51be31aba8213ed583479b46f38a6dc295fd1cd009aabe9bbe18de3daa7588"
    ]
  }
}
---
# Bytebase no Setup MNO

## Quando usar

Use o Bytebase para centralizar mudanças de esquema, revisão de SQL, consultas,
auditoria e governança de bancos de dados. Ele é indicado para equipes que
precisam substituir alterações manuais sem rastreabilidade por um fluxo
controlado entre desenvolvedores, revisores e administradores.

O produto gerencia conexões com bancos cadastrados pelo operador; ele não
substitui esses bancos nem migra aplicações automaticamente. Recursos
avançados podem depender da edição comercial do Bytebase, portanto confirme o
plano e a licença do recurso antes de incluí-lo em um processo obrigatório.

## Arquitetura no Setup MNO

O instalador publica um serviço Bytebase 3.21.0 em Docker Swarm e reutiliza o
PostgreSQL compartilhado nativo do Setup MNO somente para os metadados internos
do Bytebase. Um banco UTF-8 exclusivo, com nome aleatório da instalação, é
criado depois que o PostgreSQL confirma prontidão. As instâncias de banco que o
usuário deseja governar são cadastradas posteriormente no painel.

A imagem oficial é fixada por versão e digest multi-arquitetura. O container
usa filesystem raiz somente leitura, remove todas as capabilities Linux,
reserva `/tmp` em memória e grava apenas no diretório persistente exclusivo. A
porta 8080 permanece nas redes internas do Swarm; o acesso público ocorre pelo
Traefik ou pelo Cloudflare Tunnel, nunca por uma porta publicada no host.

## Pré-requisitos e capacidade

Exige Docker Swarm ativo, redes `externa` e `interna`, PostgreSQL compartilhado
saudável e credenciais válidas para o modo de exposição selecionado. O perfil
entregue limita o Bytebase a um CPU e 2 GB de RAM, alinhado ao ponto inicial
oficial para equipes pequenas. Bancos gerenciados, agentes, consultas
concorrentes e volume de auditoria podem exigir mais recursos.

O PostgreSQL externo suportado pelo produto deve ser versão 14 ou superior e o
banco de metadados precisa usar UTF-8. O instalador valida a prontidão antes de
criar o banco, evitando a corrida de inicialização que faria o Bytebase encerrar
sem concluir as migrações.

## Fluxo seguro

A conta administrativa é criada no primeiro acesso pelo navegador; o
instalador não define usuário ou senha padrão. Use identidade individual,
privilégio mínimo e, quando disponível no plano, políticas de aprovação e
integração com um provedor de identidade. Proteja o domínio com Cloudflare
Access quando o painel não precisar ser público.

Credenciais dos bancos cadastrados no Bytebase têm alto impacto. Crie contas
dedicadas por instância, restrinja rede e permissões e evite reutilizar o
superusuário em rotinas diárias. Não inclua tokens, senhas ou strings de conexão
em tickets, capturas de tela e logs de suporte.

## Riscos e limites

O perfil entregue possui uma única réplica e não representa alta
disponibilidade. O PostgreSQL compartilhado reduz duplicação operacional, mas
continua sendo uma dependência crítica: indisponibilidade, saturação ou perda
desse serviço afeta também os metadados do Bytebase. Monitore capacidade e
mantenha backups separados por banco.

O Bytebase pode executar consultas e mudanças nos bancos cadastrados conforme
as credenciais concedidas. Uma política mal configurada ou uma conta com
privilégios excessivos amplia o impacto de erro humano. Comece com instâncias de
teste, aprovação obrigatória e acesso mínimo antes de conectar produção.

## Validação homologada

A homologação isolada no WSL2 com Docker Desktop confirmou manifesto amd64 e
arm64, PostgreSQL externo temporário, réplica 1/1, endpoint interno `/healthz`
com resposta `OK`, interface HTTP 200, criação de 45 tabelas públicas e
persistência das 45 tabelas após reinício. O teste também confirmou filesystem
raiz somente leitura, capabilities removidas e volume de dados gravável.

O consumo ocioso observado foi próximo de 286 MB no Bytebase e 47 MB no banco
temporário de homologação. O PostgreSQL temporário foi usado somente para
isolar o laboratório; o instalador final conecta ao PostgreSQL compartilhado do
Setup MNO e cria um banco exclusivo.

## Diagnóstico

Se o serviço não alcançar 1/1, consulte as tarefas e os logs do serviço e
confirme a resolução do hostname `postgres` na rede `interna`. Se `/healthz`
falhar, valide primeiro a prontidão do PostgreSQL, a string `PG_URL`, a memória
disponível e as permissões do diretório persistente. Um endpoint saudável sem
acesso externo normalmente aponta para DNS, rota do Tunnel ou labels do
Traefik, não para o processo Bytebase.

O instalador só declara sucesso depois de validar a réplica, `/healthz` e a
existência das tabelas de metadados. A prova HTTP é executada por um serviço
efêmero interno sem porta publicada e é removida tanto no sucesso quanto no
rollback.

## Backup, atualização e rollback

Antes de atualizar, faça backup consistente do banco de metadados e preserve o
diretório persistente exclusivo. As notas oficiais da versão 3.21.0 recomendam
backup dos metadados antes do upgrade e informam que downgrade não é suportado.
Nunca execute duas réplicas usando o mesmo diretório de dados.

Em falha de instalação, o rollback remove somente a stack Bytebase, o banco
exclusivo recém-criado, o YAML e o diretório pertencentes àquela tentativa,
além de restaurar a rota DNS ou Tunnel alterada. Bancos externos cadastrados
para governança não são removidos. Em uma atualização futura, não apague dados
persistentes sem backup testado e plano de restauração.
