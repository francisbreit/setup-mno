---
{"schemaVersion":1,"documentId":"blueprint-005-servidor-pequeno-knowledge","documentVersion":"0.2.0","contentSHA256":"e815db822e06721d4796a0bbb78cd1665aeb5e70a114515fb4535ad9a35b56fc","documentType":"blueprint","blueprintId":"blueprint-005-servidor-pequeno","fictitious":false,"deployable":false,"title":"Blueprint 005 — Servidor Pequeno","setupVersion":"7.48.26","architectures":["amd64","arm64"],"category":"capacity","status":"reviewed","updatedAt":"2026-08-02","sourceType":"maintainer-authored","risk":"medium","language":"pt-BR","tags":["blueprint","servidor-pequeno","capacidade","beszel","uptimekuma","adguardhome"],"sources":[{"sourceId":"blueprint-005-manifest","title":"Manifesto canônico do Blueprint 005","sourceType":"setup-mno","location":"setupmno-knowledge/blueprints/blueprint-005-servidor-pequeno/blueprint.json","license":"maintainer-owned","verifiedAt":"2026-08-02"}],"homologation":{"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}}
---
# Blueprint 005 — Servidor Pequeno

## Estado de homologação

Este é um guia Beta revisado para orientar a montagem manual. A capacidade deve ser medida no servidor de destino e cada etapa exige confirmação humana.

## Objetivo

Montar uma composição leve para observar recursos, verificar disponibilidade e avaliar filtragem DNS opcional, mantendo margem operacional em um servidor pequeno.

## Topologia

O Beszel mede a baseline e a evolução de CPU, memória e disco. O Uptime Kuma verifica poucos alvos autorizados. O AdGuard Home é opcional e só pode ser considerado depois da revisão de rede, conflitos e estratégia reversível de DNS.

## Componentes

- BESZEL: baseline e visibilidade leve do host.
- UPTIMEKUMA: verificações simples de disponibilidade.
- ADGUARDHOME: filtragem DNS opcional e condicionada ao gate de rede.

## Pré-requisitos

A estimativa preliminar é de 2 GB de RAM mínima e 4 GB recomendada, em amd64 ou arm64. Serviços-base, sistema operacional, picos, atualizações, retenção e crescimento exigem margem adicional. A memória disponível deve ser medida, não inferida pelo total.

## Ordem segura

1. Preparar o Beszel e observar a baseline até estabilização.
2. Adicionar poucos alvos de laboratório no Uptime Kuma e medir novamente.
3. Revisar rede e conflitos antes de considerar o AdGuard Home.
4. Testar DNS somente com cliente descartável e retorno previamente definido.

## Validação

Após estabilização deve existir margem documentada para picos e atualizações. Retenção e alerta de disco precisam de limites explícitos. O cliente DNS de laboratório deve retornar ao resolvedor anterior sem afetar os demais serviços.

## Riscos e limites

A estimativa não inclui toda carga existente. Alterar DNS pode interromper resolução e acesso a serviços. Logs e históricos podem crescer. Um único nó permanece ponto único de falha e não oferece alta disponibilidade.

## Rollback

Retornar primeiro o cliente de laboratório ao resolvedor anterior, remover somente alvos temporários e restaurar a baseline documentada antes de qualquer nova tentativa.
