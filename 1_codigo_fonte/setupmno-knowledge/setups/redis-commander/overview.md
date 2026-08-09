---
{
  "schemaVersion": 1,
  "documentId": "setup-redis-commander-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "d72b3a9e9e6a18c20c98a234c32b0aa6d257b10087b903e66b631fb786d52ae3",
  "documentType": "setup",
  "title": "Redis Commander no Setup MNO",
  "setupId": "redis-commander",
  "setupVersion": "7.7.41",
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
    "redis-commander",
    "redis",
    "administracao",
    "credenciais"
  ],
  "sources": [
    {
      "sourceId": "redis-commander-installer",
      "title": "Instalador Redis Commander",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/redicommander.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "redis-commander-official",
      "title": "Repositório oficial do Redis Commander",
      "sourceType": "official-documentation",
      "location": "https://github.com/joeferner/redis-commander",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "redis-commander-image",
      "title": "Imagem Docker do Redis Commander",
      "sourceType": "official-documentation",
      "location": "https://hub.docker.com/r/rediscommander/redis-commander",
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
# Redis Commander no Setup MNO

## Quando usar

Use para inspeção administrativa pontual de uma instância Redis por operador autorizado. Não o exponha como painel permanente se métricas e CLI auditável bastarem.

## Arquitetura no Setup MNO

O instalador publica a interface Redis Commander e a conecta ao Redis informado no fluxo. A interface pode ler, alterar e excluir chaves conforme a credencial recebida.

## Pré-requisitos

O catálogo declara cerca de 1 GB de RAM para a interface; dimensione Redis separadamente e considere o custo de listar grandes conjuntos de chaves.

Exige domínio HTTPS, autenticação da própria interface, Redis restrito à rede interna e conta dedicada quando possível. Defina bancos e comandos permitidos.

## Fluxo seguro

Aplique autenticação adicional, acesso temporário e menor privilégio. Não cole valores de chaves, tokens, sessões ou credenciais no Assistente.

## Primeiro acesso e integrações

Conecte primeiro a Redis de teste e confirme que a interface não alcança outras instâncias. Evite edição de chaves produtivas sem janela e backup.

## Backup e atualização

O backup pertence ao Redis. Valide persistência e restauração da instância antes de qualquer operação administrativa ou atualização da interface.

## Validação

Confirme HTTPS, autenticação, rede, escopo da credencial e acesso apenas à instância esperada. Teste leitura e escrita em chave sintética.

## Riscos e limites

Uma interface Redis permite alteração imediata de sessões, filas e caches. Exposição pública ou credencial ampla transforma erro de clique em incidente.

## Diagnóstico

Separe proxy, login da interface, rede, TLS, autenticação Redis e banco lógico. Use chave sintética e nunca revele valores reais.
