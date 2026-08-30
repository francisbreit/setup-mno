---
{
  "schemaVersion": 1,
  "documentId": "setup-netdada-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "d17803dc01da9634171223dfc3af48ebdde813cbc656b29a7a557752ae0767ca",
  "documentType": "setup",
  "title": "NETDADA no Setup MNO",
  "setupId": "netdada",
  "setupVersion": "7.41.0",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-10",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["netdada", "netdata", "monitoramento", "observabilidade", "docker"],
  "sources": [
    {"sourceId":"netdada-installer","title":"Instalador NETDADA","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/netdada.sh","license":"project-internal","verifiedAt":"2026-08-10"},
    {"sourceId":"netdata-docker","title":"Instalação oficial do Netdata com Docker","sourceType":"official-documentation","location":"https://learn.netdata.cloud/docs/netdata-agent/installation/docker","license":"documentation-reference","verifiedAt":"2026-08-10"},
    {"sourceId":"netdata-security","title":"Segurança do Netdata Agent","sourceType":"official-documentation","location":"https://learn.netdata.cloud/docs/netdata-agent/configuration/securing-agents","license":"documentation-reference","verifiedAt":"2026-08-10"},
    {"sourceId":"caddy-basic-auth","title":"Autenticação básica do Caddy","sourceType":"official-documentation","location":"https://caddyserver.com/docs/caddyfile/directives/basic_auth","license":"documentation-reference","verifiedAt":"2026-08-10"}
  ],
  "homologation": {
    "verifiedAt": "2026-08-10",
    "verifiedPorts": [],
    "verifiedImages": [
      "netdata/netdata:v2.10.4@sha256:689145f603fed0ca341b4d8a0fb9910cd9d8c0590b0530cd24ae1912a9c7f8f3",
      "caddy:2.11.4-alpine@sha256:5f5c8640aae01df9654968d946d8f1a56c497f1dd5c5cda4cf95ab7c14d58648"
    ]
  }
}
---
# NETDADA no Setup MNO

## Quando usar

Use o NETDADA para acompanhar em tempo real CPU, memória, discos, processos,
containers Docker, alertas e disponibilidade do servidor. O nome exibido pelo
Setup MNO é NETDADA; o agente de observabilidade instalado é o Netdata.

## Arquitetura no Setup MNO

O instalador cria uma stack com o agente Netdata e um proxy Caddy dedicado.
O agente coleta métricas do host e do Docker por montagens somente leitura,
enquanto o proxy é a única entrada da interface. A porta interna do Netdata não
é publicada no host. O acesso externo ocorre pelo Traefik ou Cloudflare Tunnel.

## Pré-requisitos

Exige Docker Swarm ativo, redes externa e interna do Setup MNO, domínio válido e
credenciais do modo de instalação escolhido. O usuário define credencial própria
do painel. A senha exige pelo menos doze caracteres e não é gravada em texto
claro; somente o hash bcrypt é persistido na configuração do proxy.

## Fluxo seguro

Mantenha a autenticação do proxy habilitada e use HTTPS no domínio. Restrinja o
domínio adicionalmente com Cloudflare Access quando disponível. O socket Docker
é montado somente para leitura, mas continua sendo um recurso sensível; limite o
acesso administrativo ao nó manager e não reutilize a stack como proxy genérico.

## Validação

A homologação isolada confirmou dashboard autenticado, API interna saudável,
métricas do sistema e de containers, persistência após reinício e bloqueio com
HTTP 401 para acesso sem credencial. As imagens testadas funcionaram em amd64 e
possuem manifesto arm64. Não existe porta publicada diretamente no host.

## Riscos e limites

No Docker Swarm, o modo PID do host não é aplicado como em Docker Compose. Por
isso, coletores que dependem de todos os processos ou interfaces do host podem
ser parciais, especialmente em WSL2 com Docker Desktop. Métricas essenciais de
CPU, memória, discos e containers permanecem disponíveis. O limite total da
stack é 896 MB, embora o consumo observado tenha sido muito menor.

## Diagnóstico

Se o painel não abrir, confira réplicas dos serviços do agente e do proxy, logs
da stack, resolução do domínio e rota do Tunnel ou Traefik. Se houver HTTP 401,
revise o usuário e redefina a senha por reinstalação controlada. Avisos de acesso
a arquivos de processos no WSL2 podem indicar limitação do Docker Desktop e não
necessariamente falha do agente.

## Backup e atualização

Faça backup dos três volumes persistentes do agente e do diretório exclusivo que
contém o Caddyfile. Antes de atualizar, preserve o hash da credencial, confira a
documentação oficial, teste a nova imagem em stack isolada e mantenha os digests
fixos até a homologação ser concluída.
