---
{
  "schemaVersion": 1,
  "documentId": "setup-rabbitmq-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "394544e14313d238693b27be988aab24f6f7bc47307d155270acc6e20f962a0e",
  "documentType": "setup",
  "title": "RabbitMQ no Setup MNO",
  "setupId": "rabbitmq",
  "setupVersion": "7.22.2",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": ["rabbitmq", "amqp", "mensageria", "filas", "eventos"],
  "sources": [
    {"sourceId":"rabbitmq-installer","title":"Instalador RabbitMQ","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/rabbitmq.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"rabbitmq-install","title":"Instalação oficial do RabbitMQ","sourceType":"official-documentation","location":"https://www.rabbitmq.com/docs/download","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"rabbitmq-management","title":"Plugin de gerenciamento oficial","sourceType":"official-documentation","location":"https://www.rabbitmq.com/docs/management","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"rabbitmq-backup","title":"Backup e restauração oficiais","sourceType":"official-documentation","location":"https://www.rabbitmq.com/docs/backup","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# RabbitMQ no Setup MNO

## Quando usar

Use quando produtores e consumidores precisam desacoplamento, filas, tópicos,
confirmação e retentativa. O broker não corrige sozinho mensagens duplicadas,
consumidores não idempotentes ou ausência de dead-letter e observabilidade.

## Arquitetura no Setup MNO

O instalador cria um nó RabbitMQ 4.0 com plugin de gerenciamento e volume
externo. Publica AMQP 5672 e administração 15672 no host, além da rota web pelo
Traefik. Usuário e senha são coletados, mas o Erlang cookie é um valor literal e
o nome físico do volume declarado contém divergência.

## Pré-requisitos

Exige portas livres, dimensionamento por conexões, filas e tamanho das mensagens,
TLS quando houver tráfego fora da rede interna e desenho de vhosts, usuários,
permissões, exchanges, filas, dead-letter, TTL e consumidores.

## Fluxo seguro

Não prossiga automaticamente com o script atual. Corrija o cookie, o volume,
remova publicações desnecessárias, adicione TLS ou mantenha clientes somente na
rede interna e homologue recuperação. Cada aplicação deve ter usuário e vhost
próprios com menor privilégio.

## Primeiro acesso e integrações

Depois de corrigido, entre pela rota administrativa, crie vhost e usuário de
teste, publique uma mensagem fictícia e confirme consumo e ack. Evolution API,
Chatwoot, n8n e workers podem integrar por AMQP sem compartilhar credencial
administrativa.

## Backup e atualização

Exporte definições e decida separadamente como tratar mensagens. A documentação
oficial alerta que copiar o message store de um nó em execução pode gerar estado
inconsistente e que a restauração depende do mesmo node name em vários cenários.
Fixe a release e teste restauração antes da atualização.

## Validação

Valide listeners, TLS, autenticação, permissões, publicação, consumo, ack,
dead-letter, persistência e reconexão. Monitore memória, disco e alarmes. A UI
aberta não comprova durabilidade nem segurança do protocolo AMQP.

## Riscos e limites

Risco crítico na distribuição atual por portas do host abertas, cookie estático,
ausência de TLS e divergência do volume. Uma réplica única não oferece alta
disponibilidade. O Assistente deve bloquear recomendação de produção.

## Diagnóstico

Separe listener, TLS, usuário, vhost, permissão, exchange, binding, fila,
consumidor, ack, memória e disco. Não envie cookie, senha, payload, URL AMQP ou
mensagem de cliente ao Assistente.
