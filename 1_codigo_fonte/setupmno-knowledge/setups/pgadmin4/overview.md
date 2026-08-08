---
{
  "schemaVersion": 1,
  "documentId": "setup-pgadmin4-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "eab4c33b980856aa14f3e13362ce6dbd337784b023860ba82cc42dcff1171be2",
  "documentType": "setup",
  "title": "pgAdmin 4 no Setup MNO",
  "setupId": "pgadmin4",
  "setupVersion": "7.7.35",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["pgadmin4", "postgresql", "administracao", "banco-de-dados", "backup"],
  "sources": [
    {"sourceId":"pgadmin4-installer","title":"Instalador pgAdmin 4","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/pgadmin.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"pgadmin4-container","title":"Deployment oficial do pgAdmin 4 em container","sourceType":"official-documentation","location":"https://www.pgadmin.org/docs/pgadmin4/latest/container_deployment.html","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"pgadmin4-backup","title":"Backup e restore no pgAdmin 4","sourceType":"official-documentation","location":"https://www.pgadmin.org/docs/pgadmin4/development/backup_and_restore.html","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# pgAdmin 4 no Setup MNO

## Quando usar

Use como interface administrativa para PostgreSQL por operadores autorizados.
Não é banco de dados e não substitui backup automatizado, monitoramento,
controle de mudanças nem contas de menor privilégio.

## Arquitetura no Setup MNO

O instalador cria uma réplica com a tag móvel do pgAdmin 4, volume persistente em
`/var/lib/pgadmin`, limite de 1 GB e rota web interna 80. A conta inicial é
coletada e a proteção reforçada de cookie é habilitada. O serviço alcança as
redes interna e externa.

## Pré-requisitos

Exige domínio administrativo, MFA ou controle de acesso adicional quando
disponível, conta PostgreSQL própria para cada operador e política de retenção
dos arquivos exportados. Não use superusuário para tarefas rotineiras.

## Fluxo seguro

O Instalador Seguro coleta domínio, e-mail, senha e modo Portainer ou Docker.
Depois, restrinja a rota a operadores, não salve senhas desnecessariamente e
fixe uma versão do container. Arquivos de backup baixados pelo navegador também
precisam de proteção e descarte.

## Primeiro acesso e integrações

Cadastre o PostgreSQL base pelo hostname interno, preferencialmente com usuário
de leitura ou administração limitada. Teste conexão, query sem dados sensíveis e
expiração de sessão. Não exponha a porta do banco para facilitar o pgAdmin.

## Backup e atualização

O volume preserva contas, sessões, preferências e arquivos do pgAdmin; backups
dos bancos são artefatos separados produzidos por `pg_dump`, `pg_dumpall` ou
ferramentas equivalentes. A documentação alerta que migrações do banco interno
são progressivas; fixe a tag, preserve o volume e teste restauração antes de
atualizar.

## Validação

Confirme login, cookie seguro, conexão interna com privilégio mínimo, execução
de query controlada, geração e restauração de backup de teste e persistência das
configurações. Valide que a rota não é pública sem proteção adequada.

## Riscos e limites

É uma superfície administrativa de alto impacto. Tag `latest`, acesso às duas
redes e armazenamento de conexões elevam o risco. Backup criado pela interface
só é válido depois de uma restauração testada.

## Diagnóstico

Separe rota, login do pgAdmin, volume, DNS interno, autenticação PostgreSQL,
privilégio e versão das ferramentas cliente. Não envie senha, `.pgpass`, dump,
query com dados reais ou string de conexão ao Assistente.
