---
{
  "schemaVersion": 1,
  "documentId": "setup-duplicati-overview",
  "documentVersion": "1.0.2",
  "contentSHA256": "109e5f529472bb578ca5a788d6298e8cc26c4c2888c07b8405aa046629b21bb8",
  "documentType": "setup",
  "title": "Duplicati no Setup MNO",
  "setupId": "duplicati",
  "setupVersion": "7.35.0",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-07-30",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": ["duplicati", "backup", "restauracao"],
  "sources": [
    {
      "sourceId": "duplicati-installer",
      "title": "Instalador Duplicati",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/duplicati.sh",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    },
    {
      "sourceId": "duplicati-catalog",
      "title": "Entrada Duplicati no catálogo",
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
# Duplicati no Setup MNO

## Quando usar

Use para agendar backups criptografados para destinos suportados e administrar
retenção pela interface web. A ferramenta não elimina a necessidade de testar
restaurações.

## Arquitetura no Setup MNO

A stack mantém volumes distintos para configuração da aplicação e área de
backup. Participa das redes interna e externa e recebe uma rota autenticada
pelo próprio serviço.

## Pré-requisitos

Defina origem, destino, retenção, janela e responsável. Credenciais do destino
devem ser inseridas somente na aplicação. Planeje espaço temporário e impacto
de leitura nas aplicações protegidas.

## Fluxo seguro

O instalador coleta domínio e senha administrativa no Whiptail, gera chave de
criptografia de configurações, cria volumes e implanta a stack. Nenhum desses
segredos pertence à base de conhecimento.

## Validação

Confirme login, execução de tarefa com dados descartáveis e restauração em
local isolado. Registre a data do último teste de recuperação, não apenas a
data do último backup.

## Riscos e limites

Perder chave ou senha pode tornar cópias inutilizáveis. Um destino montado na
mesma VPS compartilha o domínio de falha. Nunca restaure sobre dados ativos sem
cópia e plano de rollback.

## Diagnóstico

Separe falha de leitura da origem, autenticação do destino, falta de espaço e
corrupção. Não cole logs contendo caminhos ou nomes de clientes no Assistente;
forneça apenas a classe sanitizada do erro.
