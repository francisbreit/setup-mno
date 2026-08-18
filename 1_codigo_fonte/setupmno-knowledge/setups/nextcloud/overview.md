---
{
  "schemaVersion": 1,
  "documentId": "setup-nextcloud-overview",
  "documentVersion": "1.0.2",
  "contentSHA256": "101412f60b21500ef5c485a8e0e688420522366d997bccfd6e39cfae6f88474d",
  "documentType": "setup",
  "title": "Nextcloud no Setup MNO",
  "setupId": "nextcloud",
  "setupVersion": "7.22.1",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-07-30",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": ["nextcloud", "arquivos", "colaboracao"],
  "sources": [
    {
      "sourceId": "nextcloud-installer",
      "title": "Instalador Nextcloud",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/nextcloud.sh",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    },
    {
      "sourceId": "nextcloud-catalog",
      "title": "Entrada Nextcloud no catálogo",
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
# Nextcloud no Setup MNO

## Quando usar

Use para armazenamento, compartilhamento e colaboração em arquivos sob
controle próprio. Avalie crescimento, sincronização e requisitos legais antes
de migrar dados críticos.

## Arquitetura no Setup MNO

A aplicação e o processo de tarefas agendadas compartilham o volume de dados.
O setup usa banco lógico no PostgreSQL base e o Redis base, participa das redes
controladas e publica a interface principal.

## Pré-requisitos

Exige armazenamento dimensionado, PostgreSQL, Redis, domínio e plano de backup
consistente. Defina tamanho esperado, usuários, política de compartilhamento e
destino externo de recuperação.

## Fluxo seguro

O instalador coleta conta administrativa pelo Whiptail, cria o banco, prepara
volume e implanta aplicação e tarefas. Credenciais não devem aparecer em
relatórios nem ser repetidas pelo Assistente.

## Validação

Confirme login, upload e download de arquivo descartável, tarefa agendada e
persistência. Teste também limite e sincronização com um cliente controlado
antes de produção.

## Riscos e limites

O volume pode crescer rapidamente e contém dados do usuário. Restaurar exige
consistência com o banco. Compartilhamentos públicos e aplicativos adicionais
ampliam a superfície de ataque.

## Diagnóstico

Falha de upload pode ser espaço, permissão ou limite. Interface lenta pode
envolver banco, Redis ou armazenamento. Nunca envie nomes ou conteúdo de
arquivos ao conector de IA.
