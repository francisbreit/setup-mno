---
{
  "schemaVersion": 1,
  "documentId": "setup-gitlab-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "3643d289d59c06b50f56883f1ea469ea2f7ab2982b181bee259e7e5dd3face97",
  "documentType": "setup",
  "title": "GitLab no Setup MNO",
  "setupId": "gitlab",
  "setupVersion": "7.7.16",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": ["gitlab", "git", "devops", "ci", "backup"],
  "sources": [
    {"sourceId":"gitlab-installer","title":"Instalador GitLab","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/gitlab.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"gitlab-docker","title":"Install GitLab in a Docker container","sourceType":"official-documentation","location":"https://docs.gitlab.com/install/docker/installation/","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"gitlab-requirements","title":"GitLab installation requirements","sourceType":"official-documentation","location":"https://docs.gitlab.com/install/requirements/","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"gitlab-backup","title":"Back up GitLab","sourceType":"official-documentation","location":"https://docs.gitlab.com/administration/backup_restore/backup_gitlab/","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# GitLab no Setup MNO

## Quando usar

Use quando repositórios, revisão, CI/CD e governança DevOps precisam estar na
mesma plataforma. Para hospedagem Git leve, Gitea demanda menos recursos. O
GitLab exige operação, capacidade e recuperação compatíveis com um sistema
crítico de engenharia.

## Arquitetura no Setup MNO

O instalador distribui GitLab Community Edition em serviço único com volumes de
configuração, logs e dados, atrás do proxy. A imagem usa tag móvel e o limite de
memória do script está abaixo do baseline oficial atual para instalação única.

## Pré-requisitos

Exige hostname externo válido, TLS, armazenamento rápido, CPU e memória
dimensionados pela documentação oficial, além de serviço de email separado
quando necessário. O suporte oficial alerta sobre limitações do Docker for
Windows; WSL2 precisa de homologação específica antes de produção.

## Fluxo seguro

Execute somente pelo Instalador Seguro após revisar capacidade. Fixe uma versão
antes de produção, preserve os três volumes e planeje SSH, registry e email
separadamente. Não interprete o limite atual do catálogo como recomendação de
dimensionamento.

## Primeiro acesso e integrações

Recupere a credencial inicial pelos meios documentados, troque-a, habilite MFA e
crie projetos descartáveis para testar clone, push, pipeline e webhook. Runners
e registry têm superfície e recursos próprios.

## Backup, atualização e rollback

O backup oficial não substitui cópia de configuração, secrets e dados externos.
A restauração exige exatamente a mesma versão e edição. Antes de atualizar,
gere backup verificável, preserve configuração e secrets, leia a rota oficial
entre versões e teste a restauração isoladamente.

## Validação

Valide saúde, login, projeto, push, pipeline, persistência, email se usado e
restauração de um backup descartável na mesma versão.

## Diagnóstico

Separe proxy, Omnibus, PostgreSQL interno, Redis interno, Gitaly, Sidekiq,
armazenamento e runners. Sanitizar logs é obrigatório; não envie repositórios,
tokens, variáveis de CI ou arquivo de secrets ao Assistente.

## Riscos e limites

Há bloqueio de recomendação de produção enquanto a tag permanecer móvel e a
capacidade distribuída não atender ao requisito oficial. Registry, Pages, alta
disponibilidade e runners não são entregues automaticamente por este setup.
