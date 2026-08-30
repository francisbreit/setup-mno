---
{
  "schemaVersion": 1,
  "documentId": "setup-beszel-overview",
  "documentVersion": "1.0.2",
  "contentSHA256": "74f099535757b6716a8a2d9d5d6b8a2fa5bf03246c87bd252c4625043871efc6",
  "documentType": "setup",
  "title": "Beszel no Setup MNO",
  "setupId": "beszel",
  "setupVersion": "7.42.2",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-07-30",
  "sourceType": "setup-mno",
  "risk": "low",
  "language": "pt-BR",
  "tags": ["beszel", "monitoramento", "metricas"],
  "sources": [
    {
      "sourceId": "beszel-installer",
      "title": "Instalador Beszel",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/beszel.sh",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    },
    {
      "sourceId": "beszel-catalog",
      "title": "Entrada Beszel no catálogo",
      "sourceType": "setup-mno",
      "location": "setupmno-control/catalog.json",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    }
  ],
  "homologation": {
    "verifiedAt": null,
    "verifiedPorts": [],
    "verifiedImages": []
  }
}
---
# Beszel no Setup MNO

## Quando usar

Use como painel leve de monitoramento quando o objetivo é acompanhar recursos
de servidores com baixa sobrecarga. Para retenção extensa, alertas complexos e
consultas avançadas, compare o stack Grafana e Prometheus.

## Arquitetura no Setup MNO

O instalador cria o hub com volume persistente próprio, redes interna e externa
e rota compatível com o modo de publicação escolhido. Agentes monitorados são
associados posteriormente pela interface da aplicação.

## Pré-requisitos

Exige infraestrutura-base saudável, domínio e planejamento de como cada agente
será autenticado. O consumo de catálogo cobre o hub e não representa todos os
servidores monitorados.

## Fluxo seguro

O Instalador Seguro coleta domínio e modo de deploy, prepara publicação, cria o
volume e implanta o hub. Dados de pareamento dos agentes não devem ser enviados
ao Assistente.

## Validação

Confirme acesso ao hub, persistência da configuração e recebimento de métricas
de um agente de teste. Um painel disponível sem métricas não significa
monitoramento funcional.

## Riscos e limites

Métricas podem revelar nomes e características internas. O contexto enviado à
LLM deve permanecer agregado e sanitizado. A perda do volume remove a
configuração do hub.

## Diagnóstico

Se o hub está indisponível, examine réplica e rota. Se apenas um servidor está
sem métricas, concentre o diagnóstico no agente e na conectividade, sem expor
identificadores do host.
