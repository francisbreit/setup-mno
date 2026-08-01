---
{
  "schemaVersion": 1,
  "documentId": "setup-wordpress-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "c01ee48d8e8932728473c3c9d31ec27ab30306d5c17f0a8078b42907d40dcda9",
  "documentType": "setup",
  "title": "WordPress no Setup MNO",
  "setupId": "wordpress",
  "setupVersion": "7.2.6",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": ["wordpress", "cms", "mysql", "redis", "backup"],
  "sources": [
    {"sourceId":"wordpress-installer","title":"Instalador WordPress","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/wordpress.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"wordpress-update-docs","title":"Atualização oficial do WordPress","sourceType":"official-documentation","location":"https://wordpress.org/documentation/article/updating-wordpress/","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"wordpress-maintenance-docs","title":"Manutenção oficial de sites WordPress","sourceType":"official-documentation","location":"https://wordpress.org/documentation/article/wordpress-site-maintenance/","license":"documentation-reference","verifiedAt":"2026-08-01"}
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
persistente e rota pública, e aponta cache para o Redis base. Banco, arquivos e
cache são dependências distintas. A imagem da aplicação é móvel e exige controle
de atualização fora de mudanças automáticas imprevisíveis.

## Pré-requisitos

Exige domínio, MySQL saudável, Redis base, volume, SMTP ou serviço transacional
quando necessário e recursos proporcionais a tráfego, plugins e mídia. Defina
administrador, política de plugins, atualização, backup, retenção e proteção de
login antes de publicar.

## Fluxo seguro

O Instalador Seguro coleta domínio, nome da base e modo Portainer ou Docker,
prepara banco e volume e implanta a aplicação. No primeiro acesso, use conta
administrativa individual, habilite menor privilégio para editores e remova
temas ou plugins não usados.

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
outras aplicações.

## Diagnóstico

Separe DNS e TLS, aplicação, PHP, banco, volume, Redis e plugin. Reproduza com
plugin desativado apenas em janela e com rollback aprovado. Não envie banco,
senha, cookies, dados de pedidos ou arquivo de configuração ao Assistente.
