---
{
  "schemaVersion": 1,
  "documentId": "infra-cloudflare-architecture",
  "documentVersion": "1.1.0",
  "contentSHA256": "2a61cd233e86d2488aaad5eb8ae201c25a4dca93c2f784dc4cbd24c6a44bb540",
  "documentType": "infrastructure",
  "title": "Cloudflare no acesso tradicional e por túnel",
  "topicId": "cloudflare",
  "setupVersion": "7.13.0",
  "architectures": ["amd64", "arm64"],
  "category": "networking",
  "status": "reviewed",
  "updatedAt": "2026-08-11",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["cloudflare", "dns", "tunnel"],
  "sources": [
    {
      "sourceId": "cloudflare-generator-script",
      "title": "Gerador de configuração Cloudflare",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/geracloudflare.sh",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    },
    {
      "sourceId": "cloudflare-base-script",
      "title": "Fluxos tradicional e Cloudflare Tunnel",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/dockerswarm.sh",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    },
    {
      "sourceId": "cloudflare-domain-profiles",
      "title": "Perfis multidomínio Cloudflare",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/domain_profiles.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-11"
    }
  ],
  "homologation": {
    "verifiedAt": null,
    "verifiedPorts": [],
    "verifiedImages": []
  }
}
---
# Cloudflare no acesso tradicional e por túnel

## Papel no Setup MNO

O Setup MNO suporta publicação tradicional e publicação por túnel. O fluxo
selecionado determina como registros e ingressos são preparados, mantendo o
serviço de aplicação dentro das redes controladas pelo Swarm.

## Princípios

Tokens e identificadores de conta nunca entram na base de conhecimento nem no
contexto enviado à LLM. O Assistente pode explicar diferenças entre os modos,
mas não cria registros, não altera túnel e não solicita que o usuário cole
credenciais no chat.

## Perfis multidomínio

O primeiro domínio configurado é o perfil principal e continua sendo a
autoridade exclusiva dos hostnames de Portainer e Setup MNO Control Center.
Atualizações antigas permanecem compatíveis porque os arquivos históricos de
credenciais não são movidos nem reescritos durante a importação.

Domínios adicionais são cadastrados em um registro schema 1, com uma
credencial 0600 separada por zona. Antes da persistência, o Instalador Seguro
confirma token ativo, zona exata, conta, leitura de DNS e edição de DNS por um
registro TXT temporário criado e removido imediatamente. A seleção do perfil é
feita antes de iniciar o instalador da aplicação; cancelar retorna ao menu e
limpa a seleção da sessão.

No modo Tunnel, zonas da mesma conta reutilizam o túnel principal somente após
um teste de leitura e escrita da configuração. Uma zona de outra conta recebe
um túnel dedicado, token mantido em Docker Secret e stack cloudflared própria,
sem deslocar Portainer ou Control Center. No modo tradicional, cada domínio
adicional recebe um hostname técnico de origem que aponta ao IPv4 do servidor;
os subdomínios das aplicações continuam sendo criados pelo instalador.

Falhas posteriores à criação de um recurso disparam rollback do túnel, Secret,
stack ou registro técnico que tenha sido criado naquela tentativa. Recursos
preexistentes e o perfil principal não entram nesse rollback.

## Validação

O diagnóstico diferencia resolução ausente, ingresso de túnel incompatível,
serviço interno indisponível e rota da aplicação incorreta. A resposta deve
trabalhar apenas com estados sanitizados e orientar a coleta pelo Instalador
Seguro quando faltarem evidências.

## Riscos e limites

Uma alteração errada pode interromper diversos domínios ou expor um serviço
interno. Nenhuma correção de DNS ou túnel é executada pelo Assistente. Mudanças
devem ser confirmadas por um operador e possuir rollback da configuração
anterior.
