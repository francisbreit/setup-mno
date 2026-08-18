---
{
  "schemaVersion": 1,
  "documentId": "setup-vaultwarden-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "4a94054058bf8ebe8fdf2c153e9a76c99e53057a10a9fb747f6dec16120f24d1",
  "documentType": "setup",
  "title": "Vaultwarden no Setup MNO",
  "setupId": "vaultwarden",
  "setupVersion": "7.20.0",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": ["vaultwarden", "senhas", "bitwarden", "smtp", "backup"],
  "sources": [
    {"sourceId":"vaultwarden-installer","title":"Instalador Vaultwarden","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/vaultwarden.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"vaultwarden-repo","title":"Vaultwarden project documentation","sourceType":"official-documentation","location":"https://github.com/dani-garcia/vaultwarden","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"vaultwarden-security","title":"Hardening Guide","sourceType":"official-documentation","location":"https://github.com/dani-garcia/vaultwarden/wiki/Hardening-Guide","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"vaultwarden-backup","title":"Backing up your vault","sourceType":"official-documentation","location":"https://github.com/dani-garcia/vaultwarden/wiki/Backing-up-your-vault","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# Vaultwarden no Setup MNO

## Quando usar

Use para hospedar um servidor compatível com clientes Bitwarden para pessoas,
famílias ou pequenas equipes que conseguem operar segurança e recuperação. Não
use como único repositório de credenciais sem backup, MFA e plano de emergência.

## Arquitetura no Setup MNO

O instalador cria um serviço de nó único com volume persistente, TLS no proxy e
SMTP configurável. A imagem usa tag móvel, novos cadastros permanecem abertos e
a senha SMTP é interpolada no YAML da stack.

## Pré-requisitos

Exige domínio HTTPS, email confiável, armazenamento protegido, backup cifrado e
administradores com MFA. O web vault depende de contexto seguro. Defina quem
pode cadastrar, recuperar e administrar antes de importar senhas reais.

## Fluxo seguro

Não publique com cadastro aberto. Fixe versão, proteja SMTP como secret, limite
o painel administrativo e use um token robusto quando habilitado. Execute pelo
Instalador Seguro e mantenha recuperação offline testada.

## Primeiro acesso e integrações

Crie conta descartável, confirme email, ative MFA e teste sincronização em um
cliente oficial compatível. Organizações, anexos, WebAuthn e envio de email
precisam ser validados individualmente antes da migração.

## Backup, atualização e rollback

Backup precisa incluir banco, configuração, anexos e chaves no volume de dados;
copiar apenas o arquivo principal pode gerar inconsistência. Faça cópia
coordenada, mantenha-a cifrada fora do servidor e teste restauração. Leia notas
de release antes de trocar versão e não suponha downgrade de banco.

## Validação

Valide HTTPS, criação e bloqueio de contas conforme política, MFA,
sincronização, anexo, email, persistência e restauração isolada.

## Diagnóstico

Separe DNS e TLS, proxy, aplicação, banco, volume e SMTP. Nunca envie senha
mestra, item do cofre, exportação, token, cookie ou credencial SMTP ao
Assistente.

## Riscos e limites

Cadastro aberto, tag móvel, secret SMTP em YAML e ausência de limites de
recursos bloqueiam recomendação automática de produção. Vaultwarden é projeto
compatível não oficial; suporte e compatibilidade devem ser avaliados.
