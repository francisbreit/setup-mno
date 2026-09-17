---
{
  "schemaVersion": 1,
  "documentId": "setup-hermes-agent-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "d1ce8c1d54630f78162f72c255076b69641df5e462a28b9cc47764b25325d93f",
  "documentType": "setup",
  "title": "Hermes Agent no Setup MNO",
  "setupId": "hermes-agent",
  "setupVersion": "7.48.9",
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
    "hermes-agent",
    "ia",
    "agente",
    "ferramentas"
  ],
  "sources": [
    {
      "sourceId": "hermes-agent-installer",
      "title": "Instalador Hermes Agent",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/hermes.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "hermes-agent-official-1",
      "title": "Documentação oficial de Hermes Agent",
      "sourceType": "official-documentation",
      "location": "https://hermes-agent.nousresearch.com/docs/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "hermes-agent-official-2",
      "title": "Documentação oficial de Hermes Agent",
      "sourceType": "official-documentation",
      "location": "https://github.com/NousResearch/hermes-agent",
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
# Hermes Agent no Setup MNO

## Quando usar

Use para experimentar um agente autônomo com memória, ferramentas e integrações de comunicação. A recomendação deve considerar finalidade, dados tratados, manutenção e alternativa mais simples; a existência no catálogo não significa homologação automática.

## Arquitetura no Setup MNO

O instalador empacota o Hermes Agent conforme o script do Setup e o expõe no fluxo escolhido. O produto pode executar ferramentas, criar memória e conectar gateways, portanto precisa de isolamento mais forte que um chatbot comum.

## Pré-requisitos

Exige provedor e modelo com contexto compatível, política explícita de ferramentas, aprovação humana e ambiente descartável. Defina dados permitidos, orçamento e canais antes de ativar gateways.

## Fluxo seguro

Execute somente pelo Instalador Seguro, confirme o resumo antes do deploy e não publique portas administrativas adicionais. Credenciais permanecem fora do Assistente e operações reais continuam sujeitas à confirmação humana.

## Primeiro acesso e integrações

Comece com conjunto de ferramentas mínimo e dados fictícios, sem shell privilegiado ou acesso ao Docker. Revise a separação entre configuração e segredos e teste o mecanismo de aprovação.

## Backup e atualização

Preserve configuração, memória e skills somente se a política permitir. Faça cópia cifrada e teste restauração sem tokens; registre versão e provedores para reproduzir comportamento.

## Validação

Confirme HTTPS, autenticação, persistência após recriação controlada, saúde das réplicas e o fluxo funcional mínimo com dados fictícios. Registre versões efetivas e evidências sem segredos; só promova após um teste de restauração aplicável.

## Riscos e limites

Agente autônomo é alto risco: ferramentas, memória e canais podem ampliar erros. A instalação no Control Center não concede autorização para ações. Nunca exponha socket Docker ou credenciais do host.

## Diagnóstico

Separe modelo, contexto, ferramenta, memória, canal e permissão. Use `doctor` e logs sanitizados; não compartilhe tokens, memória do usuário, prompts privados ou saída de comandos sensíveis.
