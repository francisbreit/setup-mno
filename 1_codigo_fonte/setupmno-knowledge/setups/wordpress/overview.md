---
{
  "schemaVersion": 1,
  "documentId": "setup-wordpress-overview",
  "documentVersion": "1.0.1",
  "contentSHA256": "b7006e961cdeb5d69c679562d9e484f3c6d3b30a77fe4b7837f3bfce92106dab",
  "documentType": "setup",
  "title": "WordPress no Setup MNO",
  "setupId": "wordpress",
  "setupVersion": "7.44.0",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-16",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["wordpress", "cms", "mysql", "redis", "backup", "dns", "tls", "www"],
  "sources": [
    {"sourceId":"wordpress-installer","title":"Instalador WordPress","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/wordpress.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"wordpress-update-docs","title":"Atualização oficial do WordPress","sourceType":"official-documentation","location":"https://wordpress.org/documentation/article/updating-wordpress/","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"wordpress-maintenance-docs","title":"Manutenção oficial de sites WordPress","sourceType":"official-documentation","location":"https://wordpress.org/documentation/article/wordpress-site-maintenance/","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"cloudflare-universal-ssl-limitations","title":"Limitações do Universal SSL da Cloudflare","sourceType":"official-documentation","location":"https://developers.cloudflare.com/ssl/edge-certificates/universal-ssl/limitations/","license":"documentation-reference","verifiedAt":"2026-08-16"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# WordPress no Setup MNO

## Quando usar

Use para sites, blogs e lojas que dependem do ecossistema WordPress. Não escolha
apenas pela quantidade de plugins: avalie governança editorial, atualizações,
cache, pagamentos, privacidade e manutenção contínua. Aplicações estáticas podem
ser mais simples e seguras para sites sem conteúdo dinâmico.

## Arquitetura no Setup MNO

O instalador prepara uma base MySQL, cria uma aplicação WordPress com volume
persistente e rota pública, e aponta cache para o Redis base. No modo tradicional,
a rota do Traefik pode contemplar o hostname informado e sua variante com ou sem
`www`; no modo Tunnel, a rota permanece restrita ao hostname exato. Banco,
arquivos e cache são dependências distintas. A imagem da aplicação é móvel e
exige controle de atualização fora de mudanças automáticas imprevisíveis.

## Pré-requisitos

Exige domínio, MySQL saudável, Redis base, volume, SMTP ou serviço transacional
quando necessário e recursos proporcionais a tráfego, plugins e mídia. Defina
administrador, política de plugins, atualização, backup, retenção e proteção de
login antes de publicar.

## Fluxo seguro

O Instalador Seguro coleta domínio, nome da base e modo Portainer ou Docker,
prepara banco e volume e implanta a aplicação. No DNS tradicional automático,
ele preserva qualquer alias já existente e só cria a variante com ou sem `www`
quando não existe conflito. No DNS manual, a variante só entra na regra TLS se
resolver para o IPv4 público da VPS. No primeiro acesso, use conta administrativa
individual, habilite menor privilégio para editores e remova temas ou plugins não
usados.

## Primeiro acesso e integrações

Valide página pública, painel, mídia e permalink com conteúdo descartável.
Plugins de cache, loja, formulários e SEO devem ser adicionados um por vez, com
fonte confiável e plano de reversão. Integrações externas usam credenciais
próprias e nunca devem depender da senha administrativa do site.

## Backup e atualização

Backup completo cobre banco e volume de conteúdo; um sem o outro pode produzir
restauração inconsistente. Antes de atualizar core, tema ou plugin, preserve
cópia restaurável e teste em staging. A documentação oficial alerta que arquivos
do core podem ser substituídos durante atualização.

## Validação

Confirme acesso público e administrativo, upload, escrita no banco, cache,
persistência, envio de email quando usado e restauração de página descartável.
Execute verificação de atualizações e saúde sem instalar componentes aleatórios.

## Riscos e limites

Plugins e temas ampliam muito a superfície de ataque. Tags móveis, credenciais
reutilizadas, falta de backup e painel exposto sem proteção são riscos altos. O
Redis compartilhado é dependência legada: limpeza indiscriminada pode atingir
outras aplicações. Em Cloudflare Tunnel, um hostname aninhado como
`www.wordpress.exemplo.com.br` não é coberto pelo Universal SSL padrão da zona;
publicá-lo exige cobertura TLS avançada da Cloudflare e uma rota dedicada.

## Diagnóstico

Separe DNS e TLS, aplicação, PHP, banco, volume, Redis e plugin. `NXDOMAIN` na
variante com `www` significa ausência de registro DNS, enquanto certificado
inválido depois da resolução aponta para cobertura TLS insuficiente. Reproduza
com plugin desativado apenas em janela e com rollback aprovado. Não envie banco,
senha, cookies, dados de pedidos ou arquivo de configuração ao Assistente.
