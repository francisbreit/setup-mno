---
{
  "schemaVersion": 1,
  "documentId": "setup-dozzle-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "fd5a79c864bad25b31b60e564f23d5bc51a1a41c1b114aff399a88d7e71187a9",
  "documentType": "setup",
  "title": "Dozzle no Setup MNO",
  "setupId": "dozzle",
  "setupVersion": "7.7.52",
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
    "dozzle",
    "logs",
    "docker",
    "observabilidade"
  ],
  "sources": [
    {
      "sourceId": "dozzle-installer",
      "title": "Instalador Dozzle",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/dozzle.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "dozzle-start",
      "title": "Instalação oficial Dozzle",
      "sourceType": "official-documentation",
      "location": "https://dozzle.dev/guide/getting-started",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "dozzle-auth",
      "title": "Autenticação oficial Dozzle",
      "sourceType": "official-documentation",
      "location": "https://dozzle.dev/guide/authentication",
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
# Dozzle no Setup MNO

## Quando usar

Use para consultar logs de contêineres em ambiente administrativo controlado. Não é ferramenta para clientes finais e nunca deve ser exposta publicamente sem autenticação forte.

## Arquitetura no Setup MNO

O instalador monta `/var/run/docker.sock`, usa `Dozzle na tag latest` e publica uma porta do host para a porta web interna; a autenticação está comentada. O socket concede capacidade equivalente a root segundo a própria documentação, mesmo que ações e shell do Dozzle estejam desativados.

## Pré-requisitos

Exige operador confiável, rede administrativa, autenticação, TLS e análise de mínimo privilégio. A porta publicada deve passar pelo gate de conflito e não ficar aberta à Internet.

## Fluxo seguro

Bloqueie a implantação pública atual. Habilite autenticação, remova porta host quando houver proxy seguro e considere socket proxy somente leitura com lista mínima. Nunca exponha logs a usuários comuns.

## Primeiro acesso e integrações

Em homologação isolada, valide login e visibilidade somente dos contêineres autorizados. Confirme que não há ações, shell, download indevido ou dados sensíveis nos logs.

## Backup e atualização

Dozzle é essencialmente stateless; preserve apenas configuração de acesso. Para atualizar, fixe uma tag, teste autenticação e permissões e mantenha manifesto anterior para rollback.

## Validação

Confirme autenticação obrigatória, TLS, ausência de porta pública, escopo de contêineres, no-store e logs sanitizados. Verifique que o socket não chega a serviços desnecessários.

## Riscos e limites

Estado atual é crítico: porta publicada, ausência de autenticação, socket Docker e tag flutuante podem expor controle administrativo e segredos contidos nos logs.

## Diagnóstico

Separe proxy, autenticação, socket e filtragem. Use contêiner temporário com mensagens fictícias; não copie logs reais ao Assistente.
