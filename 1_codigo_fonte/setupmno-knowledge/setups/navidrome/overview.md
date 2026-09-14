---
{
  "schemaVersion": 1,
  "documentId": "setup-navidrome-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "a6ed2cd87d369ca53f2675b0720d207a6db80028e01fdcefc839985bc5260890",
  "documentType": "setup",
  "title": "Navidrome no Setup MNO",
  "setupId": "navidrome",
  "setupVersion": "7.48.0",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-14",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["navidrome", "musica", "audio", "streaming", "subsonic", "sqlite"],
  "sources": [
    {"sourceId":"navidrome-installer","title":"Instalador Navidrome PRO","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/navidrome.sh","license":"project-internal","verifiedAt":"2026-08-14"},
    {"sourceId":"navidrome-docker","title":"Instalação oficial do Navidrome com Docker","sourceType":"official-documentation","location":"https://www.navidrome.org/docs/installation/docker/","license":"documentation-reference","verifiedAt":"2026-08-14"},
    {"sourceId":"navidrome-config","title":"Opções oficiais de configuração do Navidrome","sourceType":"official-documentation","location":"https://www.navidrome.org/docs/usage/configuration/options/","license":"documentation-reference","verifiedAt":"2026-08-14"},
    {"sourceId":"navidrome-release","title":"Navidrome 0.63.2","sourceType":"official-documentation","location":"https://github.com/navidrome/navidrome/releases/tag/v0.63.2","license":"documentation-reference","verifiedAt":"2026-08-14"}
  ],
  "homologation": {
    "verifiedAt": "2026-08-14",
    "verifiedPorts": [4533],
    "verifiedImages": [
      "deluan/navidrome:0.63.2@sha256:9012939114fbb1bb641b81cf96dec5ded15f0aafefe8d47a511d7cb919658e40"
    ]
  }
}
---
# Navidrome no Setup MNO

## Quando usar

Use o Navidrome para organizar e reproduzir uma biblioteca pessoal de músicas
no navegador ou em clientes compatíveis com Subsonic. Ele é indicado para quem
quer manter arquivos de áudio no próprio servidor, com usuários, playlists,
favoritos, transcodificação e acesso por aplicativos móveis ou desktop.

## Arquitetura no Setup MNO

O instalador cria uma stack de serviço único com banco SQLite, cache e
configuração em um diretório persistente exclusivo. A biblioteca musical fica
em outro diretório do host, montado como `/music` somente para leitura. Isso
impede que a aplicação altere ou apague os arquivos originais durante a
reprodução, indexação ou transcodificação.

A imagem oficial 0.63.2 é fixada por versão e digest multi-arquitetura. O
processo executa como UID e GID 1000, sem capabilities Linux, com `/tmp`
temporário e limites de um CPU e 512 MB de RAM. A porta 4533 permanece somente
nas redes internas do Swarm; o acesso externo ocorre pelo Traefik ou pelo
Cloudflare Tunnel.

## Pré-requisitos

Exige Docker Swarm ativo, redes externa e interna do Setup MNO, domínio válido
e credenciais correspondentes ao modo Traefik ou Cloudflare Tunnel. Os arquivos
de música devem ser copiados para a pasta informada ao final do instalador. O
espaço em disco precisa comportar a biblioteca, o banco e os caches de imagens
e transcodificação.

## Fluxo seguro

No primeiro acesso, o próprio Navidrome solicita a criação do administrador.
Nenhuma senha padrão é gerada ou armazenada pelo instalador. Use uma senha
exclusiva e, quando possível, proteja o domínio adicionalmente com Cloudflare
Access. A coleta anônima de informações do produto fica desativada por padrão.

Não exponha a porta 4533 diretamente no host e não torne a pasta de músicas
gravável para o container. Contas para familiares ou clientes devem ser
individuais; evite compartilhar a conta administrativa usada na configuração.

## Validação

A homologação no WSL2 com Docker Desktop confirmou a imagem amd64 e o manifesto
arm64, réplica 1/1, endpoint interno `/ping` com HTTP 200, interface web,
criação do banco SQLite, scanner, persistência após reinício e healthcheck
saudável. O teste sem root confirmou banco pertencente ao UID 1000 e falha de
escrita esperada na biblioteca musical. O consumo ocioso observado foi próximo
de 14 MB, abaixo do limite de 512 MB.

O instalador valida comandos, Swarm, redes, credenciais, imagens, YAML, réplica,
endpoint e banco persistente antes de configurar DNS e Tunnel. A prova HTTP usa
um serviço efêmero do Swarm sem porta publicada, filesystem somente leitura e
capabilities removidas; ele é apagado no sucesso, erro e rollback.

Na fundação do Selo de Homologação da v7.20.0, essa execução AMD64 foi anexada
como evidência operacional sanitizada. A cobertura permanece parcial: ARM64
tem manifesto confirmado, mas ainda não possui execução operacional anexada;
update, backup e restore também continuam pendentes. Portanto, o Navidrome não
recebe o nível `homologated` nesta release.

## Riscos e limites

O perfil entregue é de instância única e não oferece alta disponibilidade do
banco SQLite. Bibliotecas grandes, transcodificação simultânea e clientes em
conexões lentas podem elevar CPU, memória e uso de disco. O limite de 512 MB é
adequado para uma implantação pessoal inicial, mas deve ser revisto com métricas
reais antes de ampliar usuários simultâneos.

O Navidrome organiza e transmite arquivos existentes; ele não fornece músicas
nem substitui licenças de conteúdo. O operador continua responsável pela origem
e pelo direito de uso dos arquivos armazenados no servidor.

## Diagnóstico

Se o painel não abrir, confira réplica, healthcheck, logs, resolução DNS e rota
do Tunnel ou Traefik. Se `/ping` responder mas a biblioteca estiver vazia,
confirme que os arquivos foram copiados para o diretório correto, que UID 1000
consegue lê-los e execute uma nova varredura no painel. Falha ao criar o banco
normalmente indica permissão incorreta no diretório de dados.

## Backup e atualização

Antes de atualizar, faça backup do diretório de dados e preserve a biblioteca
musical. O backup do SQLite deve ocorrer com a aplicação parada ou pelo comando
oficial de backup, evitando cópia inconsistente durante escrita. Teste novas
tags e migrações em ambiente isolado e mantenha o digest fixo até a homologação.

Em falha durante a instalação, o rollback remove somente a stack, o YAML e os
diretórios exclusivos da execução e restaura DNS e Tunnel alterados. Não apague
o banco para corrigir erro de login ou indexação sem backup e diagnóstico.
