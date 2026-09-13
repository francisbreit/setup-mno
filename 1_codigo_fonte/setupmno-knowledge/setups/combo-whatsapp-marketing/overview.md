---
{
  "schemaVersion": 1,
  "documentId": "setup-combo-whatsapp-marketing-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "c93c7a51ba95400333e782b3989508b1124aad348d195dbab3669dc9a2a4b0e1",
  "documentType": "setup",
  "title": "Combo WhatsApp Marketing Completo no Setup MNO",
  "setupId": "combo-whatsapp-marketing",
  "setupVersion": "7.47.0",
  "architectures": [
    "amd64",
    "arm64"
  ],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-09-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": [
    "whatsapp",
    "marketing",
    "chatwoot",
    "evolution-api",
    "rabbitmq",
    "minio",
    "mautic",
    "n8n",
    "typebot",
    "combo",
    "blueprint"
  ],
  "sources": [
    {
      "sourceId": "combo-whatsapp-marketing-installer",
      "title": "Instalador Combo WhatsApp Marketing Completo",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/combo_whatsapp_marketing.sh",
      "license": "project-internal",
      "verifiedAt": "2026-09-01"
    },
    {
      "sourceId": "combo-whatsapp-marketing-official-1",
      "title": "Documentação oficial do Chatwoot",
      "sourceType": "official-documentation",
      "location": "https://developers.chatwoot.com/self-hosted/deployment/architecture",
      "license": "documentation-reference",
      "verifiedAt": "2026-09-01"
    },
    {
      "sourceId": "combo-whatsapp-marketing-official-2",
      "title": "Documentação oficial da Evolution API",
      "sourceType": "official-documentation",
      "location": "https://doc.evolution-api.com/",
      "license": "documentation-reference",
      "verifiedAt": "2026-09-01"
    },
    {
      "sourceId": "blueprint-001-reference",
      "title": "Manifesto do Blueprint 001",
      "sourceType": "setup-mno",
      "location": "setupmno-knowledge/blueprints/blueprint-001-whatsapp-marketing-completo/blueprint.json",
      "license": "maintainer-owned",
      "verifiedAt": "2026-09-01"
    }
  ],
  "homologation": {
    "verifiedAt": null,
    "verifiedPorts": [],
    "verifiedImages": []
  }
}
---
# Combo WhatsApp Marketing Completo no Setup MNO

## Quando usar

Use para instalar em lote toda a stack de automação e atendimento do Blueprint #001 (WhatsApp Marketing Completo), integrando Chatwoot, Evolution API v2, RabbitMQ, MinIO, Mautic 7, n8n em modo fila e Typebot. A recomendação deve considerar a memória RAM disponível e a finalidade de marketing conversacional.

## Arquitetura no Setup MNO

O combo executa a sequência integrada de deploys no Docker Swarm conectando todos os serviços na rede interna segura `rede-mno`, compartilhando o PostgreSQL central e provisionando filas RabbitMQ e armazenamento S3 no MinIO.

## Pré-requisitos

Exige servidor com no mínimo 8 GB de RAM, domínios/subdomínios previamente apontados para o host (Cloudflare ou DNS direto), serviços-base (PostgreSQL e Traefik) ativos e portas internas liberadas.

## Fluxo seguro

Execute pelo instalador interativo Whiptail do Setup MNO selecionando a opção do combo. O assistente valida os pré-requisitos, solicita os domínios de cada ferramenta e executa a instalação encadeada sem expor credenciais.

## Primeiro acesso e integrações

Após a instalação, configure as instâncias no Evolution API, crie a caixa de entrada no Chatwoot conectada via webhook, importe os templates do Typebot e os workflows de aquecimento e envio no n8n.

## Backup e atualização

Realize o backup consolidado dos bancos PostgreSQL (Chatwoot, Evolution, Mautic, n8n, Typebot) e dos volumes persistentes de dados e mídias do MinIO antes de realizar qualquer atualização de imagem.

## Validação

Confirme o funcionamento individual de cada URL pública sob HTTPS, o envio e recebimento de webhooks entre Typebot, n8n e Evolution API, e o registro correto dos leads no Mautic 7.

## Riscos e limites

Exige atenção rigorosa às políticas de anti-bloqueio do WhatsApp, respeitando limites de envio gradual e aquecimento de chips. A execução consome recursos intensivos de memória durante picos de campanha.

## Diagnóstico

Em caso de falha de conexão ou 502, inspecione os logs individuais de cada stack via Docker Swarm (`docker service logs`), valide a conectividade com o banco PostgreSQL e verifique o status das filas no RabbitMQ Management.
