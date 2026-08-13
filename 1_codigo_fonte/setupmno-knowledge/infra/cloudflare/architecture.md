---
{
  "schemaVersion": 1,
  "documentId": "infra-cloudflare-architecture",
  "documentVersion": "1.3.2",
  "contentSHA256": "758a2f9c32e171123fc251f15bb9f9388ee53ad43924d77a5ba0b6760cd6140f",
  "documentType": "infrastructure",
  "title": "Cloudflare no acesso tradicional e por túnel",
  "topicId": "cloudflare",
  "setupVersion": "7.17.0",
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
      "verifiedAt": "2026-08-11"
    },
    {
      "sourceId": "cloudflare-base-script",
      "title": "Fluxos tradicional e Cloudflare Tunnel",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/dockerswarm.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-11"
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

## Criação do túnel principal

Em uma instalação inicial por Cloudflare Tunnel, o usuário pode solicitar a
criação automática recomendada ou informar o ID de um Tunnel já criado. Os
dois caminhos pedem primeiro o hostname do Portainer e o API Token. O Setup
lista as zonas ativas acessíveis pelo token, escolhe a zona mais específica
compatível com o hostname e descobre automaticamente Account ID, Zone ID e
nome da zona. O usuário não precisa copiar esses identificadores do painel.

O token inicial precisa de Cloudflare Tunnel em edição, Zona em leitura e DNS
em edição. No método automático, esses são todos os dados Cloudflare pedidos.
O método clássico acrescenta somente o Tunnel ID. Os dois caminhos validam
token, conta descoberta, zona, acesso a DNS e permissão de Tunnel antes da
confirmação final. A escolha automática gera um nome exclusivo no formato
`setupmno-primary-<12 caracteres hexadecimais aleatórios>` e somente chama a
API depois que o usuário confirma todos os dados. O identificador aleatório
evita colisões entre projetos que compartilham a mesma conta e zona. Se já
existir estado local válido, o nome e o Tunnel ID registrados são reutilizados
sem renomear ou recriar o recurso.

O túnel automático nasce com estado `pending` e propriedade `setupmno`. O
conector recebe o Tunnel Token exclusivamente por Docker Secret e a conclusão
exige stack 1/1, estado Healthy confirmado pela Cloudflare, ingresso do
Portainer e CNAME válidos. Uma falha restaura a configuração do Tunnel, os
registros DNS e as credenciais locais anteriores, remove stack e Secret e
exclui apenas o Tunnel automático ainda pendente.

A configuração de um Tunnel recém-criado pode demorar alguns segundos para
ficar consultável. O instalador repete a leitura com espera progressiva e
registra somente HTTP e mensagem sanitizada. Se, ao final, a API confirmar que
a configuração ainda não existe, apenas um Tunnel automático `pending` e
pertencente ao Setup MNO pode começar com configuração vazia. HTTP 401/403,
erros não reconhecidos, Tunnel externo ou Tunnel ativo continuam bloqueantes.
Depois do `PUT`, a rota do Portainer também é consultada com retry antes da
confirmação; ausência persistente aciona rollback.

No método clássico, o Tunnel recebe propriedade `external`. O Setup pode
configurar a rota e iniciar o conector, mas o rollback nunca exclui esse
Tunnel. O Tunnel Token não é gravado no arquivo de credenciais; o arquivo 0600
mantém somente os identificadores necessários para compatibilidade com os
instaladores atuais e antigos.

Na instalação tradicional com DNS automático, o mesmo mecanismo descobre
Account ID e Zone ID a partir do hostname do Portainer e solicita apenas o API
Token com leitura de zona e edição de DNS. Se o usuário escolher DNS manual,
nenhuma credencial Cloudflare é pedida nessa etapa. Os campos históricos de
credenciais continuam sendo gravados quando aplicáveis para compatibilidade
com scripts atuais e antigos.

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
