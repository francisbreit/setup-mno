---
{
  "schemaVersion": 1,
  "documentId": "setup-homepage-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "df6bc04ce3f140e97344b664f912526cb01973f4541baf0ef1db6b4c2464cba5",
  "documentType": "setup",
  "title": "Homepage no Setup MNO",
  "setupId": "homepage",
  "setupVersion": "7.34.0",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-10",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["homepage", "dashboard", "docker", "swarm", "produtividade"],
  "sources": [
    {"sourceId":"homepage-installer","title":"Instalador Homepage","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/homepage.sh","license":"project-internal","verifiedAt":"2026-08-10"},
    {"sourceId":"homepage-docker-install","title":"Instalação oficial do Homepage com Docker","sourceType":"official-documentation","location":"https://gethomepage.dev/installation/docker/","license":"documentation-reference","verifiedAt":"2026-08-10"},
    {"sourceId":"homepage-docker-config","title":"Integração oficial do Homepage com Docker e Swarm","sourceType":"official-documentation","location":"https://gethomepage.dev/configs/docker/","license":"documentation-reference","verifiedAt":"2026-08-10"},
    {"sourceId":"socket-proxy-official","title":"Docker Socket Proxy da Tecnativa","sourceType":"official-documentation","location":"https://github.com/Tecnativa/docker-socket-proxy","license":"documentation-reference","verifiedAt":"2026-08-10"},
    {"sourceId":"caddy-basic-auth","title":"Autenticação básica do Caddy","sourceType":"official-documentation","location":"https://caddyserver.com/docs/caddyfile/directives/basic_auth","license":"documentation-reference","verifiedAt":"2026-08-10"}
  ],
  "homologation": {
    "verifiedAt": "2026-08-10",
    "verifiedPorts": [80, 2375, 3000],
    "verifiedImages": [
      "ghcr.io/gethomepage/homepage:v1.13.2@sha256:a0b71c8e757298d02560186bab9fbe3fc2d375c523a62cc1019177b37e48aa28",
      "ghcr.io/tecnativa/docker-socket-proxy:v0.4.2@sha256:1f3a6f303320723d199d2316a3e82b2e2685d86c275d5e3deeaf182573b47476",
      "caddy:2.11.4-alpine@sha256:5f5c8640aae01df9654968d946d8f1a56c497f1dd5c5cda4cf95ab7c14d58648"
    ]
  }
}
---
# Homepage no Setup MNO

## Quando usar

Use o Homepage para reunir aplicações, favoritos, pesquisas, widgets e estado
dos serviços do Docker Swarm em um painel inicial leve e personalizável. Ele é
adequado para operadores que desejam uma página central de navegação sem
substituir o Portainer nem o monitoramento especializado do servidor.

## Arquitetura no Setup MNO

O instalador cria duas stacks e uma rede overlay exclusiva. A stack principal
contém o Homepage e um gateway Caddy autenticado. A substack de segurança contém
somente o Docker Socket Proxy. O Homepage nunca recebe o socket Docker; consulta
o proxy pela rede interna na porta 2375, enquanto o proxy aceita apenas as APIs
de containers, serviços e tarefas necessárias à descoberta do Swarm.

## Pré-requisitos

Exige Docker Swarm ativo, rede externa do Setup MNO, domínio válido e credenciais
do modo Cloudflare Tunnel ou tradicional. O usuário define credencial própria do
painel. A senha exige doze caracteres, maiúscula, minúscula, número e caractere
especial. A configuração persistente fica em diretório exclusivo da instância.

## Fluxo seguro

O gateway Caddy é a única entrada da interface e armazena somente o hash bcrypt
da senha. As portas internas do Homepage e do proxy Docker não são publicadas.
O proxy monta o socket somente para leitura e usa POST igual a zero, bloqueando
criação, alteração ou remoção de recursos. Mantenha HTTPS e considere adicionar
Cloudflare Access como camada extra para ambientes administrativos.

## Validação

A homologação isolada confirmou três serviços em estado saudável, resposta da
API interna, descoberta de serviços do Swarm, bloqueio HTTP 403 para operação
POST, bloqueio HTTP 401 para acesso anônimo e reinício preservando a configuração.
O consumo observado foi de aproximadamente 87 MB no Homepage, 14 MB no proxy e
10 MB no Caddy. Os manifestos oficiais contêm imagens amd64 e arm64.

## Riscos e limites

Mesmo com escrita bloqueada, a leitura do inventário Docker expõe nomes, imagens
e estado operacional ao painel; proteja o domínio e não compartilhe a credencial.
O Homepage não substitui backup, observabilidade ou controle de acesso do Docker.
O limite total configurado é 768 MB e a descoberta completa exige execução no
nó manager. A porta 2375 existe apenas na rede overlay exclusiva.

## Diagnóstico

Se o painel não abrir, confira as réplicas da stack principal e da substack do
proxy, o healthcheck do Homepage, os logs do gateway e a rota do domínio. Se os
serviços não aparecerem, valide o arquivo docker.yaml, o endereço da substack e
as permissões CONTAINERS, SERVICES e TASKS. HTTP 401 indica autenticação ativa;
HTTP 403 no proxy para POST é o comportamento de segurança esperado.

## Backup e atualização

Faça backup do diretório de configuração do Homepage e do Caddyfile da instância.
Os arquivos YAML das duas stacks permitem reconstrução controlada. Antes de
atualizar, valide a nova versão em recursos isolados, confirme os manifestos para
amd64 e arm64, fixe novos digests e teste leitura do Swarm com escrita bloqueada.
