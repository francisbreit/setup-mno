---
{
  "schemaVersion": 1,
  "documentId": "setup-n8n-queue-v2-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "b13afb81baf6999b08e3929c615c5282dff849dbb0e826c65910c1a4d5423ee5",
  "documentType": "setup",
  "title": "n8n v2 em modo fila no Setup MNO",
  "setupId": "n8n-queue-v2",
  "setupVersion": "7.19.6",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["n8n", "queue", "workers", "task-runners", "redis"],
  "sources": [
    {"sourceId":"n8n-queue-v2-installer","title":"Instalador n8n v2 em fila","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/n8n2.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"n8n-v2-queue-docs","title":"Configuração oficial do modo fila","sourceType":"official-documentation","location":"https://docs.n8n.io/hosting/scaling/queue-mode/","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"n8n-v2-runner-docs","title":"Task runners do n8n","sourceType":"official-documentation","location":"https://docs.n8n.io/hosting/configuration/task-runners/","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# n8n v2 em modo fila no Setup MNO

## Quando usar

Use para novos ambientes que precisam de fila, webhooks escaláveis, workers e
execução isolada de tarefas de código. Em cargas simples, prefira a variante sem
fila. Migração de v1 deve ser tratada como projeto com compatibilidade de nodes,
workflows e dados, não como troca automática de imagem.

## Arquitetura no Setup MNO

O instalador cria Redis dedicado e stacks separadas para editor, webhooks,
endpoint auxiliar, worker e task runner. PostgreSQL e chave de criptografia são
compartilhados entre os componentes n8n. O runner executa JavaScript e Python em
serviço próprio, reduzindo o acoplamento com o processo principal.

## Pré-requisitos

Exige dois domínios, PostgreSQL base, capacidade alta de RAM e CPU, SMTP opcional
e planejamento de concorrência. Considere também tamanho de payload, retenção de
execuções, dados binários e integrações simultâneas. Servidor pequeno não deve
receber esta topologia sem medição e margem.

## Fluxo seguro

O Instalador Seguro coleta rotas, SMTP e modo Portainer ou Docker, cria o Redis
dedicado e depois implanta todos os componentes com versões alinhadas. Preserve
a chave de criptografia e o segredo do runner. Restrinja Code nodes e community
nodes conforme o risco do ambiente.

## Primeiro acesso e integrações

Valide primeiro um workflow sem credenciais e um webhook descartável. Em seguida,
adicione integrações individualmente com menor privilégio, timeout, retentativa e
idempotência. O runner deve permanecer alcançável apenas pela rede interna e não
é um shell para o usuário final.

## Backup e atualização

Backup deve cobrir PostgreSQL, chave de criptografia, configuração do runner,
workflows, credenciais e dados binários. Atualize editor, webhooks, workers e
runners juntos para evitar incompatibilidade de protocolo. Teste migrações e
restauração isoladamente antes da produção.

## Validação

Confirme saúde de todos os serviços, enfileiramento, consumo pelo worker,
execução de código no runner, webhook público, persistência e comportamento após
reinício. Verifique jobs presos, duplicação, latência, saturação de worker e
limites de memória definidos pelo instalador.

## Riscos e limites

É uma topologia de vários serviços e alto consumo. Escalar webhooks sem workers
ou aumentar concorrência sem proteger destinos apenas desloca o gargalo. Código
de workflow continua sendo código executável; fila e runner não eliminam risco
de acesso indevido a dados ou APIs.

## Diagnóstico

Separe falha de editor, webhook, PostgreSQL, Redis dedicado, worker ou runner.
Compare versões entre serviços e use erro sanitizado. Não envie workflow real,
payload de cliente, segredo do runner, chave de criptografia ou credenciais.
