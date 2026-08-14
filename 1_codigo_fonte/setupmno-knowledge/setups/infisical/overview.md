---
{
  "schemaVersion": 1,
  "documentId": "setup-infisical-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "d55e88aa71fe5cc1651ec90f1263bee3b5d12012467aeea6246f9f237308edd4",
  "documentType": "setup",
  "title": "Infisical no Setup MNO",
  "setupId": "infisical",
  "setupVersion": "7.17.1",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": ["infisical", "secrets", "seguranca", "devops", "credenciais"],
  "sources": [
    {"sourceId":"infisical-installer","title":"Instalador Infisical","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/infisical.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"infisical-compose","title":"Deploy oficial com Docker Compose","sourceType":"official-documentation","location":"https://infisical.com/docs/self-hosting/deployment-options/docker-compose","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"infisical-requirements","title":"Requisitos de hardware do Infisical","sourceType":"official-documentation","location":"https://infisical.com/docs/self-hosting/configuration/requirements","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"infisical-overview","title":"Visão geral self-hosted do Infisical","sourceType":"official-documentation","location":"https://infisical.com/docs/self-hosting/overview","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# Infisical no Setup MNO

## Quando usar

Use para centralizar secrets, identidades de máquina, ambientes e auditoria de
acesso. Não instale apenas para guardar senhas manualmente sem definir donos,
políticas, rotação, recuperação e um caminho de emergência fora da plataforma.

## Arquitetura no Setup MNO

O script usa PostgreSQL compartilhado, Redis dedicado e uma réplica Infisical
com tag `latest`. Publica 8088 no host e também cria rota HTTPS. O Redis está
limitado a 256 MB com política `allkeys-lru`; a documentação oficial recomenda
`noeviction`. O catálogo informa cerca de 512 MB, enquanto a referência oficial
parte de 4 GB para o conjunto mínimo e mais em produção.

## Pré-requisitos

Exige PostgreSQL compatível, Redis 6.2 ou 7 em modo standalone, TLS, SMTP para
recuperação, backup externo e controle estrito do primeiro cadastro. Confirme
CPU, RAM e disco considerando aplicação, banco, cache e logs de auditoria.

## Fluxo seguro

Não use a implantação atual em produção. Fixe versões, remova a porta pública,
troque a política do Redis, dimensione recursos e mantenha chaves criptográficas
em Docker Secrets ou mecanismo equivalente. O primeiro usuário deve ser criado
por operador autorizado antes da exposição a terceiros.

## Primeiro acesso e integrações

Após correções, crie a conta administrativa, desative cadastro aberto, configure
SMTP e separe organizações, projetos, ambientes e identidades. Aplicações devem
receber somente o secret de que precisam; nunca compartilhe credencial root.

## Backup, atualização e rollback

O PostgreSQL contém secrets criptografados, usuários, projetos e configuração e
é o ativo crítico. Faça `pg_dump`, preserve as chaves de criptografia em cofre
separado e teste restauração conjunta. Atualize por versão fixada, com backup e
imagem anterior disponíveis.

## Validação

Valide status da aplicação, banco, Redis, login, recuperação, auditoria, rotação
e uma identidade de máquina de teste.

## Diagnóstico

Separe falha de chave, conexão, migração, cache, SMTP e permissão. Nunca envie
secrets, tokens ou material criptográfico ao Assistente.

## Riscos e limites

Risco crítico por subdimensionamento, tag móvel, porta do host, política de
evicção incompatível e secrets interpolados em YAML. Como o próprio gerenciador
protege as credenciais das demais aplicações, sua recuperação precisa ser
homologada antes de qualquer adoção real.
