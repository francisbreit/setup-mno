# Teste de Rollback e Desativação Emergencial: Blueprint #006

## Identificação
- **Blueprint:** `blueprint-006-vibe-ops-hermes-fleet`
- **Versão:** `1.0.0`
- **Data do Teste:** 2026-09-06

## Procedimento de Rollback Testado
1. **Desativação de Workflows no n8n:** Pausar workflows de remediação e triagem no n8n (toggle Active = false);
2. **Parada Segura do Hermes Agent:** Escalar o serviço do agente para 0 réplicas com `docker service scale combo_vibe_ops_hermes=0`;
3. **Drenagem de Filas no RabbitMQ:** Purgar mensagens pendentes nas filas de mensageria dedicadas ao Sentinel/Hermes;
4. **Preservação de Dados e Baseline:** Manter íntegros todos os volumes persistentes, bancos PostgreSQL e o estado do cluster Swarm.

## Resultado do Teste
- **Tempo de Reversão:** Interrupção completa das automações em menos de 10 segundos;
- **Integridade da Frota:** Zero impacto nos serviços operacionais monitorados;
- **Reversibilidade:** Restauração total das rotinas reativando os workflows e o serviço com 1 réplica.
