---
{
  "schemaVersion": 1,
  "documentId": "setup-clickhouse-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "8069850b6dd5354bcc05824b004c77702bf3a8cafa526c0fb2bb6f98401ffdf8",
  "documentType": "setup",
  "title": "ClickHouse no Setup MNO",
  "setupId": "clickhouse",
  "setupVersion": "7.48.26",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": ["clickhouse", "olap", "analytics", "data-warehouse", "sql"],
  "sources": [
    {"sourceId":"clickhouse-installer","title":"Instalador ClickHouse","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/clickhouse.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"clickhouse-docker","title":"Imagem Docker oficial do ClickHouse","sourceType":"official-documentation","location":"https://clickhouse.com/docs/install/docker","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"clickhouse-backup","title":"Backup e restauração do ClickHouse","sourceType":"official-documentation","location":"https://clickhouse.com/docs/operations/backup","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"clickhouse-update","title":"Atualização self-managed do ClickHouse","sourceType":"official-documentation","location":"https://clickhouse.com/docs/operations/update","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# ClickHouse no Setup MNO

## Quando usar

Use para consultas analíticas, eventos, séries temporais e grandes volumes com
leitura agregada. Não use como substituto automático de PostgreSQL ou MySQL em
aplicações transacionais sem redesenhar modelo, ingestão e consistência.

## Arquitetura no Setup MNO

O instalador cria uma réplica com a imagem 23.8.8.20-alpine, volumes de dados e
logs e rota HTTPS para a interface HTTP 8123. Usuário e senha são coletados,
mas a confirmação visual repete a senha. A versão 23.8 é antiga diante das
releases suportadas atuais e não deve ser promovida para produção.

## Pré-requisitos

Dimensione CPU, memória, SSD, retenção e cardinalidade. Imagens atuais exigem
x86-64-v3 em amd64 e requisitos específicos de ARMv8.2-A/RCpc em arm64. Planeje
o limite de arquivos, que a documentação oficial exemplifica com 262144.

## Fluxo seguro

Não execute produção com a distribuição atual. Remova a senha da confirmação,
fixe uma release suportada, homologue migração, restrinja 8123 à rede necessária
e trate credenciais fora do YAML. A rota HTTP é uma API de banco, não um painel
público comum.

## Primeiro acesso e integrações

Depois das correções, confirme a versão, usuário e banco com uma consulta sem
dados sensíveis. Langfuse e pipelines analíticos podem usar as portas HTTP 8123
ou nativa 9000 pela rede interna com usuário exclusivo e menor privilégio.

## Backup, atualização e rollback

Configure destino explícito para `BACKUP` e teste `RESTORE` em instância isolada.
Snapshot de volume sem consistência não substitui backup lógico. Antes de trocar
a imagem, preserve dados e controle de acesso, leia as notas intermediárias e
mantenha a imagem anterior disponível para rollback validado.

## Validação

Valide arquitetura da CPU, disco, memória, limites de arquivo, autenticação,
consulta HTTP e nativa, persistência e restauração.

## Diagnóstico

Separe erros de rede, usuário, quota, schema, partição, merge e pressão de disco.
Não envie consultas, senhas ou dados de clientes ao Assistente.

## Riscos e limites

Risco crítico pela release obsoleta, exposição da API por Traefik e repetição da
senha na interface. Uma réplica única não fornece alta disponibilidade. O
Assistente deve bloquear recomendação de produção até correção e homologação.
