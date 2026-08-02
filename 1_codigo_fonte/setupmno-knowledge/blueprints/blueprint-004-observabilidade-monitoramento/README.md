# Observabilidade e Monitoramento

> GUIA BETA. Pode ser seguido manualmente, mas retenção, alertas e capacidade ainda exigem homologação no ambiente de destino.

## Objetivo

Orientar uma arquitetura com responsabilidades separadas para saúde do host, métricas detalhadas e disponibilidade externa.

## Arquitetura

Beszel fornece a camada leve, Grafana e Prometheus fornecem séries temporais e Uptime Kuma representa testes externos e alertas.

## Componentes

| Ordem | Setup | Responsabilidade |
|---|---|---|
| 1 | BESZEL | Saúde leve dos hosts |
| 2 | GRAFANA/PROMETHEUS MONITOR | Métricas e dashboards |
| 3 | UPTIMEKUMA | Disponibilidade e alertas |

## Pré-requisitos

- Inventário de alvos autorizados.
- Política de retenção.
- Responsáveis pelos alertas.
- Estimativa real de cardinalidade e armazenamento.

## Ordem de instalação

Comece pela visão leve e crie a conta administrativa. Cadastre os hosts autorizados, acrescente Prometheus e Grafana com retenção limitada, conecte a fonte e importe dashboards revisados. Finalize no Uptime Kuma com monitores, canal de alerta e teste controlado de indisponibilidade.

## Validação

Valide métrica recente, alerta de queda e encerramento do incidente. Use somente um alvo temporário criado para o teste.

## Riscos e limites

Coleta excessiva aumenta cardinalidade e armazenamento. Alertas sem responsável geram ruído. Os números preliminares não são garantia de capacidade.

## Rollback

Remova os alvos temporários, suspenda alertas e restaure dashboards e retenção da versão anterior.

## Downloads, vídeos e PDFs

- O ZIP deste Blueprint está disponível no Control Center.
- Vídeo sobre camadas de monitoramento: em preparação.

## Homologação futura

Exige retenção medida, testes de alerta, responsáveis, backup dos dashboards e evidência de restauração.
