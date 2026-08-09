---
{
  "schemaVersion": 1,
  "documentId": "setup-ollama-openwebui-overview",
  "documentVersion": "1.0.2",
  "contentSHA256": "87e8ffffb21cf18c8ccfcb18ad950864f93b24fa576653f427e4c592bb025ce0",
  "documentType": "setup",
  "title": "Ollama e Open WebUI no Setup MNO",
  "setupId": "ollama-openwebui",
  "setupVersion": "7.7.40",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-07-30",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["ollama", "open-webui", "llm-local"],
  "sources": [
    {
      "sourceId": "ollama-openwebui-installer",
      "title": "Instalador Ollama e Open WebUI",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/ollama.sh",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    },
    {
      "sourceId": "ollama-openwebui-catalog",
      "title": "Entrada Ollama e Open WebUI no catálogo",
      "sourceType": "setup-mno",
      "location": "setupmno-control/catalog.json",
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
# Ollama e Open WebUI no Setup MNO

## Quando usar

Use para executar modelos locais e oferecer uma interface web quando
privacidade, autonomia ou experimentação justificarem o consumo. Para VPS
pequena, prefira o diagnóstico básico ou um provedor remoto opcional.

## Arquitetura no Setup MNO

O setup implanta Ollama com volume de modelos e Open WebUI com volume próprio.
Os serviços compartilham rede interna, enquanto as interfaces previstas pelo
instalador recebem roteamento.

## Pré-requisitos

Exige memória e armazenamento muito superiores aos de aplicações comuns. O
modelo escolhido determina consumo real e compatibilidade. O Control Center
não baixa modelos automaticamente para ativar seu conector.

## Fluxo seguro

O instalador alerta sobre recursos, coleta os domínios, gera o segredo da
interface, cria volumes e implanta os serviços. Modelos são geridos
separadamente pelo operador.

## Validação

Confirme saúde de ambos os serviços, comunicação interna e uma inferência com
modelo já disponível. Meça memória durante a geração, não apenas com o modelo
ocioso.

## Riscos e limites

Falta de memória pode derrubar outros serviços. Publicar a API do modelo amplia
a superfície de abuso e consumo. Dados enviados ao modelo local ainda exigem
governança e controle de acesso.

## Diagnóstico

Interface disponível sem resposta aponta para comunicação com Ollama ou modelo
ausente. Encerramento durante inferência sugere capacidade. Nunca invente que
um modelo foi instalado; confirme somente estados observáveis.
