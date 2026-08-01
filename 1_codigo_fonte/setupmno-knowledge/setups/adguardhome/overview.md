---
{
  "schemaVersion": 1,
  "documentId": "setup-adguardhome-overview",
  "documentVersion": "1.0.2",
  "contentSHA256": "cc8380578baf8e1907bcf1404b741cc6daf2e6cf7a2e3cf6460debc37f2d5520",
  "documentType": "setup",
  "title": "AdGuard Home no Setup MNO",
  "setupId": "adguardhome",
  "setupVersion": "7.2.3",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-07-30",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["adguardhome", "dns", "privacidade"],
  "sources": [
    {
      "sourceId": "adguardhome-installer",
      "title": "Instalador AdGuard Home",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/adguardhome.sh",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    },
    {
      "sourceId": "adguardhome-catalog",
      "title": "Entrada AdGuard Home no catálogo",
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
# AdGuard Home no Setup MNO

## Quando usar

Use para filtragem DNS de anúncios, rastreadores e domínios maliciosos em uma
rede controlada. Não trate a ferramenta como substituta de firewall, proteção
de endpoint ou política de acesso.

## Arquitetura no Setup MNO

A stack mantém volumes separados para dados de trabalho e configuração,
participa das redes interna e externa e publica o serviço DNS diretamente no
host, além da interface web roteada.

## Pré-requisitos

O serviço DNS do host deve estar livre e a mudança precisa ser planejada para
não interromper a resolução existente. A infraestrutura-base, a rota escolhida
e o volume persistente devem estar disponíveis.

## Fluxo seguro

O instalador alerta sobre o conflito do resolvedor do sistema, coleta domínio
e modo de deploy, prepara a publicação e cria volumes. Mudanças no resolvedor
do host exigem ação humana consciente.

## Validação

Confirme a réplica, abertura da interface e resolução de um domínio de teste a
partir de um cliente controlado. Diferencie falha do painel, falha de DNS e
bloqueio causado por regra.

## Riscos e limites

Uma configuração incorreta pode interromper a resolução de toda a rede.
Listas externas podem bloquear destinos legítimos. Preserve configuração e
tenha um resolvedor anterior documentado como rollback.

## Diagnóstico

Em indisponibilidade geral, confirme conflito do serviço DNS e estado da
réplica. Em bloqueio seletivo, revise filtros e consulta registrada sem expor
histórico de navegação ao Assistente.
