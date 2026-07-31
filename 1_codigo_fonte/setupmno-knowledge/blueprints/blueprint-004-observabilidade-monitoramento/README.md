# Observabilidade e Monitoramento

> EXEMPLO FICTÍCIO. Retenção, alertas e capacidade não foram homologados.

## Objetivo

Demonstrar responsabilidades separadas para saúde do host, métricas detalhadas e disponibilidade externa.

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

Comece pela visão leve, acrescente métricas detalhadas com retenção limitada e finalize com testes externos controlados.

## Validação

Valide métrica recente, alerta de queda e encerramento do incidente. Use somente um alvo temporário criado para o teste.

## Riscos e limites

Coleta excessiva aumenta cardinalidade e armazenamento. Alertas sem responsável geram ruído. Os números deste exemplo não são garantia de capacidade.

## Rollback

Remova os alvos temporários, suspenda alertas e restaure dashboards e retenção da versão anterior.

## Vídeos e links

- [Vídeo fictício sobre camadas de monitoramento](https://videos.setupmno.invalid/blueprints/004/camadas)

## Promoção para produção

Exige retenção medida, testes de alerta, responsáveis, backup dos dashboards e evidência de restauração.
