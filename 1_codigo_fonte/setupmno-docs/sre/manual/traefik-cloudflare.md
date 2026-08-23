# Diagnóstico de Traefik e Cloudflare por camadas

- Estado: `implemented`
- Atualizado em: 2026-08-23
- Público: mantenedor PRO MASTER e autores do futuro Help
- Ambientes: Traefik tradicional e Cloudflare Tunnel

## Resumo para leigos

“O site não abre” pode significar que o nome não existe, a Cloudflare não chega
ao túnel, o certificado não cobre o hostname, o Traefik não encontrou uma regra
ou a aplicação não respondeu. Cada camada possui um teste próprio. Mudar DNS ao
acaso pode criar uma segunda falha e atrasar o diagnóstico.

## Objetivo

Separar resolução, borda, transporte, TLS, roteamento e serviço de origem.

## O que observar

| Camada | Pergunta | Evidência esperada |
|---|---|---|
| DNS | O hostname existe publicamente? | A/AAAA/CNAME ou NXDOMAIN |
| Cloudflare | A zona, Access e rota correspondem ao hostname? | recurso exato e estado |
| Tunnel | `cloudflared` possui conexões saudáveis? | conexões e destino local |
| TLS | O certificado cobre exatamente o hostname? | SAN, emissor e validade |
| Traefik | Algum router casa host e entrypoint? | rule, TLS e service |
| Origem | O serviço responde na rede interna? | código HTTP controlado |

Consultas externas de baixo risco:

```bash
curl -I https://app.example.com
curl -I https://www.app.example.com
```

Preserve código, headers relevantes e horário. Não compartilhe cookies, tokens
de Access nem URLs assinadas. DNS deve ser consultado com uma ferramenta
disponível no ambiente; falha da ferramenta não é prova de propagação.

## Modo Cloudflare Tunnel

O `cloudflared` estabelece conexões de saída até a rede Cloudflare. Uma rota de
hostname público associa o nome a um serviço local. Criar um redirecionamento
para `www` não elimina a necessidade de o hostname `www` existir e concluir DNS
e TLS antes de entregar a resposta HTTP.

Conflitos com rota ou aplicação Access antiga devem ser tratados pelo hostname
exato e, quando aplicável, por wildcard. Remover Access após confirmação não
autoriza remover o túnel nem o DNS.

## Modo tradicional com Traefik

O router é ativado quando a regra combina com a requisição. Depois aplica
middlewares e encaminha ao serviço. Para HTTPS, entrypoint, TLS, resolver e nomes
do certificado precisam ser coerentes. Uma regra apenas para o domínio raiz não
aceita `www` automaticamente.

Padrão recomendado quando o domínio raiz é canônico:

- raiz e `www` possuem DNS válido;
- TLS cobre os dois nomes;
- `www` redireciona para a raiz preservando caminho e query;
- a aplicação recebe um único host canônico.

## Limites e segurança

- Não altere DNS, Tunnel, Access, certificados ou labels durante coleta.
- Não exponha token da Cloudflare em comando, log ou relatório.
- Não desative validação TLS para declarar sucesso.
- Um `HTTP 200` da borda não prova saúde do banco nem backup.
- Mudanças reais exigem escopo literal, diff e rollback.

## Fontes oficiais

- [Cloudflare Tunnel](https://developers.cloudflare.com/tunnel/)
- [Cloudflare Tunnel routing](https://developers.cloudflare.com/tunnel/routing/)
- [Traefik HTTP routers](https://doc.traefik.io/traefik/reference/routing-configuration/http/routing/router/)
- [Traefik TLS overview](https://doc.traefik.io/traefik/https/overview/)

## Publicação futura no Help

Criar uma linha visual `DNS -> Cloudflare -> Tunnel/Traefik -> serviço` e destacar
em vermelho somente a primeira camada sem evidência. Incluir um tutorial próprio
para SSL com e sem `www`.
