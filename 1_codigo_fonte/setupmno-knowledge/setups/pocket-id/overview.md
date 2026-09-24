---
{
  "schemaVersion": 1,
  "documentId": "setup-pocket-id-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "5123b0f620472f633b63797ab24c1db280274d40dd0516865b02b02c50fdaf6f",
  "documentType": "setup",
  "title": "Pocket ID no Setup MNO",
  "setupId": "pocket-id",
  "setupVersion": "7.48.23",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-10",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["pocket-id", "identidade", "oidc", "passkeys", "webauthn"],
  "sources": [
    {"sourceId":"pocket-id-installer","title":"Instalador Pocket ID","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/pocketid.sh","license":"project-internal","verifiedAt":"2026-08-10"},
    {"sourceId":"pocket-id-installation","title":"Instalação oficial do Pocket ID","sourceType":"official-documentation","location":"https://pocket-id.org/docs/setup/installation","license":"documentation-reference","verifiedAt":"2026-08-10"},
    {"sourceId":"pocket-id-environment","title":"Variáveis de ambiente oficiais do Pocket ID","sourceType":"official-documentation","location":"https://pocket-id.org/docs/configuration/environment-variables","license":"documentation-reference","verifiedAt":"2026-08-10"},
    {"sourceId":"pocket-id-hardening","title":"Hardening oficial do Pocket ID","sourceType":"official-documentation","location":"https://pocket-id.org/docs/advanced/hardening","license":"documentation-reference","verifiedAt":"2026-08-10"},
    {"sourceId":"pocket-id-releases","title":"Releases oficiais do Pocket ID","sourceType":"official-documentation","location":"https://github.com/pocket-id/pocket-id/releases","license":"documentation-reference","verifiedAt":"2026-08-10"}
  ],
  "homologation": {
    "verifiedAt": "2026-08-10",
    "verifiedPorts": [1411],
    "verifiedImages": [
      "ghcr.io/pocket-id/pocket-id:v2.11.0-distroless@sha256:446624a84743c29f93db2ffbbe19f9059fd9741e0cb2516d31efcc764e131835"
    ]
  }
}
---
# Pocket ID no Setup MNO

## Quando usar

Use o Pocket ID como provedor de identidade OIDC para aplicações compatíveis
quando desejar login sem senha por passkeys. O navegador pode usar biometria,
PIN do dispositivo ou uma chave de segurança, sem manter uma senha tradicional
do usuário no Pocket ID.

## Arquitetura no Setup MNO

O instalador cria uma stack de serviço único, um Docker Secret exclusivo para a
chave de criptografia e um diretório persistente para o banco SQLite e imagens.
A imagem distroless oficial é fixada por versão e digest multi-arquitetura. O
processo executa como usuário não-root 65532, com filesystem raiz somente leitura
e todas as capabilities removidas.

## Pré-requisitos

Exige Docker Swarm ativo, redes externa e interna do Setup MNO, domínio válido e
HTTPS funcional. WebAuthn depende de contexto seguro no navegador; por isso a
porta 1411 não é publicada no host e o acesso externo passa pelo Traefik ou pelo
Cloudflare Tunnel. A implantação suporta AMD64 e ARM64.

## Fluxo seguro

A chave de criptografia é gerada com OpenSSL, enviada diretamente ao Docker
Secret e montada somente para o usuário da aplicação. O valor não entra no YAML,
no log nem no arquivo de dados. O instalador desativa callbacks inseguros, mantém
rate limiting ativo e desativa telemetria analítica. Após o deploy, o primeiro
administrador é cadastrado em `/setup` e registra uma passkey.

## Validação

A homologação isolada confirmou imagem AMD64, manifesto ARM64, réplica saudável,
healthcheck oficial, resposta HTTP 200 no fluxo `/setup`, ausência de porta
publicada e criação do SQLite persistente. O reinício forçado preservou o banco.
O consumo ocioso observado foi de aproximadamente 12 MiB, sob limite de 512 MiB.

## Riscos e limites

O Pocket ID torna-se parte central da autenticação das aplicações integradas.
Perder simultaneamente o banco e a chave de criptografia impede recuperação dos
dados protegidos. Passkeys também exigem planejamento de recuperação do usuário;
cadastre mais de um autenticador administrativo e proteja o domínio com HTTPS.
O teste funcional ARM64 ficou limitado à inspeção do manifesto oficial.

## Diagnóstico

Se a página não abrir, confirme a réplica, o healthcheck, a rota do domínio e os
logs da stack. Falha ao gravar o banco indica proprietário incorreto no diretório
persistente. Redirecionamentos ou origem inválida normalmente indicam divergência
entre `APP_URL`, HTTPS e o domínio acessado.

## Backup e atualização

Faça backup consistente do diretório de dados e preserve o Docker Secret da
instância no plano de recuperação do Swarm. Antes de atualizar, homologue a nova
imagem, valide os manifestos AMD64 e ARM64, fixe o novo digest e confirme login,
OIDC, reinício e persistência. O rollback deve restaurar juntos banco e chave da
mesma geração.
