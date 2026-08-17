---
{
  "schemaVersion": 1,
  "documentId": "setup-langfuse-minio-clickhouse-overview",
  "documentVersion": "1.5.0",
  "contentSHA256": "db282a62863c4984f80ea460b24cd42dc751caa2032460ab26b657b7242e4b20",
  "documentType": "setup",
  "title": "Langfuse com MinIO e ClickHouse no Setup MNO",
  "setupId": "langfuse-minio-clickhouse",
  "setupVersion": "7.19.9",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-09",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["langfuse", "observabilidade-ia", "clickhouse", "minio", "tracing"],
  "sources": [
    {"sourceId":"langfuse-installer","title":"Instalador Langfuse, MinIO e ClickHouse","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/langfuse.sh","license":"project-internal","verifiedAt":"2026-08-09"},
    {"sourceId":"langfuse-compose","title":"Docker Compose oficial do Langfuse","sourceType":"official-documentation","location":"https://github.com/langfuse/langfuse/blob/main/docker-compose.yml","license":"documentation-reference","verifiedAt":"2026-08-08"},
    {"sourceId":"langfuse-blobstorage","title":"Blob storage self-hosted do Langfuse","sourceType":"official-documentation","location":"https://langfuse.com/self-hosting/deployment/infrastructure/blobstorage","license":"documentation-reference","verifiedAt":"2026-08-08"},
    {"sourceId":"langfuse-clickhouse","title":"ClickHouse self-hosted do Langfuse","sourceType":"official-documentation","location":"https://langfuse.com/self-hosting/deployment/infrastructure/clickhouse","license":"documentation-reference","verifiedAt":"2026-08-08"},
    {"sourceId":"langfuse-health","title":"Health e readiness endpoints do Langfuse","sourceType":"official-documentation","location":"https://langfuse.com/self-hosting/configuration/health-readiness-endpoints","license":"documentation-reference","verifiedAt":"2026-08-08"},
    {"sourceId":"langfuse-scaling","title":"Requisitos e escala do Langfuse","sourceType":"official-documentation","location":"https://langfuse.com/self-hosting/configuration/scaling","license":"documentation-reference","verifiedAt":"2026-08-08"}
  ],
  "homologation": {"verifiedAt":"2026-08-09","verifiedPorts":[3000,3030,5432,6379,8123,9000],"verifiedImages":["clickhouse/clickhouse-server:25.12","langfuse/langfuse-worker:4","langfuse/langfuse:4","pgvector/pgvector:pg16","quay.io/minio/minio:RELEASE.2025-04-08T15-41-24Z","redis:7-alpine"]}
}
---
# Langfuse com MinIO e ClickHouse no Setup MNO

## Quando usar

Use para rastrear chamadas de modelos, spans, custos, latência, prompts, scores e
datasets de aplicações de IA. Não use como substituto de logs de infraestrutura
nem envie dados pessoais sem política explícita de retenção e mascaramento.

## Arquitetura no Setup MNO

O combo usa Langfuse web e worker na linha principal `4`, ClickHouse 25.12,
Redis 7 Alpine dedicado, PostgreSQL compartilhado e MinIO. Cada dependência é
uma stack separada no Portainer. Web e worker recebem 2 GiB cada e usam
`NODE_OPTIONS=--max-old-space-size=1536`, necessário para as migrações do
primeiro boot. Todos os componentes operam em UTC.

O bucket é privado e recebe uma service account limitada ao próprio bucket.
Eventos, mídia do worker e exportações em lote trafegam pelo alias interno do
MinIO na porta 9000. Apenas a web usa o endpoint público para gerar URLs de
download acessíveis ao navegador. O alias interno não contém underscore porque
o SDK S3 rejeita esse caractere em hostnames.

## Pré-requisitos

Reserve pelo menos 8 GiB de RAM e espaço persistente para PostgreSQL,
ClickHouse, Redis e objetos S3. A medição isolada em repouso ficou próxima de
2,3 GiB, mas o primeiro boot produz um pico relevante durante as migrações.
Produção, alta ingestão e retenção extensa exigem o dimensionamento oficial por
componente, que é muito maior que o mínimo prático de laboratório.

As redes externas `interna` e `externa`, PostgreSQL e Traefik ou Cloudflare
Tunnel devem existir. Nenhuma porta é publicada diretamente no host pelo combo.

## Fluxo seguro

O instalador cria volumes externos antes dos deploys, provisiona MinIO,
ClickHouse e Redis antes da aplicação e só cria os bancos depois de validar as
dependências. Use ClickHouse 25.12 ou superior. O Redis dedicado usa senha,
persistência AOF e `noeviction`, pois a remoção automática de chaves pode perder
filas do BullMQ.

O instalador não mostra senhas na confirmação. O provisionador temporário do
MinIO usa Docker Secrets e é removido ao concluir. Os YAMLs persistentes ainda
contêm credenciais operacionais e exigem permissão restrita e backup protegido.
Feche o cadastro público depois de criar os administradores necessários.

A access key da service account possui exatamente 20 caracteres alfanuméricos,
limite aceito pela imagem MinIO fixada. O instalador valida esse tamanho antes
de criar os Secrets e novamente dentro do provisionador. Falhas registram apenas
o estágio, nunca a chave, e acionam a remoção limitada ao serviço e aos Secrets
temporários daquela tentativa.

O provisionador é um serviço Swarm one-shot com `restart-condition none`. Sua
criação usa `--detach` explicitamente, pois versões recentes do Docker aguardam
convergência por padrão e um job concluído não deve bloquear o instalador. O
script retorna imediatamente ao próprio loop, que aceita somente o estado
`Complete` antes de avançar para ClickHouse, PostgreSQL, Redis e Langfuse.

## Primeiro acesso e integrações

Depois da instalação, acesse a URL do Langfuse, crie organização e projeto e
gere chaves exclusivas. Teste primeiro com telemetria fictícia. n8n, aplicações
Python ou JavaScript, OpenTelemetry e gateways de LLM podem enviar traces para
`/api/public/otel/v1/traces` sem receber credenciais administrativas do provedor.

## Backup, atualização e rollback

Proteja separadamente PostgreSQL, volumes de dados e logs do ClickHouse, volume
do Redis e bucket S3. Pause ingestão antes de um backup coordenado e teste a
restauração em ambiente isolado. Antes de atualizar, leia as notas do Langfuse,
faça snapshot e valide compatibilidade do ClickHouse. O rollback do instalador
é a release Git anterior; rollback de dados depende de restauração coordenada,
pois migrações de banco podem não ser reversíveis.

## Validação

No WSL2 com Docker Desktop, a homologação isolada de 8 de agosto de 2026
confirmou instalação limpa, Langfuse 4.6.0, ClickHouse 25.12.11.4, web e worker
saudáveis e ingestão OTLP v4 com HTTP 200. O mesmo trace sintético foi gravado
como objeto no MinIO e materializado na tabela `events_full` do ClickHouse.

Também foram validados Redis autenticado por connection string, provisionamento
da service account com política limitada ao bucket, persistência após reinício e
recuperação das dependências. As imagens declaradas possuem manifests amd64 e
arm64; a lógica ARM é espelhada, mas o smoke test de runtime ocorreu em amd64.

Em 9 de agosto de 2026, uma falha real foi reproduzida com a chave antiga de 23
caracteres: o MinIO recusou a service account e a stack principal não chegou a
ser criada. A chave corrigida de 20 caracteres foi aceita no mesmo ambiente
isolado. O gate validou 32 gerações no fonte e após compilação SHC, além de CRUD
no bucket permitido e bloqueio de acesso a outro bucket.

Também foi reproduzido no Docker 29.4.2 o bloqueio causado por `service create`
sem detach explícito. Com `--detach`, a chamada retornou em dois segundos e o
provisionador Swarm atingiu `Complete`, usando a mesma imagem, quatro Secrets,
rede overlay, bucket privado e policy do instalador.

Na validação de 9 de agosto de 2026, a API do Portainer respondeu antes de o
Swarm registrar os serviços: worker e web surgiram um e três segundos depois da
verificação do instalador. A validação agora aguarda o registro por até dois
minutos. As imagens v4 também escutaram somente no endereço interno quando a
variável oficial de binding não estava definida; os healthchecks em loopback
falharam e o Swarm encerrou as tarefas como `unhealthy`. Web e worker agora
recebem a configuração oficial de escuta em todas as interfaces, mantendo os
endpoints locais acessíveis.

## Diagnóstico

Consulte primeiro o log seguro indicado pelo instalador e o estado das quatro
stacks. Web responde em `/api/public/health?failIfDatabaseUnavailable=true` e o
worker em `/api/health`. Erro S3 `invalid hostname` indica alias com underscore;
falha de migração com abort do Node indica memória insuficiente. Confirme ainda
Redis saudável, ClickHouse 25.12 ou superior e acesso ao bucket privado. Nunca
envie prompts, respostas, chaves ou conteúdo de clientes ao Assistente.

Se a interface informar que a stack não existe, compare o horário do log com o
campo `CreatedAt` dos serviços. Um atraso curto após resposta HTTP do Portainer
indica criação assíncrona e deve ser absorvido pela espera do instalador. Tarefas
em reinício com recusa de conexão no loopback indicam ausência de configuração
de escuta em todas as interfaces nas versões antigas do YAML.

Se apenas MinIO e ClickHouse aparecerem no Portainer, procure o serviço
temporário `<langfuse>-mc-internal`. Estado `Failed` antes da criação dos bancos
indica falha no provisionamento S3. Releases anteriores à correção podem deixar
esse serviço e quatro Secrets temporários; confirme o sufixo exato da tentativa
antes de qualquer limpeza e nunca remova volumes ou dependências compartilhadas.

## Riscos e limites

O risco residual é alto: credenciais ainda são materializadas nos YAMLs gerados,
PostgreSQL ou MinIO preexistentes podem ser compartilhados e tags principais do
Langfuse podem introduzir migrações. A evidência local cobre instalação limpa,
saúde, ingestão, storage, analytics e reinício; não cobre carga prolongada,
restauração coordenada, alta disponibilidade ou execução real em ARM.
