---
{
  "schemaVersion": 1,
  "documentId": "setup-mysql-overview",
  "documentVersion": "1.2.0",
  "contentSHA256": "1fd9869ffc661eb781dbaafc6fb20c5a9c98fe035d86b43db5d845e985d046a8",
  "documentType": "setup",
  "title": "MySQL baseado em Percona Server no Setup MNO",
  "setupId": "mysql",
  "setupVersion": "7.8.2",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-09",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["mysql", "percona-server", "sql", "banco-de-dados", "xtrabackup"],
  "sources": [
    {"sourceId":"mysql-installer","title":"Instalador MySQL","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/mysql.sh","license":"project-internal","verifiedAt":"2026-08-09"},
    {"sourceId":"percona-upgrade","title":"Upgrade oficial do Percona Server 8.0","sourceType":"official-documentation","location":"https://docs.percona.com/percona-server/8.0/upgrade-percona-repos.html","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"percona-xtrabackup","title":"Percona XtraBackup 8.0 em Docker","sourceType":"official-documentation","location":"https://docs.percona.com/percona-xtrabackup/8.0/docker.html","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# MySQL baseado em Percona Server no Setup MNO

## Quando usar

Use para aplicações compatíveis com MySQL quando banco relacional for a escolha
correta. A entrada se chama MySQL, mas o instalador distribui Percona Server 8.0;
essa diferença deve ser considerada em suporte, plugins, backup e atualização.

## Arquitetura no Setup MNO

O instalador cria um serviço compartilhado da série 8.0 do Percona Server,
volume de dados e conexão apenas pelas redes Docker. Define root password,
UTF-8, pacote máximo e opções legadas de autenticação, além de esvaziar o SQL
mode. Não publica 3306 e não cria usuário de aplicação.

Os instaladores consumidores verificam o serviço exato `mysql_mysql`, recuperam
a credencial já gerada e aguardam por até 15 minutos uma consulta autenticada
`SELECT 1`. Só depois criam o banco de forma idempotente e continuam o deploy.
Isso evita confundir MySQL 8.0 com `mysql84` e impede que a mera existência do
container seja tratada como banco pronto.

Durante essa espera, o Whiptail mantém uma barra de progresso visível e informa
se o instalador ainda aguarda o serviço, a autenticação ou se o banco já está
pronto. O gauge encerra antes da criação do schema e preserva no shell principal
o container e a credencial recuperados pelo gate.

## Pré-requisitos

Exige disco confiável, RAM, IOPS, política de backup e compatibilidade da
aplicação com Percona Server 8.0. Defina database, charset, collation, SQL mode,
usuário e privilégios por aplicação antes de integrá-la.

## Fluxo seguro

O Instalador Seguro coleta a senha root e modo Portainer ou Docker. A validação
de readiness usa a credencial dentro do container, sem colocá-la nos argumentos
de `docker exec`. Depois da subida, crie usuários de menor privilégio e não
compartilhe root. Revise a necessidade de `mysql_native_password` e SQL mode
vazio; ambos reduzem controles modernos e podem mascarar erros de dados.

## Primeiro acesso e integrações

Conecte somente pela rede interna, crie banco e usuário de teste, valide charset,
transação, índice e limites. Cada aplicação deve receber credencial e schema
próprios, sem acessar bancos vizinhos.

## Backup e atualização

Use dump consistente ou Percona XtraBackup compatível com a mesma série,
preserve configurações e teste restauração isolada. A tag 8.0 acompanha releases
da série; registre a versão efetiva, faça backup integral e leia as notas antes
de atualizar.

## Validação

Confirme saúde, autenticação, privilégios, persistência, charset, SQL mode,
backup, restauração e ausência de porta publicada. Simule inicialização lenta,
confirme que nenhum banco é criado antes de `SELECT 1`, repita a criação para
validar idempotência e reinicie o serviço para provar persistência.

## Riscos e limites

O nome do catálogo pode levar o usuário a presumir Oracle MySQL. SQL mode vazio,
autenticação legada, root como única conta e ausência de healthcheck exigem
correção operacional antes de produção. Uma réplica não oferece alta
disponibilidade.

## Diagnóstico

Separe processo, storage, conexão, autenticação, privilégio, charset, SQL mode,
lock e consulta. Não exponha senha, DSN, dump, linha de cliente ou dados de
tabela ao Assistente.
