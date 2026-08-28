---
{
  "schemaVersion": 1,
  "documentId": "setup-maybe-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "2d4ce175c4d07eafb70ea25dfd0d74e60d7563f0b68e18b9c6b800fde29081d9",
  "documentType": "setup",
  "title": "Maybe no Setup MNO",
  "setupId": "maybe",
  "setupVersion": "7.38.0",
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
    "maybe",
    "financas",
    "orcamento",
    "projeto-arquivado"
  ],
  "sources": [
    {
      "sourceId": "maybe-installer",
      "title": "Instalador Maybe",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/maybe.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "maybe-official",
      "title": "Repositório oficial arquivado do Maybe",
      "sourceType": "official-documentation",
      "location": "https://github.com/maybe-finance/maybe",
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
# Maybe no Setup MNO

## Quando usar

Use somente para laboratório ou continuidade consciente de uma instalação existente de finanças pessoais. O repositório oficial foi arquivado em 2025 e declara que não recebe manutenção; não recomende para uma nova operação financeira sem aceitar esse risco.

## Arquitetura no Setup MNO

O instalador executa a imagem histórica do Maybe com persistência local e integração ao banco prevista pelo script. A presença no catálogo preserva compatibilidade, mas não transforma o projeto arquivado em solução homologada.

## Pré-requisitos

O catálogo declara cerca de 512 MB de RAM como referência editorial; confirme CPU, banco e concorrência em homologação antes de aceitar essa capacidade.

Exige domínio HTTPS, armazenamento persistente, banco compatível, política de backup e entendimento de que dados financeiros são altamente sensíveis. Defina também uma alternativa mantida antes de cadastrar dados reais.

## Fluxo seguro

Instale primeiro com dados fictícios, mantenha registro da versão efetiva e não conecte contas bancárias durante a avaliação. Credenciais, saldos e extratos nunca devem ser enviados ao Assistente.

## Primeiro acesso e integrações

Crie um usuário de teste e valide importação manual, categorias e relatórios sem dados reais. Integrações externas só podem ser habilitadas após revisão de privacidade e manutenção.

## Backup e atualização

Preserve banco, anexos e configuração em cópia cifrada e teste a restauração. Como não há manutenção oficial, atualização automática por tag flutuante é especialmente arriscada.

## Validação

Confirme HTTPS, autenticação, persistência após recriação controlada, exportação e restauração. Registre a imagem efetiva e a evidência de aceite do risco de descontinuação.

## Riscos e limites

Projeto arquivado, dados financeiros e tag flutuante formam um risco crítico. Não há garantia de correções de segurança, compatibilidade futura ou suporte.

## Diagnóstico

Separe proxy, aplicação, banco, volume e importação. Use somente dados sintéticos e logs sanitizados.
