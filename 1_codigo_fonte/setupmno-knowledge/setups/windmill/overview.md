---
{
  "schemaVersion": 1,
  "documentId": "setup-windmill-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "8bdea97f3e7db6838b2347b4451d939046bf792d3c944cc3e92b683e5273af26",
  "documentType": "setup",
  "title": "Windmill no Setup MNO",
  "setupId": "windmill",
  "setupVersion": "7.18.0",
  "architectures": [
    "amd64",
    "arm64"
  ],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": [
    "windmill",
    "scripts",
    "workflows",
    "execucao-de-codigo"
  ],
  "sources": [
    {
      "sourceId": "windmill-installer",
      "title": "Instalador Windmill",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/windmill.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "windmill-selfhost",
      "title": "Documentação oficial de self-host do Windmill",
      "sourceType": "official-documentation",
      "location": "https://www.windmill.dev/docs/advanced/self_host",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "windmill-security",
      "title": "Segurança e isolamento oficiais do Windmill",
      "sourceType": "official-documentation",
      "location": "https://www.windmill.dev/docs/advanced/security_and_isolation",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    }
  ],
  "homologation": {
    "verifiedAt": null,
    "verifiedPorts": [],
    "verifiedImages": []
  }
}
---
# Windmill no Setup MNO

## Quando usar

Use para scripts, jobs, workflows e aplicações internas quando execução de código for um requisito explícito. Não o trate como automação sem risco: workers executam código e recebem credenciais.

## Arquitetura no Setup MNO

O instalador simplifica a topologia Windmill em relação à arquitetura oficial de servidor, Postgres e workers. Valide quais modos realmente existem na stack antes de prometer execução completa.

## Pré-requisitos

O catálogo declara cerca de 512 MB de RAM, mas a documentação oficial relaciona cada worker a CPU e memória próprias; a referência não cobre jobs arbitrários.

Exige domínio HTTPS, Postgres, workers dimensionados, isolamento e política de secrets. A recomendação oficial relaciona workers a CPU e memória e prevê proteção adicional para jobs.

## Fluxo seguro

Não monte socket Docker nem host nos workers sem caso aprovado. Use grupos, secrets de menor privilégio, timeouts e filas separadas para código não confiável.

## Primeiro acesso e integrações

Troque credenciais iniciais, crie script inofensivo e valide fila, cancelamento e logs. Só adicione uma integração real depois de revisar o secret e o código.

## Backup e atualização

Preserve Postgres e configuração; jobs e scripts fazem parte do estado. Pare ou drene workers, fixe versão e teste restore e retomada.

## Validação

Confirme modos server e worker, autenticação, fila, cancelamento, isolamento, backup e restore. Verifique ausência de socket Docker e mounts amplos.

## Riscos e limites

Execução de código e credenciais tornam o risco crítico. Uma stack sem worker, isolamento ou secret adequado pode parecer saudável sem cumprir o objetivo.

## Diagnóstico

Separe proxy, servidor, Postgres, fila, worker, runtime, secret e job. Use script sintético sem rede nem credenciais.
