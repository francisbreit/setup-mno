---
{
  "schemaVersion": 1,
  "documentId": "setup-rocketchat-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "bb492b94eb29facd464d4c30c53401ebdde3c52c42aa45c66194e08620fc3fac",
  "documentType": "setup",
  "title": "Rocket.Chat no Setup MNO",
  "setupId": "rocketchat",
  "setupVersion": "7.12.3",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": ["rocket-chat", "chat", "mongodb", "colaboracao", "replica-set"],
  "sources": [
    {"sourceId":"rocketchat-installer","title":"Instalador Rocket.Chat","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/rocketchat.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"rocketchat-docker","title":"Deploy with Docker and Docker Compose","sourceType":"official-documentation","location":"https://docs.rocket.chat/docs/deploy-with-docker-docker-compose","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"rocketchat-requirements","title":"System Requirements","sourceType":"official-documentation","location":"https://docs.rocket.chat/docs/system-requirements","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"rocketchat-backup","title":"Back up and restore MongoDB","sourceType":"official-documentation","location":"https://docs.rocket.chat/docs/deploy-with-docker-docker-compose#back-up-and-restore-your-mongodb-database","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# Rocket.Chat no Setup MNO

## Quando usar

Use para mensagens, canais e colaboração quando a organização aceita operar a
plataforma e o banco. Não escolha sem verificar a janela de suporte: versões
fora dela podem perder integração com serviços cloud e clientes oficiais.

## Arquitetura no Setup MNO

O instalador reutiliza ou cria um MongoDB compartilhado de nó único e implanta
Rocket.Chat com tag móvel. A base criada não configura replica set nem oplog. O
wizard inicial é marcado como concluído pela configuração distribuída.

## Pré-requisitos

Exige domínio, TLS, MongoDB na versão compatível, replica set, armazenamento,
SMTP e recursos dimensionados. A documentação atual exige MongoDB mais novo
para a geração atual do Rocket.Chat e recomenda três membros para alta
disponibilidade.

## Fluxo seguro

Não recomende o deploy atual para produção até corrigir e homologar a topologia
MongoDB. Use banco dedicado, fixe versões compatíveis e preserve credenciais
fora de YAML e logs. Execute mudanças apenas pelo Instalador Seguro.

## Primeiro acesso e integrações

Com uma topologia homologada, crie administrador, restrinja cadastros, habilite
MFA e teste canal e usuário descartáveis. Apps, bots, push, federação e OAuth
devem ser validados separadamente e podem depender da edição ou cloud.

## Backup, atualização e rollback

Backup é centrado no MongoDB e também precisa de uploads e configuração
compatíveis. Leia a matriz Rocket.Chat e MongoDB antes de cada salto, preserve
backup, teste restore e respeite versões intermediárias. Não faça downgrade por
troca de imagem.

## Validação

Valide replica set, login, mensagem, upload, websocket, email, persistência e
restauração de workspace descartável antes de convidar usuários.

## Diagnóstico

Separe proxy e websocket, aplicação, MongoDB, replica set, storage e cloud. Não
envie mensagens, anexos, tokens, credenciais ou dump ao Assistente.

## Riscos e limites

MongoDB standalone compartilhado, tag móvel e incompatibilidade com requisitos
atuais são bloqueios críticos. O Assistente deve informar ausência de evidência
em vez de ensinar a contornar esses gates.
