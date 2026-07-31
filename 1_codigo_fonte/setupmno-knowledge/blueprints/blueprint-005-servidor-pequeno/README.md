# Servidor Pequeno com Ferramentas Leves

> EXEMPLO FICTÍCIO. Não representa dimensionamento homologado.

## Objetivo

Demonstrar uma composição conservadora para obter visibilidade, disponibilidade e DNS opcional em servidor pequeno.

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

Meça primeiro, adicione poucos monitores e somente depois avalie a camada DNS. Pare se a margem operacional ficar insuficiente.

## Validação

Registre memória, disco, saúde dos alvos e reversão do DNS em um cliente descartável.

## Riscos e limites

Um servidor pequeno pode ficar saudável em repouso e falhar durante picos. DNS incorreto pode afetar todos os serviços. Os valores são apenas exemplos.

## Rollback

Restaure a resolução anterior, remova alvos temporários e compare o ambiente com a baseline inicial.

## Vídeos e links

- [Guia fictício de capacidade](https://docs.setupmno.invalid/blueprints/005/capacidade)

## Promoção para produção

Exige medições reais, teste de conflito, alertas de capacidade e validação de rollback em ambiente isolado.
