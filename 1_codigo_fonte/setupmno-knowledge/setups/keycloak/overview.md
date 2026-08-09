---
{
  "schemaVersion": 1,
  "documentId": "setup-keycloak-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "8d3b5a936ac50af818877143be38b29ebf53b1304f651dfe097d223c5b4a6e83",
  "documentType": "setup",
  "title": "Keycloak no Setup MNO",
  "setupId": "keycloak",
  "setupVersion": "7.7.49",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": ["keycloak", "identidade", "oidc", "saml", "postgresql"],
  "sources": [
    {"sourceId":"keycloak-installer","title":"Instalador Keycloak","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/keycloak.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"keycloak-containers","title":"Running Keycloak in a container","sourceType":"official-documentation","location":"https://www.keycloak.org/server/containers","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"keycloak-proxy","title":"Using a reverse proxy","sourceType":"official-documentation","location":"https://www.keycloak.org/server/reverseproxy","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"keycloak-export","title":"Importing and exporting realms","sourceType":"official-documentation","location":"https://www.keycloak.org/server/importExport","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# Keycloak no Setup MNO

## Quando usar

Use como provedor central de identidade quando várias aplicações precisam de
OIDC, OAuth ou SAML, MFA, federação e políticas comuns. Não use sem responsável
por identidade: uma configuração incorreta pode bloquear todos os sistemas ou
ampliar privilégios.

## Arquitetura no Setup MNO

O instalador cria uma base no PostgreSQL compartilhado e executa um nó Keycloak
atrás do proxy. Credenciais administrativas entram no YAML e a imagem usa tag
móvel. O serviço habilita HTTP interno, headers encaminhados, health e métricas.

## Pré-requisitos

Exige domínio estável, TLS, relógio sincronizado, PostgreSQL saudável, backup e
planejamento de realms, clientes, redirect URIs e contas de emergência. A URL
pública não deve mudar sem plano de migração.

## Fluxo seguro

Use o Instalador Seguro, uma credencial administrativa temporária e valide o
proxy antes de integrar clientes. Troque o bootstrap, habilite MFA para
administradores, restrinja redirect URIs e aplique menor privilégio. Uma imagem
otimizada e fixada é preferível para produção.

## Primeiro acesso e integrações

Crie realm e cliente descartáveis, valide discovery, login, logout, refresh e
expiração. Integre uma aplicação por vez e mantenha conta de emergência fora do
provedor para evitar bloqueio operacional.

## Backup, atualização e rollback

Backup primário é o PostgreSQL consistente com configuração e chaves. Exportar
realms não é backup completo: sessões, eventos e outros estados podem ficar de
fora, e consistência exige nós parados. Leia o guia de atualização entre
versões, restaure isoladamente e nunca reverta schema por troca de imagem.

## Validação

Valide issuer, TLS, login, MFA, logout, renovação, papéis, clock e recuperação
de administrador antes de conectar aplicações críticas.

## Diagnóstico

Separe DNS e TLS, headers do proxy, hostname, realm, cliente, relógio, banco e
cache. Não envie tokens, client secrets, cookies, chaves ou exportações de realm
ao Assistente.

## Riscos e limites

Tag móvel, bootstrap legado no YAML, relaxamento de hostname e banco
compartilhado bloqueiam recomendação automática de produção. Alta
disponibilidade, rotação de chaves e recuperação precisam de projeto próprio.
