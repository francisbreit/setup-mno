---
{
  "schemaVersion": 1,
  "documentId": "setup-odoo-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "9dc7739669f42ad4682bd63df4910036b206f955398c2c0c313dcb3fcc5645c3",
  "documentType": "setup",
  "title": "Odoo no Setup MNO",
  "setupId": "odoo",
  "setupVersion": "7.7.24",
  "architectures": ["amd64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": ["odoo", "erp", "crm", "postgresql", "filestore"],
  "sources": [
    {"sourceId":"odoo-installer","title":"Instalador Odoo","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/odoo.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"odoo-admin","title":"Database management","sourceType":"official-documentation","location":"https://www.odoo.com/documentation/18.0/administration.html","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"odoo-update","title":"Bugfix updates","sourceType":"official-documentation","location":"https://www.odoo.com/documentation/18.0/administration/on_premise/update.html","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"odoo-upgrade","title":"Upgrade","sourceType":"official-documentation","location":"https://www.odoo.com/documentation/18.0/administration/upgrade.html","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# Odoo no Setup MNO

## Quando usar

Use como plataforma ERP e CRM modular quando processos, responsáveis e
governança de dados estão definidos. Não instale módulos indiscriminadamente:
customizações afetam atualização, suporte e migração. Diferencie Community de
recursos e contratos Enterprise.

## Arquitetura no Setup MNO

O catálogo declara apenas amd64. O instalador cria aplicação Odoo 18 e
PostgreSQL na mesma stack, com volumes separados para dados, configuração,
addons e banco. A base também é publicada no host, ampliando a superfície de
ataque sem necessidade para o fluxo web.

## Pré-requisitos

Exige domínio, TLS, email, armazenamento para banco e filestore, plano de
backup, módulos aprovados e responsável funcional. Confirme compatibilidade de
addons com a edição e versão antes de importar produção.

## Fluxo seguro

Execute pelo Instalador Seguro somente após verificar conflito e necessidade da
exposição do banco. Proteja o gerenciador de bases, defina senha mestra, limite
bancos por hostname e crie administrador individual. Addons de terceiros
precisam de revisão de código e licença.

## Primeiro acesso e integrações

Crie base descartável sem dados de demonstração quando apropriado, revise país,
empresa, moeda e email. Ative um módulo por vez e teste webhooks, API e SMTP com
contas de menor privilégio.

## Backup, atualização e rollback

Backup completo reúne dump e filestore da mesma base; perder um deles quebra
anexos. Antes de atualização, preserve cópia fora do servidor e teste com todos
os addons. Mudança de versão principal é upgrade de banco, não simples troca de
imagem, e pode exigir o serviço oficial de upgrade.

## Validação

Valide login, criação de registro, anexo, email, job agendado, persistência e
restauração conjunta de banco e filestore em ambiente isolado.

## Diagnóstico

Separe proxy, aplicação, addons, workers, PostgreSQL, filestore e email. Não
envie bancos, documentos fiscais, dados pessoais, chaves ou configuração ao
Assistente.

## Riscos e limites

A publicação do PostgreSQL, ausência de limites de recursos e agrupamento do
banco com a aplicação bloqueiam recomendação automática de produção. ARM, alta
disponibilidade e migração de edição não estão homologados.
