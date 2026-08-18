---
{
  "schemaVersion": 1,
  "documentId": "setup-plane-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "0dec7e146fcca40751a5b1bf9cbad3a1ef7311bf57b622e7028ed7de796ec8f0",
  "documentType": "setup",
  "title": "Plane no Setup MNO",
  "setupId": "plane",
  "setupVersion": "7.22.1",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": ["plane", "projetos", "redis", "rabbitmq", "minio"],
  "sources": [
    {"sourceId":"plane-installer","title":"Instalador Plane","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/plane.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"plane-compose","title":"Docker Compose","sourceType":"official-documentation","location":"https://developers.plane.so/self-hosting/methods/docker-compose","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"plane-backup","title":"Backup and restore data","sourceType":"official-documentation","location":"https://developers.plane.so/self-hosting/manage/backup-restore","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"plane-upgrade","title":"Upgrade Plane","sourceType":"official-documentation","location":"https://developers.plane.so/self-hosting/manage/upgrade","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# Plane no Setup MNO

## Quando usar

Use para planejamento de produto, issues, ciclos e colaboração de equipes. Não
é apenas uma aplicação web: a operação envolve banco, fila, cache, storage e
vários serviços. Para listas simples, uma solução menor reduz manutenção.

## Arquitetura no Setup MNO

O instalador compõe Redis e RabbitMQ dedicados, PostgreSQL compartilhado, MinIO
compartilhado ou criado pelo fluxo, três processos backend, três frontends e um
proxy interno. As imagens da aplicação seguem tag estável móvel e secrets ficam
interpolados nos YAMLs.

## Pré-requisitos

Exige domínio, TLS, PostgreSQL, Redis, RabbitMQ, storage S3 compatível, redes e
capacidade superior ao valor simplificado do catálogo. A documentação oficial
parte de pelo menos quatro gigabytes de RAM e recomenda mais para uso real.

## Fluxo seguro

Escolha conscientemente MinIO compartilhado ou isolado, valide buckets e contas
de serviço, e execute pelo Instalador Seguro. Confirme que todas as substacks
foram criadas no modo escolhido; o fluxo atual ainda usa deploy direto para
algumas dependências mesmo quando Portainer foi selecionado.

## Primeiro acesso e integrações

Crie workspace descartável, usuários de teste e um projeto com issue e anexo.
Email, OAuth, webhooks e storage precisam de credenciais separadas e validação
de origem, callback e menor privilégio.

## Backup, atualização e rollback

Backup precisa reunir PostgreSQL, objetos do bucket, configuração e estado das
dependências. O comando oficial de backup se aplica ao método oficial e não
deve ser presumido para esta composição Swarm. Fixe versões, preserve todas as
substacks e ensaie restauração coordenada antes de atualizar.

## Validação

Valide login, workspace, issue, anexo, job assíncrono, email quando usado,
persistência e restauração coordenada de dado descartável.

## Diagnóstico

Separe proxy, API, worker, scheduler, frontends, PostgreSQL, Redis, RabbitMQ e
S3. Não envie tokens, URLs internas, anexos, dump ou YAML com credenciais ao
Assistente.

## Riscos e limites

Complexidade, tags móveis, secrets em YAML, dependências parcialmente fora do
Portainer e capacidade subestimada bloqueiam recomendação automática de
produção. Backup oficial não equivale a backup deste instalador.
