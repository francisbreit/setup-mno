---
{
  "schemaVersion": 1,
  "documentId": "setup-linkwarden-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "a7bb40e6ce95f83ce5ef4a68d378ade3e4910c5c6bac5bfecbf231f1bc1b551c",
  "documentType": "setup",
  "title": "Linkwarden no Setup MNO",
  "setupId": "linkwarden",
  "setupVersion": "7.32.2",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-11",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["linkwarden", "favoritos", "arquivamento", "postgresql", "meilisearch"],
  "sources": [
    {"sourceId":"linkwarden-installer","title":"Instalador Linkwarden","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/linkwarden.sh","license":"project-internal","verifiedAt":"2026-08-10"},
    {"sourceId":"linkwarden-installation","title":"Instalação oficial do Linkwarden","sourceType":"official-documentation","location":"https://docs.linkwarden.app/self-hosting/installation","license":"documentation-reference","verifiedAt":"2026-08-10"},
    {"sourceId":"linkwarden-environment","title":"Variáveis de ambiente oficiais do Linkwarden","sourceType":"official-documentation","location":"https://docs.linkwarden.app/self-hosting/environment-variables","license":"documentation-reference","verifiedAt":"2026-08-10"},
    {"sourceId":"linkwarden-user-content","title":"Domínio isolado de conteúdo do usuário","sourceType":"official-documentation","location":"https://docs.linkwarden.app/self-hosting/user-content-domain","license":"documentation-reference","verifiedAt":"2026-08-10"},
    {"sourceId":"linkwarden-releases","title":"Releases oficiais do Linkwarden","sourceType":"official-documentation","location":"https://github.com/linkwarden/linkwarden/releases","license":"documentation-reference","verifiedAt":"2026-08-10"}
  ],
  "homologation": {
    "verifiedAt": "2026-08-11",
    "verifiedPorts": [],
    "verifiedImages": [
      "ghcr.io/linkwarden/linkwarden:v2.14.1@sha256:31cf4bd2a2e111991fa5c9de03174c8698869c83722105c6ce529e4c911e6861",
      "postgres:16.10-alpine@sha256:029660641a0cfc575b14f336ba448fb8a75fd595d42e1fa316b9fb4378742297",
      "getmeili/meilisearch:v1.12.8@sha256:c9fac23131cca4db95173d41cc50fd5639121ee381795528fdd7522d7978a7b8"
    ]
  }
}
---
# Linkwarden no Setup MNO

## Quando usar

Use o Linkwarden para reunir favoritos, páginas, artigos e documentos em
coleções pesquisáveis e colaborativas. A aplicação preserva conteúdo como
screenshot, PDF e HTML para reduzir o impacto de páginas removidas ou alteradas.

## Arquitetura no Setup MNO

O instalador cria três stacks separadas: PostgreSQL 16, Meilisearch e Linkwarden.
Cada dependência possui dados persistentes, healthcheck e limite de recursos. As
credenciais do banco, da busca e das sessões ficam em Docker Secrets exclusivos;
os valores não entram nos YAMLs, logs ou arquivos de inventário.

## Pré-requisitos

Requer Docker Swarm ativo, redes `interna` e `externa` existentes, dois
domínios HTTPS distintos e, preferencialmente, um host com pelo menos 4 GB de
RAM. O fluxo cria credenciais próprias; não reutiliza banco, índice ou secrets
de outra aplicação.

## Fluxo seguro

São usados dois domínios HTTPS. O domínio principal atende painel e API. O
segundo domínio atende somente `/api/v1/preserved/view`, isolando HTML preservado
e potencialmente não confiável da origem principal. Traefik e Cloudflare Tunnel
bloqueiam essa rota no domínio principal e recusam outras rotas no domínio de
conteúdo.

## Primeiro administrador

O instalador coleta nome, usuário e senha, cria o primeiro administrador pela
rede interna e atualiza a stack para desativar novos cadastros. A senha exige no
mínimo 12 caracteres e combinação de maiúscula, minúscula, número e símbolo. O
valor permanece apenas na memória do processo durante a criação da conta.

## Segurança operacional

O Linkwarden não publica a porta de aplicação no host. PostgreSQL e Meilisearch
ficam somente na rede interna. O Meilisearch executa como UID 1000, a aplicação
usa filesystem raiz somente leitura, diretório temporário dedicado, `tmpfs` para
memória compartilhada e capabilities removidas. O acesso a redes privadas e TLS
inseguro permanece desativado.

## Validação

A homologação isolada confirmou os três YAMLs, convergência saudável de
PostgreSQL, Meilisearch e Linkwarden, criação do administrador com HTTP 201,
fechamento de cadastros, domínio de conteúdo isolado e persistência após reinício
forçado. Também foi reproduzida a janela em que o Swarm ainda reportava o
container antigo como saudável durante uma atualização; o instalador agora exige
um novo ID de container e confirma a configuração segura com tentativas. Não
houve porta publicada. No repouso observado, Linkwarden consumiu entre 654 e 678
MiB, PostgreSQL entre 39 e 76 MiB e Meilisearch aproximadamente 10 MiB.

## Riscos e limites

Arquivamento com Chromium pode consumir memória em páginas grandes ou em muitos
trabalhos simultâneos. O combo limita recursos, mas servidores com 4 GB ou mais
são recomendados. Não habilite acesso a IPs privados sem avaliar SSRF. O domínio
de conteúdo não deve usar regra Cloudflare `Cache Everything`.

## Diagnóstico

Se a aplicação não convergir, verifique separadamente os serviços PostgreSQL,
Meilisearch e Linkwarden, os healthchecks e o log temporário informado pelo
instalador. Falha na criação do primeiro usuário provoca rollback e não deve ser
tratada como instalação concluída.

## Backup e rollback

O backup precisa preservar juntos o diretório PostgreSQL, os arquivos do
Linkwarden, o índice Meilisearch e os três Docker Secrets. O índice pode ser
reconstruído, mas banco, arquivos e secrets formam a cópia essencial. Em falha de
instalação, o rollback remove somente stacks, secrets, rotas e diretórios com o
identificador exclusivo criado pelo fluxo atual.
