---
{
  "schemaVersion": 1,
  "documentId": "setup-autogen-studio-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "686e21e50b54f6910e414947097db4bcb6015ed3fd808bd910c636a296b3ce48",
  "documentType": "setup",
  "title": "AutoGen Studio no Setup MNO",
  "setupId": "autogen-studio",
  "setupVersion": "7.48.22",
  "architectures": [
    "amd64",
    "arm64"
  ],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": [
    "autogen-studio",
    "ia",
    "agentes",
    "prototipagem"
  ],
  "sources": [
    {
      "sourceId": "autogen-studio-installer",
      "title": "Instalador AutoGen Studio",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/autogen.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "autogen-studio-official-1",
      "title": "Documentação oficial de AutoGen Studio",
      "sourceType": "official-documentation",
      "location": "https://microsoft.github.io/autogen/stable/user-guide/autogenstudio-user-guide/",
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
# AutoGen Studio no Setup MNO

## Quando usar

Use para prototipar equipes e fluxos de agentes de IA por uma interface web. A recomendação deve considerar finalidade, dados tratados, manutenção e alternativa mais simples; a existência no catálogo não significa homologação automática.

## Arquitetura no Setup MNO

O instalador constrói no início do contêiner um ambiente Python e inicia o AutoGen Studio atrás do Traefik ou do túnel. O serviço mantém o diretório da aplicação em volume persistente, mas a instalação dinâmica e a ausência de versão imutável reduzem a reprodutibilidade.

## Pré-requisitos

Exige domínio com HTTPS, memória compatível, provedor de modelo e chave criada fora da conversa. Defina previamente se o ambiente é apenas laboratório ou se tratará dados reais.

## Fluxo seguro

Execute somente pelo Instalador Seguro, confirme o resumo antes do deploy e não publique portas administrativas adicionais. Credenciais permanecem fora do Assistente e operações reais continuam sujeitas à confirmação humana.

## Primeiro acesso e integrações

Abra o Studio, configure um provedor com credencial de teste e crie um fluxo mínimo sem ferramentas de alto privilégio. A autenticação do Studio é experimental; não exponha uma instância sem controle de acesso adicional.

## Backup e atualização

Preserve o volume da aplicação, exporte configurações dos times e registre versões de Python e pacotes. Antes de atualizar, clone o volume ou use dados fictícios em uma instância isolada.

## Validação

Confirme HTTPS, autenticação, persistência após recriação controlada, saúde das réplicas e o fluxo funcional mínimo com dados fictícios. Registre versões efetivas e evidências sem segredos; só promova após um teste de restauração aplicável.

## Riscos e limites

É uma superfície de prototipagem, não um executor automaticamente seguro. Agentes podem produzir chamadas e conteúdo não confiável. O build em tempo de inicialização e dependências flutuantes exigem revisão antes de uso produtivo.

## Diagnóstico

Separe falha de build Python, inicialização do Studio, rota HTTPS e credencial do provedor. Use logs sanitizados e nunca envie chaves, prompts privados ou conteúdo de usuários ao Assistente.
