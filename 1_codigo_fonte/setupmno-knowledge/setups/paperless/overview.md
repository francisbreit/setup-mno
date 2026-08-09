---
{
  "schemaVersion": 1,
  "documentId": "setup-paperless-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "0a1c934263f8787b8a71b612ff4dfb5adb2cc7af5d93e1612e99b26a13e83851",
  "documentType": "setup",
  "title": "Paperless-ngx no Setup MNO",
  "setupId": "paperless",
  "setupVersion": "7.7.49",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": ["paperless", "documentos", "ocr", "redis", "postgresql"],
  "sources": [
    {"sourceId":"paperless-installer","title":"Instalador Paperless","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/paperless.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"paperless-setup","title":"Setup","sourceType":"official-documentation","location":"https://docs.paperless-ngx.com/setup/","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"paperless-config","title":"Configuration","sourceType":"official-documentation","location":"https://docs.paperless-ngx.com/configuration/","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"paperless-admin","title":"Administration","sourceType":"official-documentation","location":"https://docs.paperless-ngx.com/administration/","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# Paperless-ngx no Setup MNO

## Quando usar

Use para receber, aplicar OCR, classificar e pesquisar documentos. Não trate o
sistema como arquivo legal sem política de retenção, acesso, exportação e cópia
externa. Documentos pessoais e empresariais tornam o impacto de vazamento alto.

## Arquitetura no Setup MNO

O instalador cria broker Redis dedicado e aplicação em nó único, mas conecta o
Paperless a uma base esperada no PostgreSQL compartilhado. A imagem usa tag
móvel, o idioma de OCR inicial é inglês e os volumes cobrem dados e mídia.

## Pré-requisitos

Exige domínio, TLS, PostgreSQL e usuário de banco previamente compatíveis,
volumes, espaço para originais e derivados, e CPU para OCR. Defina idioma,
usuários, origem dos documentos, retenção e backup antes da ingestão real.

## Fluxo seguro

Use o Instalador Seguro, confirme a existência isolada da base e valide a chave
secreta. Crie superusuário apenas para administração e uma conta comum para uso
diário, como recomenda a documentação. Restrinja consumo por email e scripts.

## Primeiro acesso e integrações

Importe documento descartável, revise texto OCR, tags e permissões. Scanner,
email e automações devem usar pastas ou contas dedicadas, com arquivo malicioso
e duplicidade considerados no fluxo.

## Backup, atualização e rollback

O exportador oficial inclui documentos, miniaturas, metadados e banco, mas não
tokens de API. Exportações são sensíveis à versão. Pare consumo, gere exportação
ou copie volumes e banco consistentemente, teste importação em instância vazia
e leia migrações antes de trocar a imagem.

## Validação

Valide ingestão, OCR no idioma correto, busca, permissão, tarefa agendada,
persistência, exportação e importação de um conjunto descartável.

## Diagnóstico

Separe proxy, aplicação, workers, Redis, PostgreSQL, OCR, volume e origem de
consumo. Não envie documentos, texto extraído, tokens, emails ou banco ao
Assistente.

## Riscos e limites

Tag móvel, dependência de base prévia e chave reutilizada como senha do banco
exigem correção antes de recomendação automática de produção. O setup não
configura Tika, Gotenberg nem backup externo.
