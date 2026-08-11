---
{
  "schemaVersion": 1,
  "documentId": "setup-gitea-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "18b7355483d354519236bf1bde25ca3f1b53ad42d73786c36b093169fdf678bd",
  "documentType": "setup",
  "title": "Gitea no Setup MNO",
  "setupId": "gitea",
  "setupVersion": "7.12.1",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["gitea", "git", "repositorio", "sqlite", "devops"],
  "sources": [
    {"sourceId":"gitea-installer","title":"Instalador Gitea","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/gitea.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"gitea-docker","title":"Installation with Docker","sourceType":"official-documentation","location":"https://docs.gitea.com/installation/install-with-docker","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"gitea-backup","title":"Backup and Restore","sourceType":"official-documentation","location":"https://docs.gitea.com/usage/backup-and-restore","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"gitea-upgrade","title":"Upgrade from an old Gitea","sourceType":"official-documentation","location":"https://docs.gitea.com/installation/upgrade-from-gitea","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# Gitea no Setup MNO

## Quando usar

Use para hospedar repositórios Git de equipes pequenas ou médias com interface
leve, issues e colaboração. Não substitui sozinho um plano de CI, registry,
backup externo ou alta disponibilidade. Compare com GitLab quando a prioridade
for uma plataforma DevOps integrada e houver recursos maiores.

## Arquitetura no Setup MNO

O instalador cria uma instância única, dois volumes persistentes, rota web e
acesso Git por SSH. A distribuição atual usa SQLite, tag móvel e permite novos
cadastros. Essa combinação facilita o início, mas exige decisão humana antes de
uso público ou concorrente.

## Pré-requisitos

Exige domínio, redes base, volumes, DNS e TLS. Reserve cópia externa para dados,
configuração e repositórios. Defina previamente política de cadastro, contas
administrativas, SSH, atualização e recuperação.

## Fluxo seguro

Use o Instalador Seguro e confirme domínio, modo de implantação e conflito das
portas publicadas. Depois do primeiro acesso, restrinja cadastros se a instância
não for pública, crie administradores individuais e revise webhooks e chaves.

## Primeiro acesso e integrações

Crie um repositório descartável, valide clone por HTTPS e SSH, push, issue e
webhook. Integre runners, CI ou autenticação externa somente com credenciais de
menor privilégio e destino explícito.

## Backup, atualização e rollback

O backup precisa incluir todo o volume de dados e a configuração. A restauração
Docker é manual e pode exigir ajuste de permissões e regeneração de hooks. Antes
de trocar a imagem, preserve snapshot consistente e mantenha a versão anterior
disponível; voltar somente a imagem não reverte migrações.

## Validação

Valide persistência após reinício controlado, clone, push, autenticação, URL
externa, webhook e restauração de um repositório descartável.

## Diagnóstico

Separe DNS e TLS, proxy, aplicação, SQLite, volume, permissões e SSH. Consulte
logs sanitizados e nunca envie chaves privadas, tokens, repositórios ou arquivo
de configuração ao Assistente.

## Riscos e limites

Tags móveis, cadastro aberto, SQLite sob concorrência e portas publicadas são
riscos da distribuição atual. Não recomende alta disponibilidade nem migração
automática para outro banco sem projeto e homologação.
