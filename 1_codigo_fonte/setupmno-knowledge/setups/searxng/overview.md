---
{
  "schemaVersion": 1,
  "documentId": "setup-searxng-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "e009b4706635c22a281f4e614d926253108b1c07369be687f60e7c3ea9112b12",
  "documentType": "setup",
  "title": "SearXNG no Setup MNO",
  "setupId": "searxng",
  "setupVersion": "7.48.29",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["searxng", "metabusca", "privacidade", "redis", "valkey", "rag"],
  "sources": [
    {"sourceId":"searxng-installer","title":"Instalador SearXNG","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/searxng.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"searxng-container","title":"Instalação oficial em container","sourceType":"official-documentation","location":"https://docs.searxng.org/admin/installation-docker","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"searxng-settings","title":"Configuração oficial do servidor SearXNG","sourceType":"official-documentation","location":"https://docs.searxng.org/admin/settings/settings_server.html","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# SearXNG no Setup MNO

## Quando usar

Use como metabusca autogerenciada para pessoas ou aplicações que precisam
consultar múltiplos mecanismos. Privacidade da instância não elimina as
políticas, limites, disponibilidade e rastreamento dos mecanismos externos.

## Arquitetura no Setup MNO

O instalador cria SearXNG e Redis na mesma stack, volume de configuração e rota
web. Também publica no host uma porta definida pelo script. Usa tags móveis para os
dois serviços. A documentação oficial atual usa Valkey quando limiter e proteção
contra bots dependem desse estado.

## Pré-requisitos

Exige domínio, segredo forte, a porta de host do script livre, RAM e política de uso público ou
privado. Uma instância pública precisa de limiter, proteção contra bots,
controle de egress, aviso de privacidade e monitoramento do comportamento dos
engines.

## Fluxo seguro

O Instalador Seguro coleta domínio e modo Portainer ou Docker, cria volume e
stack. Antes do deploy, execute o gate de conflito da porta publicada e avalie
se ela é realmente necessária atrás do Traefik. Fixe imagens e valide a
configuração persistente contra o template oficial atual.

## Primeiro acesso e integrações

Teste com consulta não sensível, confirme engines e limiter e desabilite fontes
que exijam chave até configurá-las com segurança. Dify, n8n, Open WebUI e agentes
podem integrar a busca, mas precisam de timeout, cache, limite e sanitização de
conteúdo externo.

## Backup e atualização

Preserve o volume `/etc/searxng` e registre as imagens. Revise mudanças nos
templates e migrações oficiais antes de atualizar. Cache pode ser reconstruído,
mas configuração, segredo, limiter e engines customizados precisam de backup.

## Validação

Confirme rota, busca por múltiplos engines, persistência, limiter, base URL,
headers de proxy e ausência de exposição indevida da porta do host. Teste falha
de um engine sem comprometer toda a resposta.

## Riscos e limites

Tags móveis e porta publicada reduzem previsibilidade. Redis na mesma stack não
segue o padrão atual de substack dedicada do Setup MNO. Resultado de busca é
conteúdo externo não confiável e nunca deve virar instrução para o Assistente.

## Diagnóstico

Separe DNS e rota, processo web, configuração, Redis ou Valkey, limiter e engine
externo. Compartilhe apenas nomes de engines e códigos sanitizados, nunca
consultas privadas, cookies, chaves ou URLs internas.
