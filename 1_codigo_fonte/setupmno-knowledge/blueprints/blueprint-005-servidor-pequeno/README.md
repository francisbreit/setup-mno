# Servidor Pequeno com Ferramentas Leves

> GUIA BETA. Pode ser seguido manualmente, mas o dimensionamento deve ser confirmado no servidor de destino.

## Objetivo

Orientar uma composição conservadora para obter visibilidade, disponibilidade e DNS opcional em servidor pequeno.

## Arquitetura

Beszel mede a baseline, Uptime Kuma verifica poucos alvos e AdGuard Home representa uma camada DNS opcional que exige revisão de rede.

## Componentes

| Ordem | Setup | Responsabilidade |
|---|---|---|
| 1 | BESZEL | Baseline leve |
| 2 | UPTIMEKUMA | Disponibilidade |
| 3 | ADGUARDHOME | DNS opcional |

## Pré-requisitos

- Memória e disco medidos antes da instalação.
- Margem para serviços-base e atualizações.
- Gate de conflito de rede antes do componente DNS.

## Ordem de instalação

Meça primeiro, instale o Beszel, crie a conta e registre a baseline. Adicione poucos monitores no Uptime Kuma e somente depois avalie o AdGuard Home. Crie a conta, revise portas e altere o DNS de apenas um cliente piloto. Pare se a margem operacional ficar insuficiente.

## Validação

Registre memória, disco, saúde dos alvos e reversão do DNS em um cliente descartável.

## Riscos e limites

Um servidor pequeno pode ficar saudável em repouso e falhar durante picos. DNS incorreto pode afetar todos os serviços. Os valores são estimativas preliminares.

## Rollback

Restaure a resolução anterior, remova alvos temporários e compare o ambiente com a baseline inicial.

## Downloads, vídeos e PDFs

- O ZIP deste Blueprint está disponível no Control Center.
- PDF com checklist de capacidade: em preparação.

## Homologação futura

Exige medições reais, teste de conflito, alertas de capacidade e validação de rollback em ambiente isolado.
