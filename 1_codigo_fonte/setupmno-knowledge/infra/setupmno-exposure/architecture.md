---
{
  "schemaVersion": 1,
  "documentId": "infra-setupmno-exposure-architecture",
  "documentVersion": "1.3.2",
  "contentSHA256": "b0052d7ca1a80ca90daeb56b9ed55fd72d934b6d23db0569e5f5f2b9772c6bc9",
  "documentType": "infrastructure",
  "title": "Publicação de serviços por Cloudflare Tunnel ou Traefik",
  "topicId": "setupmno-exposure",
  "setupVersion": "7.48.4",
  "architectures": ["amd64", "arm64"],
  "category": "networking",
  "status": "reviewed",
  "updatedAt": "2026-08-11",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["cloudflare-tunnel", "traefik", "dns", "tls", "proxy", "rede-externa"],
  "sources": [
    {"sourceId":"dockerswarm-x86","title":"Preparação de entrada e redes","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/dockerswarm.sh","license":"project-internal","verifiedAt":"2026-08-03"},
    {"sourceId":"control-installer","title":"Instalador canônico do Control Center","sourceType":"setup-mno","location":"setupmno-control/installer-template.sh","license":"project-internal","verifiedAt":"2026-08-03"},
    {"sourceId":"traefik-knowledge","title":"Conhecimento canônico do Traefik","sourceType":"setup-mno","location":"setupmno-knowledge/infra/traefik/architecture.md","license":"project-internal","verifiedAt":"2026-08-03"},
    {"sourceId":"cloudflare-knowledge","title":"Conhecimento canônico do Cloudflare","sourceType":"setup-mno","location":"setupmno-knowledge/infra/cloudflare/architecture.md","license":"project-internal","verifiedAt":"2026-08-03"}
  ],
  "homologation": {"verifiedAt": null, "verifiedPorts": [], "verifiedImages": []}
}
---
# Publicação de serviços por Cloudflare Tunnel ou Traefik

## Papel no Setup MNO

Define o caminho canônico de publicação e diagnóstico externo conforme o tipo
de instalação validado no runtime.

## Princípios

Validar de dentro para fora: aplicação, rede, proxy ou Tunnel, TLS e DNS.
Preservar credenciais e evitar duas autoridades para o mesmo hostname.

## Escolha do modelo

O Setup MNO registra um tipo de instalação: **Cloudflare Tunnel** ou
**Tradicional (Traefik)**. Essa informação define como os hostnames chegam aos
serviços, quais credenciais são necessárias e onde investigar uma falha. O
Assistente deve usar a tag runtime e não presumir o tipo pela existência de um
container isolado.

O tipo de instalação continua global, mas a zona Cloudflare pode ser escolhida
por aplicação. O domínio inicialmente instalado permanece o principal e é o
único usado por Portainer e Control Center. Um domínio adicional nunca altera
esses dois hostnames e recebe credencial isolada. Aplicações antigas continuam
usando o domínio principal quando nenhuma seleção adicional existir.

## Cloudflare Tunnel

No modelo Tunnel, o conector cloudflared estabelece uma saída autenticada para
a Cloudflare. A rota associa hostname a um serviço interno na rede Docker. A
aplicação não precisa publicar uma porta diretamente no host para ser acessada
por essa rota.

Zonas adicionais da mesma conta podem compartilhar o túnel principal. Zonas de
outra conta Cloudflare usam túnel e stack cloudflared dedicados, pois conta,
token e configuração do túnel formam uma fronteira administrativa separada.

Na preparação inicial, o usuário escolhe entre criação automática e Tunnel
existente. A criação automática é transacional e pertence ao Setup MNO; o
Tunnel existente permanece externo e nunca pode ser excluído pelo rollback.
Em ambos os casos, o token do conector fica em Docker Secret e a publicação só
é confirmada depois de validar conector, rota e DNS. Esse fluxo não altera
instalações antigas que já possuem o Swarm e o túnel principal configurados.
Novos túneis automáticos recebem sufixo aleatório exclusivo, evitando colisão
quando vários projetos usam a mesma conta e zona Cloudflare. Um túnel já
registrado localmente preserva seu nome original durante atualização ou
reconciliação.
Na criação automática, a propagação inicial da configuração é aguardada com
retry progressivo. Somente um Tunnel novo ou `pending`, reconhecido como
propriedade do Setup MNO, pode receber o primeiro ingresso a partir de uma
configuração vazia confirmada pela API; erros de autorização e recursos
externos permanecem bloqueantes.

Como `dockerswarm.sh` atende a instalação limpa, ele coleta apenas os dados
necessários. No Tunnel automático, são pedidos hostname do Portainer e API
Token; Account ID, Zone ID e zona são descobertos pela API. No Tunnel
existente, acrescenta-se somente o Tunnel ID. A seleção usa a zona ativa mais
específica correspondente ao hostname, preservando zonas delegadas ou
aninhadas da mesma conta.

O diagnóstico deve separar:

1. serviço e healthcheck dentro do Swarm;
2. resolução do nome do serviço na rede compartilhada;
3. conectividade do cloudflared;
4. ingress do Tunnel para o hostname;
5. DNS e estado da zona na Cloudflare;
6. política de acesso, quando usada.

Credenciais do Tunnel, token de API, account ID e tunnel ID nunca devem entrar
no chat. Alterar uma rota exige confirmar a configuração atual e preservar a
rota anterior para rollback.

## Tradicional com Traefik

No modelo tradicional, Traefik observa labels de serviços, recebe tráfego nas
portas publicadas de entrada e encaminha pela rede overlay externa. DNS aponta
para o endereço público do servidor e TLS depende dos resolvers e labels
configurados.

Quando o DNS automático é escolhido na instalação inicial, o Setup solicita
somente o API Token e descobre os IDs pela zona do hostname. No DNS manual,
nenhum token ou identificador Cloudflare é necessário. Os identificadores
descobertos continuam persistidos no formato histórico para não quebrar os
instaladores que os consomem.

O diagnóstico deve separar:

1. DNS do hostname para o endereço esperado;
2. firewall e portas de entrada;
3. serviço Traefik e seus logs;
4. labels de router, rule, entrypoint, TLS e service port;
5. presença conjunta de Traefik e aplicação na rede externa;
6. porta interna real na qual a imagem escuta;
7. certificado e desafio ACME.

Não assuma que toda imagem escuta na porta HTTP padrão. A porta indicada ao proxy deve
corresponder ao processo real do container.

Para múltiplas zonas, cada perfil adicional possui um hostname técnico de
origem na própria zona. Os instaladores criam os subdomínios das aplicações
como CNAME para essa origem, enquanto o roteamento HTTP permanece determinado
pelas labels do Traefik.

## Redes

A rede `interna` atende comunicação privada entre componentes. A rede
`externa` conecta aplicações que precisam ser alcançadas pelo proxy ou pelo
Tunnel. Uma aplicação pode participar das duas, mas bancos, Redis e filas não
devem ser expostos apenas por conveniência.

Falha de acesso externo com task saudável costuma exigir verificação da rota e
da rede, não reinício repetido da aplicação. Primeiro prove acesso interno;
depois avance para proxy ou Tunnel e, por último, DNS público.

## Evitar exposição dupla

O mesmo hostname não deve ser administrado simultaneamente por rotas
independentes de Tunnel e Traefik sem um projeto explícito. Exposição dupla
pode produzir diagnóstico ambíguo, certificados divergentes e uma superfície
de ataque desnecessária. A tag de tipo de instalação indica o caminho padrão;
exceções precisam ser documentadas.

## Checklist antes de publicar

- domínio sob controle do usuário;
- serviço saudável e porta interna confirmada;
- rede overlay correta;
- hostname não utilizado por outra aplicação;
- TLS e política de acesso definidos;
- credenciais somente em Secret ou arquivo protegido do fluxo autorizado;
- ausência de banco, Redis, fila ou painel administrativo exposto sem
  necessidade;
- validação interna antes do DNS público;
- rollback da rota e do DNS registrado.

## Resposta do Assistente

Ao orientar acesso, informe primeiro o tipo runtime. Em seguida, diga em qual
camada há evidência de falha: aplicação, rede, proxy/Tunnel, TLS ou DNS. Não
afirme que o serviço está publicamente seguro apenas porque as réplicas estão
saudáveis. Não solicite credenciais nem invente hostname, porta ou label.

## Validação

Confirme resposta interna, participação na rede correta, rota, TLS e DNS.
Teste o hostname sem desativar o caminho anterior antes de registrar sucesso.

## Riscos e limites

Rota incorreta pode expor um painel administrativo ou encaminhar ao serviço
errado. Réplicas saudáveis não comprovam TLS, DNS ou proteção externa. Tokens,
IDs de conta e arquivos de credenciais permanecem fora do chat.
