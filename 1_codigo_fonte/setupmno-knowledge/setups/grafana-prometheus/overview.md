---
{
  "schemaVersion": 1,
  "documentId": "setup-grafana-prometheus-overview",
  "documentVersion": "1.0.2",
  "contentSHA256": "be066946d489605feb172e5e079a607d7b416e501f5b86a0e6a00f24d331fcc3",
  "documentType": "setup",
  "title": "Grafana e Prometheus no Setup MNO",
  "setupId": "grafana-prometheus",
  "setupVersion": "7.48.27",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-07-30",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["grafana", "prometheus", "observabilidade"],
  "sources": [
    {
      "sourceId": "grafana-prometheus-installer",
      "title": "Instalador Grafana e Prometheus",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/grafana.sh",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    },
    {
      "sourceId": "grafana-prometheus-catalog",
      "title": "Entrada Grafana e Prometheus no catálogo",
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
# Grafana e Prometheus no Setup MNO

## Quando usar

Use quando a operação precisa de séries temporais, dashboards e visão
detalhada de infraestrutura. Para um painel mais leve e simples, avalie Beszel.

## Arquitetura no Setup MNO

O setup reúne Grafana, Prometheus, coletor de recursos do nó e coletor de
containers. Volumes preservam dashboards e métricas, enquanto somente a
interface necessária recebe rota pública.

## Pré-requisitos

Exige infraestrutura-base, domínio, armazenamento para retenção e política de
acesso. O operador deve definir quais métricas são necessárias para evitar
coleta e retenção excessivas.

## Fluxo seguro

O instalador coleta domínio, usuário e senha pelo Whiptail, gera configurações
de coleta, cria volumes e implanta a stack via Portainer ou Docker. A senha não
é exposta ao Assistente.

## Validação

Confirme réplicas de todos os componentes, origem de dados ativa e dashboard
com métricas recentes. Uma interface Grafana disponível sem alvos saudáveis
não conclui a instalação.

## Riscos e limites

Coleta ampla aumenta uso de disco e pode revelar detalhes internos. O
Assistente recebe somente métricas agregadas e sanitizadas. Defina retenção,
backup dos dashboards e controle de acesso.

## Diagnóstico

Dashboard vazio exige verificar origem de dados, alvos e janela de consulta.
Falha apenas em um coletor deve ser isolada do restante da stack antes de
qualquer mudança.
