---
{
  "schemaVersion": 1,
  "documentId": "setup-n8n-queue-v1-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "548b437bf08ba4b9b10d7bcf0855a13fd1450cfb53338661f2989175e59afa87",
  "documentType": "setup",
  "title": "n8n v1 em modo fila no Setup MNO",
  "setupId": "n8n-queue-v1",
  "setupVersion": "7.22.3",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["n8n", "queue", "workers", "redis", "automacao"],
  "sources": [
    {"sourceId":"n8n-queue-v1-installer","title":"Instalador n8n v1 em fila","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/n8n.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"n8n-queue-docs","title":"Configuração oficial do modo fila","sourceType":"official-documentation","location":"https://docs.n8n.io/hosting/scaling/queue-mode/","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"n8n-security-audit-docs","title":"Auditoria de segurança do n8n","sourceType":"official-documentation","location":"https://docs.n8n.io/hosting/securing/security-audit/","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# n8n v1 em modo fila no Setup MNO

## Quando usar

Use quando webhooks e execuções precisam ser separados do editor e processados
por workers. É apropriado para automações concorrentes e cargas com picos. Para
uso leve e poucos workflows, o n8n sem fila reduz componentes e manutenção.

## Arquitetura no Setup MNO

A variante v1 cria stacks distintas para editor, webhooks, endpoint auxiliar e
worker. Todos compartilham banco PostgreSQL, chave de criptografia e configuração
de fila. O instalador legado aponta a fila para o Redis base do Setup em um banco
lógico reservado; ele não cria Redis dedicado para esta variante.

## Pré-requisitos

Exige dois domínios, PostgreSQL, Redis base saudável, SMTP opcional e capacidade
para todas as réplicas concorrentes. O catálogo reserva uma faixa alta de RAM;
dimensione pelo número, duração, payload e paralelismo dos workflows, não apenas
pelo acesso ao editor.

## Fluxo seguro

O instalador coleta rotas de administração e webhook, SMTP e modo de criação das
stacks. Ele cria banco e chave compartilhada antes dos componentes. Preserve a
mesma chave em toda a topologia e restrinja nós capazes de executar código ou
acessar o sistema de arquivos.

## Primeiro acesso e integrações

Crie um workflow descartável, depois valide webhook, fila e worker em sequência.
Ao integrar APIs, bancos ou mensageria, use credenciais separadas por ambiente,
menor privilégio, timeout e tratamento de repetição. Não use o editor como prova
de que workers recebem e concluem jobs.

## Backup e atualização

Backup deve incluir PostgreSQL, chave de criptografia, workflows, credenciais e
dados binários persistidos. Atualize editor, webhooks e workers para a mesma
versão; mudança parcial pode quebrar o contrato entre componentes. Tenha teste
de restauração e retorno para a versão anterior antes da janela.

## Validação

Confirme acesso ao editor, criação de job, consumo por worker, retorno do webhook,
persistência após recriação e ausência de jobs presos ou duplicados. Monitore
latência de fila, falhas, consumo de RAM e crescimento das tabelas de execução.

## Riscos e limites

Esta é uma linha v1 mantida por compatibilidade. O Redis compartilhado aumenta o
acoplamento operacional e exige cuidado para não limpar chaves de outras cargas.
Workflows inseguros podem exfiltrar dados ou executar ações externas; fila não
substitui governança, rate limit ou idempotência.

## Diagnóstico

Classifique a falha como editor, rota, banco, Redis, worker, credencial ou nó.
Informe apenas nome genérico do workflow, estado do job, horário e erro
sanitizado. Nunca envie credenciais, payload real, chave de criptografia ou dados
de execução ao Assistente.
