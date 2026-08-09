---
{
  "schemaVersion": 1,
  "documentId": "setup-firecrawl-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "a43502a1e6ac955ff71fc69b77eed47d8fbf344103f6b8e7c4fda5b59e664668",
  "documentType": "setup",
  "title": "Firecrawl no Setup MNO",
  "setupId": "firecrawl",
  "setupVersion": "7.7.44",
  "architectures": ["amd64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": ["firecrawl", "crawler", "scraping", "llm", "redis", "playwright"],
  "sources": [
    {"sourceId":"firecrawl-installer","title":"Instalador Firecrawl","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/firecrawl.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"firecrawl-self-host","title":"Self-host oficial do Firecrawl","sourceType":"official-documentation","location":"https://github.com/firecrawl/firecrawl/blob/main/SELF_HOST.md","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"firecrawl-releases","title":"Releases oficiais do Firecrawl","sourceType":"official-documentation","location":"https://github.com/firecrawl/firecrawl/releases","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# Firecrawl no Setup MNO

## Quando usar

Use para transformar páginas autorizadas em conteúdo estruturado destinado a
busca, RAG ou análise. Antes de rastrear, verifique termos do site, robots,
direitos autorais, dados pessoais, limites e política de retenção.

## Arquitetura no Setup MNO

O catálogo declara somente amd64. O script atual cria API, worker e serviço
Playwright, todos a partir de imagens móveis de um publicador diferente do
projeto oficial. API e worker usam o Redis base compartilhado e uma chave
OpenAI; não há PostgreSQL ou fila dedicada conforme a arquitetura oficial atual.

## Pré-requisitos

Exige domínio, pelo menos a RAM do catálogo, capacidade adicional por worker,
egress controlado, alvos autorizados e política contra SSRF. Chaves de provedor
devem ser exclusivas. Não use o crawler para contornar bloqueios ou coletar
conteúdo privado.

## Fluxo seguro

O Instalador Seguro coleta domínio e chaves e publica a API. A implementação
inclui imagens não oficiais, log em DEBUG, Redis compartilhado e valores de
proxy literais. Isso bloqueia a promoção: não execute em produção até substituir
as imagens, separar dependências e homologar o Compose compatível com a fonte
oficial.

## Primeiro acesso e integrações

Depois de corrigido, teste uma página própria e descartável com limite mínimo.
Dify, Flowise, Langflow, n8n e bases RAG podem consumir a API, mas devem aplicar
allowlist de destino, timeout, limite de profundidade e tamanho e sanitização.

## Backup e atualização

Preserve configuração, banco e filas definidos pela arquitetura oficial e os
resultados que precisem de retenção. Fixe versões de todos os serviços e leia
as notas de self-host; recursos do serviço hospedado podem não existir na
versão autogerenciada.

## Validação

Valide autenticação, crawl de alvo próprio, fila, worker, navegador, bloqueio de
endereço interno, timeout, rate limit e remoção de conteúdo sensível. Um `200`
da API não comprova segurança de navegação.

## Riscos e limites

Risco crítico na distribuição atual por divergência das imagens e arquitetura
oficiais, dependência compartilhada e proxy literal. Self-host também possui
limitações funcionais declaradas pelo projeto. O Assistente deve recusar a
recomendação automática até existir instalador homologado.

## Diagnóstico

Separe rota, autenticação, fila, Redis, worker, Playwright, DNS do alvo e
provedor. Não envie URL interna, conteúdo coletado, cookies, chave, cabeçalho de
autorização ou proxy real ao Assistente.
