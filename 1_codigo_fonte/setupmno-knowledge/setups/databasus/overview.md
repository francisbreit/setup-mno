---
{
  "schemaVersion": 1,
  "documentId": "setup-databasus-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "9adf9f9ea7112b9265f912ef4c8ee477f36a848f65ed38bc814a8b67c3e02707",
  "documentType": "setup",
  "title": "Databasus no Setup MNO",
  "setupId": "databasus",
  "setupVersion": "7.5.5",
  "architectures": [
    "amd64",
    "arm64"
  ],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": [
    "databasus",
    "backup",
    "postgresql",
    "restauracao"
  ],
  "sources": [
    {
      "sourceId": "databasus-installer",
      "title": "Instalador Databasus",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/databasus.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "databasus-official-1",
      "title": "Documentação oficial de Databasus",
      "sourceType": "official-documentation",
      "location": "https://github.com/databasus/databasus",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "databasus-official-2",
      "title": "Documentação oficial de Databasus",
      "sourceType": "official-documentation",
      "location": "https://databasus.com/",
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
# Databasus no Setup MNO

## Quando usar

Use para agendar e verificar backups de bancos com uma interface self-hosted. A recomendação deve considerar finalidade, dados tratados, manutenção e alternativa mais simples; a existência no catálogo não significa homologação automática.

## Arquitetura no Setup MNO

O instalador entrega a aplicação Databasus com armazenamento persistente e rota web. A ferramenta conecta-se aos bancos e destinos definidos pelo administrador; sua função não substitui o backup nativo do Setup.

## Pré-requisitos

Exige credencial de banco com privilégio mínimo, destino separado, criptografia, retenção e espaço. Planeje a verificação de restore em recurso isolado sem expor o banco publicamente.

## Fluxo seguro

Execute somente pelo Instalador Seguro, confirme o resumo antes do deploy e não publique portas administrativas adicionais. Credenciais permanecem fora do Assistente e operações reais continuam sujeitas à confirmação humana.

## Primeiro acesso e integrações

Crie o administrador, configure primeiro um banco de teste e execute um backup manual. Valide notificação e restauração antes de aceitar um agendamento como proteção efetiva.

## Backup e atualização

Proteja também os dados e a chave de criptografia do próprio Databasus, além dos arquivos produzidos. Mantenha cópia fora da VPS e uma rotina de restore independente da interface.

## Validação

Confirme HTTPS, autenticação, persistência após recriação controlada, saúde das réplicas e o fluxo funcional mínimo com dados fictícios. Registre versões efetivas e evidências sem segredos; só promova após um teste de restauração aplicável.

## Riscos e limites

Backup concluído não prova recuperação. Agentes de restore podem iniciar contêineres temporários e exigem escopo controlado. Acesso ao banco e ao destino é altamente sensível.

## Diagnóstico

Diferencie conexão ao banco, execução do dump, upload, retenção, notificação e restore. Use banco descartável; não envie dumps, URLs assinadas ou credenciais ao Assistente.
