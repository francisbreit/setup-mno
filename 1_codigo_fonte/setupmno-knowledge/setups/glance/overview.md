---
{
  "schemaVersion": 1,
  "documentId": "setup-glance-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "ef1aa11b3b3f1e7f26dbdbb2cc98b15aaac53d87cf1f9ae717a8a0b4dc995dc9",
  "documentType": "setup",
  "title": "Glance no Setup MNO",
  "setupId": "glance",
  "setupVersion": "7.38.0",
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
    "glance",
    "dashboard",
    "feeds",
    "monitoramento"
  ],
  "sources": [
    {
      "sourceId": "glance-installer",
      "title": "Instalador Glance",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/glance.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "glance-repo",
      "title": "Repositório oficial Glance",
      "sourceType": "official-documentation",
      "location": "https://github.com/glanceapp/glance",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "glance-config",
      "title": "Configuração oficial Glance",
      "sourceType": "official-documentation",
      "location": "https://github.com/glanceapp/glance/blob/main/docs/configuration.md",
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
# Glance no Setup MNO

## Quando usar

Use como painel agregado de feeds, links, clima, métricas e serviços. Não o trate como monitoramento com alertas, cofre de segredos ou controle de acesso de aplicações internas.

## Arquitetura no Setup MNO

O instalador fixa `Glance na versão 0.8.5` com digest, volume/configuração, rota e 256 MB. A fixação melhora reprodutibilidade, mas a versão precisa ser comparada à linha atual antes de atualizar.

## Pré-requisitos

Exige domínio, arquivo de configuração, fontes autorizadas e tokens de APIs opcionais. Planeje cache, limites de provedores e acesso ao painel.

## Fluxo seguro

Guarde secrets fora da página e evite URLs internas ou tokens em widgets públicos. Use autenticação/proxy conforme documentação e mantenha fontes com escopo mínimo.

## Primeiro acesso e integrações

Monte painel com dados públicos fictícios e teste cada widget, timeout e fallback. Só conecte serviços internos após revisar o que será exposto.

## Backup e atualização

Preserve configuração e eventuais secrets referenciados; o serviço é majoritariamente reconstruível. Teste a nova imagem com cópia do config e mantenha digest anterior para rollback.

## Validação

Confirme autenticação, widgets, cache, links, responsividade, limites e ausência de tokens no HTML/logs. Verifique comportamento de fonte indisponível.

## Riscos e limites

Dashboards podem vazar topologia e URLs internas. Integrações externas têm limites; configuração incompatível pode impedir boot. Não confundir painel com alerta.

## Diagnóstico

Isole widget/fonte, DNS, TLS, configuração e proxy. Compartilhe apenas config sanitizado, sem hosts ou tokens reais.
