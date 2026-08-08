---
{
  "schemaVersion": 1,
  "documentId": "setup-redisinsight-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "eecf8a9cc8da2f3c695e0fdaf39712737fa6a0b811b52385419cda94495eda2e",
  "documentType": "setup",
  "title": "Redis Insight no Setup MNO",
  "setupId": "redisinsight",
  "setupVersion": "7.7.34",
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
    "redisinsight",
    "redis",
    "monitoramento",
    "imagem-legada"
  ],
  "sources": [
    {
      "sourceId": "redisinsight-installer",
      "title": "Instalador Redis Insight",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/redisinsight.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "redisinsight-docker",
      "title": "Instalação oficial do Redis Insight em Docker",
      "sourceType": "official-documentation",
      "location": "https://redis.io/docs/latest/operate/redisinsight/install/install-on-docker/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "redisinsight-docs",
      "title": "Documentação oficial do Redis Insight",
      "sourceType": "official-documentation",
      "location": "https://redis.io/docs/latest/develop/tools/insight/",
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
# Redis Insight no Setup MNO

## Quando usar

Use para análise e administração visual de Redis, incluindo chaves e memória, por operador autorizado. Prefira métricas de somente leitura quando não houver necessidade de editar dados.

## Arquitetura no Setup MNO

O instalador ainda referencia o namespace legado da imagem RedisInsight, enquanto a documentação oficial atual usa outro namespace e caminho de persistência. Essa divergência deve bloquear homologação até validação.

## Pré-requisitos

O catálogo declara cerca de 1 GB de RAM para a interface; análises de memória e a instância Redis precisam de capacidade adicional.

Exige domínio HTTPS, autenticação, volume da interface e Redis restrito à rede interna. Planeje impacto de análises de memória sobre bases grandes.

## Fluxo seguro

Use credencial de menor privilégio, autenticação adicional e janela controlada. Dados e valores de chaves nunca devem ser enviados ao Assistente.

## Primeiro acesso e integrações

Conecte a uma instância de teste, valide TLS e confirme o banco correto. Não habilite edição produtiva sem backup e autorização.

## Backup e atualização

Faça backup do Redis e, se necessário, dos metadados da interface. Migre namespace e dados somente após teste isolado e mantenha rollback.

## Validação

Confirme imagem efetiva, healthcheck, persistência, autenticação e conexão a uma Redis de teste. Bloqueie promoção se a imagem legada não for compatível com a documentação atual.

## Riscos e limites

A interface manipula dados críticos; análises podem gerar carga. Namespace legado, tag flutuante e exposição pública elevam o risco.

## Diagnóstico

Separe imagem, proxy, interface, volume, TLS, credencial e Redis. Use uma chave sintética e logs sanitizados.
