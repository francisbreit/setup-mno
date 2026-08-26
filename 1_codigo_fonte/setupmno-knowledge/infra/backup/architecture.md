---
{
  "schemaVersion": 1,
  "documentId": "infra-backup-architecture",
  "documentVersion": "1.0.2",
  "contentSHA256": "ccb50355429272f8a355ec1d59fff15db0089be5fa98fbd17ef431c5228d9d96",
  "documentType": "infrastructure",
  "title": "Princípios de backup e restauração",
  "topicId": "backup",
  "setupVersion": "7.35.0",
  "architectures": ["amd64", "arm64"],
  "category": "backup",
  "status": "reviewed",
  "updatedAt": "2026-07-30",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": ["backup", "restauracao", "continuidade"],
  "sources": [
    {
      "sourceId": "duplicati-installer-script",
      "title": "Instalador do Duplicati",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/duplicati.sh",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    },
    {
      "sourceId": "packager-backup-policy",
      "title": "Backup automático antes do empacotamento",
      "sourceType": "maintainer-authored",
      "location": "Regra de release do projeto Setup MNO",
      "license": "maintainer-owned",
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
# Princípios de backup e restauração

## Papel no Setup MNO

Backup protege dados persistentes e oferece um ponto de retorno antes de
mudanças relevantes. A existência de uma tarefa não prova que a restauração
funciona; recuperação precisa ser verificada separadamente.

## Princípios

Definir escopo, retenção, destino, criptografia e responsável. Manter cópias
fora do mesmo domínio de falha da VPS. Antes de alterações estruturais,
confirmar que o backup recente está íntegro e que existe procedimento de
restauração.

## Validação

O Assistente deve perguntar pela evidência de execução e por um teste de
restauração sem solicitar caminhos, nomes ou credenciais do cliente. Um
resultado deve separar backup configurado, execução concluída e restauração
homologada.

## Riscos e limites

Backup incompleto gera falsa segurança. Restaurar sobre dados vivos pode
sobrescrever informação válida. O copiloto permanece consultivo e encaminha
qualquer restauração ao operador com janela, cópia de segurança e rollback.
