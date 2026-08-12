---
{
  "schemaVersion": 1,
  "documentId": "setup-mongodb-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "b0bb195d1a9374d40a20c0174991a488d02dc080e1df6bef022a54e755a6f5ac",
  "documentType": "setup",
  "title": "MongoDB no Setup MNO",
  "setupId": "mongodb",
  "setupVersion": "7.14.4",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["mongodb", "nosql", "documentos", "banco-de-dados", "backup"],
  "sources": [
    {"sourceId":"mongodb-installer","title":"Instalador MongoDB","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/mongodb.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"mongodb-docker","title":"MongoDB Community com Docker","sourceType":"official-documentation","location":"https://www.mongodb.com/docs/v7.0/tutorial/install-mongodb-community-with-docker/","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"mongodb-auth","title":"Autenticação em deployments autogerenciados","sourceType":"official-documentation","location":"https://www.mongodb.com/docs/manual/core/authentication/","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"mongodb-backup","title":"Backup de deployments autogerenciados","sourceType":"official-documentation","location":"https://www.mongodb.com/docs/manual/core/backups/","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# MongoDB no Setup MNO

## Quando usar

Use quando o modelo de documentos e os padrões de consulta justificarem um
banco MongoDB. Não escolha apenas por flexibilidade: índices, consistência,
transações, crescimento e recuperação precisam de desenho explícito.

## Arquitetura no Setup MNO

O instalador cria uma réplica única `mongo:latest`, sem porta publicada, com
volumes externos para dados, configuração e dump e limite de 2 GB. Cria somente
o usuário root inicial. Não configura replica set, TLS, healthcheck ou usuário
específico de aplicação.

## Pré-requisitos

Exige storage compatível com persistência e `fsync`, RAM e disco dimensionados,
política de backup e usuário por aplicação. Verifique AVX e suporte da versão da
imagem quando o host for antigo. Clientes devem alcançar apenas a rede interna.

## Fluxo seguro

O Instalador Seguro coleta nome, usuário, senha e modo Portainer ou Docker. Após
o deploy, crie banco e usuário de menor privilégio; não entregue a conta root à
aplicação. Fixe versão, habilite TLS se sair da rede interna e avalie replica set
para produção.

## Primeiro acesso e integrações

Conecte com `mongosh` por caminho interno autorizado, crie coleção de teste,
índice e usuário restrito e valide leitura e escrita. Aplicações recebem URI
própria sem publicar 27017 na internet.

## Backup e atualização

Defina `mongodump` e `mongorestore`, snapshot consistente ou ferramenta de
gestão conforme RPO e escala. Teste restauração em volume isolado. Trocar
`latest` pode atravessar versão maior; fixe a release e siga a matriz oficial de
upgrade antes de substituir a imagem.

## Validação

Confirme autenticação, autorização, persistência, índices, limite de disco,
backup e restauração. Valide também que 27017 não está publicada e que uma
aplicação não consegue acessar bancos alheios.

## Riscos e limites

Uma única réplica é ponto único de falha. Tag móvel, conta root como única conta,
ausência de TLS e de healthcheck impedem classificação como produção
homologada. O volume de dump vazio não constitui backup automático.

## Diagnóstico

Separe processo, storage, autenticação, autorização, seleção de banco, índice,
memória e cliente. Use erros sanitizados e métricas agregadas; nunca envie URI,
senha, documento real ou dump ao Assistente.
