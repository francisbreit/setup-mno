---
{
  "schemaVersion": 1,
  "documentId": "infra-vps-architecture",
  "documentVersion": "1.0.2",
  "contentSHA256": "0860e190fdc2d7a0a95161c453fe389cc09a1a2a848a0f36e49fd15908f53412",
  "documentType": "infrastructure",
  "title": "Baseline de VPS para o Setup MNO",
  "topicId": "vps",
  "setupVersion": "7.32.1",
  "architectures": ["amd64", "arm64"],
  "category": "capacity",
  "status": "reviewed",
  "updatedAt": "2026-07-30",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["vps", "capacidade", "compatibilidade"],
  "sources": [
    {
      "sourceId": "bootstrap-standard-script",
      "title": "Bootstrap padrão do Setup MNO",
      "sourceType": "setup-mno",
      "location": "setup-mno.sh",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    },
    {
      "sourceId": "bootstrap-oracle-script",
      "title": "Bootstrap Oracle do Setup MNO",
      "sourceType": "setup-mno",
      "location": "setup-mno-oracle.sh",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    }
  ],
  "homologation": {
    "verifiedAt": null,
    "verifiedPorts": [],
    "verifiedImages": []
  }
}
---
# Baseline de VPS para o Setup MNO

## Papel no Setup MNO

A VPS fornece sistema operacional, memória, armazenamento e conectividade para
o Swarm. O bootstrap prepara uma instalação Debian ou Ubuntu e seleciona os
artefatos compatíveis com a arquitetura detectada.

## Princípios

Capacidade deve considerar serviços-base, aplicação, dependências dedicadas e
margem operacional. A recomendação usa o catálogo como referência inicial e
deve destacar quando consumo real depende de usuários, filas, arquivos ou
modelos de IA.

## Validação

O diagnóstico compara memória total e disponível com os requisitos conhecidos,
confirma arquitetura e identifica conflitos de serviços antes da instalação.
Dados de hostname, endereço e provedor não são necessários para essa análise.

## Riscos e limites

Instalar no limite de memória causa degradação e reinícios. Estimativas do
catálogo não substituem medição após a carga real. O Assistente deve declarar
incerteza, recomendar margem e impedir Ollama quando o baseline mínimo não for
atendido.
