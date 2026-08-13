---
{
  "schemaVersion": 1,
  "documentId": "setup-rustdesk-server-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "1bdb924d5f45e102f126086dfd7ba1421026977aa2ee3c817985368f20791ffc",
  "documentType": "setup",
  "title": "RustDesk Server no Setup MNO",
  "setupId": "rustdesk-server",
  "setupVersion": "7.17.0",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-13",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["rustdesk", "acesso-remoto", "suporte", "hbbs", "hbbr", "relay", "dns-only"],
  "sources": [
    {"sourceId":"rustdesk-installer","title":"Instalador RustDesk Server PRO","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/rustdesk.sh","license":"project-internal","verifiedAt":"2026-08-13"},
    {"sourceId":"rustdesk-docker","title":"RustDesk Server OSS com Docker","sourceType":"official-documentation","location":"https://rustdesk.com/docs/en/self-host/rustdesk-server-oss/docker/","license":"documentation-reference","verifiedAt":"2026-08-13"},
    {"sourceId":"rustdesk-ports","title":"Portas do RustDesk Server OSS","sourceType":"official-documentation","location":"https://rustdesk.com/docs/en/self-host/rustdesk-server-oss/install/","license":"documentation-reference","verifiedAt":"2026-08-13"},
    {"sourceId":"rustdesk-release","title":"RustDesk Server 1.1.16","sourceType":"official-documentation","location":"https://github.com/rustdesk/rustdesk-server/releases/tag/1.1.16","license":"documentation-reference","verifiedAt":"2026-08-13"}
  ],
  "homologation": {
    "verifiedAt": "2026-08-13",
    "verifiedPorts": [21115, 21116, 21117],
    "verifiedImages": [
      "rustdesk/rustdesk-server:1.1.16@sha256:8ecdab65deb7c84652a626380e31d11a8f1fbafd97916d57f95c20628f943c00"
    ]
  }
}
---
# RustDesk Server no Setup MNO

## Quando usar

Use o RustDesk Server para manter sob seu controle a identificação dos clientes,
o hole punching e o relay de sessões de acesso remoto. Ele substitui os servidores
públicos do RustDesk, mas não substitui o aplicativo RustDesk instalado nos
computadores e celulares atendidos.

## Arquitetura no Setup MNO

O instalador cria uma stack com dois serviços oficiais: `hbbs`, responsável pelo
rendezvous, registro e teste NAT, e `hbbr`, responsável pelo relay. Os dois usam o
mesmo diretório persistente para a chave Ed25519 e a base SQLite. A imagem oficial
1.1.16 é fixada por digest multi-arquitetura e funciona em AMD64 e ARM64.

Os serviços executam com filesystem raiz somente leitura, todas as capabilities
removidas, limites de CPU e memória e placement no manager. A atualização usa
ordem `stop-first`, necessária porque as portas em modo host não podem ser ocupadas
simultaneamente por duas tarefas no mesmo nó.

## DNS e Cloudflare

RustDesk não é uma aplicação HTTP comum. O Cloudflare Tunnel e o proxy laranja não
transportam o conjunto TCP e UDP esperado pelos clientes RustDesk OSS. Por isso o
Setup cria um CNAME DNS-only para uma origem IPv4 DNS-only do domínio selecionado.
Nenhuma rota é adicionada ao Tunnel e nenhuma label do Traefik é criada.

O perfil multidomínio fornece a zona e a API Token corretas. O instalador valida
que o hostname pertence exatamente ao domínio escolhido, recusa registros DNS já
existentes e reverte somente os registros criados pela tentativa que falhou.

## Portas e firewall

O servidor publica 21115/TCP para teste NAT, 21116/TCP e UDP para registro e hole
punching e 21117/TCP para relay. As portas WebSocket 21118 e 21119 não são
publicadas porque o web client não faz parte desta instalação. A porta adicional do
console Pro oficial também não pertence ao servidor OSS.

Em uma VPS, libere as portas tanto no firewall local quanto no firewall ou security
group do provedor. Em WSL2, acesso vindo da internet também exige encaminhamento no
Windows e no roteador. DNS correto não substitui essas regras de rede.

## Configuração dos clientes

Depois da instalação, configure `ID Server` com o domínio escolhido e a porta 21116,
`Relay Server` com o mesmo domínio e a porta 21117, deixe `API Server` vazio e copie a chave pública exibida pelo
instalador. A mesma configuração deve ser usada nos clientes que participarão das
sessões. A chave privada nunca deve ser copiada ou divulgada.

Os dados de conexão são gravados em `/root/dados_rustdesk/` com permissão restrita.
A chave pública pode ser distribuída aos clientes; o arquivo `id_ed25519` no
diretório persistente é secreto e deve permanecer somente no servidor.

## Pré-requisitos

Exige Docker Swarm ativo, uma zona Cloudflare validada pelo perfil multidomínio,
API Token com DNS em modo de edição, IPv4 público e disponibilidade das portas
21115, 21116 e 21117. O provedor precisa aceitar tráfego TCP e UDP nessas portas.
Em WSL2, o teste local não garante acesso externo sem regras adicionais no Windows
e no equipamento que entrega a conexão à internet.

## Fluxo seguro

Reserve um subdomínio exclusivo, mantenha o proxy Cloudflare desativado e libere
somente as portas necessárias. Distribua apenas a chave pública aos clientes e
proteja a chave privada com backup restrito. Não publique o diretório persistente,
não coloque a chave privada em mensagens e não altere o CNAME para proxy laranja.

Antes de uma atualização, registre versão, digest, chave pública e estado das
réplicas. A mudança deve conservar o diretório de dados e permitir retorno ao digest
anterior sem recriar a identidade dos clientes.

## Validação

Antes do deploy, o instalador verifica Docker Swarm, imagem, YAML, credenciais
Cloudflare e conflitos nas três portas. Depois do deploy, exige réplica 1/1 de
`hbbs` e `hbbr`, listeners TCP/UDP, conexão local nas portas TCP, chave pública,
chave privada e banco SQLite persistentes. O DNS só é criado após esses gates.

A homologação isolada confirmou os dois serviços, TCP 21115/21116/21117, UDP 21116,
preservação da chave após reinício e consumo inferior a 2 MiB em repouso. Os
limites de 384 MB para `hbbs` e 256 MB para `hbbr` mantêm margem para sessões reais.

## Riscos e limites

O relay pode consumir banda elevada quando conexão direta não é possível. O custo
principal de produção tende a ser tráfego de rede, não RAM. Monitore banda, latência,
disco e reinícios. Uma única réplica atende o cenário inicial do Setup MNO, mas não
representa alta disponibilidade.

Publicar portas de acesso remoto amplia a superfície exposta. Mantenha a versão
fixada e homologada, restrinja administração da VPS, aplique atualizações planejadas
e nunca habilite 21118/21119 diretamente na internet sem um projeto específico de
proxy reverso e validação dos riscos documentados pelo RustDesk.

## Diagnóstico

Se os clientes não conectarem, confirme primeiro a resolução DNS-only e depois as
regras TCP e UDP no firewall local e no provedor. Réplicas 1/1 com timeout externo
normalmente indicam bloqueio ou NAT, não falha do container. Consulte separadamente
os logs de `hbbs` e `hbbr` e confirme se as três portas permanecem escutando.

Se a chave exibida pelo cliente divergir, compare-a com `id_ed25519.pub`; nunca use
o arquivo privado como chave de configuração. Reinícios acompanhados de perda de
identidade indicam volume ou bind incorreto. Preserve os dados antes de qualquer
recriação e evite gerar um novo par de chaves como primeiro passo de diagnóstico.

## Backup, atualização e rollback

Faça backup do diretório persistente antes de atualizar. Ele contém a identidade do
servidor e a base de peers; perder a chave exige reconfigurar os clientes. Atualize
primeiro em ambiente isolado e preserve o digest anterior para rollback.

Em falha de instalação, o Setup remove somente a stack, o YAML, o diretório de dados
e os registros DNS criados naquela execução. Recursos já existentes, portas ocupadas
e hostnames previamente cadastrados são preservados e causam interrupção segura.
