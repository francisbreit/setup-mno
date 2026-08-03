---
{
  "schemaVersion": 1,
  "documentId": "setup-nginx-proxy-manager-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "7df3a269c0ef0a9a67b5745f31f9cb0bdc9e478c92a11660267c335f1f53bd17",
  "documentType": "setup",
  "title": "Nginx Proxy Manager no Setup MNO",
  "setupId": "nginx-proxy-manager",
  "setupVersion": "7.7.8",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": ["nginx-proxy-manager", "proxy-reverso", "tls", "gateway"],
  "sources": [
    {"sourceId":"nginx-proxy-manager-installer","title":"Instalador Nginx Proxy Manager","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/nginxproxymanager.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"nginx-proxy-manager-guide","title":"Guia oficial do Nginx Proxy Manager","sourceType":"official-documentation","location":"https://nginxproxymanager.com/guide","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"nginx-proxy-manager-advanced","title":"Configuração avançada oficial","sourceType":"official-documentation","location":"https://nginxproxymanager.com/advanced-config/","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# Nginx Proxy Manager no Setup MNO

## Quando usar

Use somente quando ele será o gateway deliberado de um ambiente separado ou
quando existe um desenho explícito de coexistência. No Setup MNO padrão, Traefik
já ocupa a função de proxy reverso e certificados; adicionar outro gateway pode
criar conflito e duas fontes de verdade.

## Arquitetura no Setup MNO

O instalador cria uma réplica com volumes separados para dados e certificados,
publica portas do host para tráfego e administração e, ao mesmo tempo, cria rota
administrativa pelo Traefik ou túnel. Essa sobreposição arquitetural precisa ser
resolvida antes do deploy, não depois.

## Pré-requisitos

Exige mapa completo das portas do host, proprietário dos certificados, DNS,
upstreams, redes e rollback do gateway atual. O gate de conflito de portas é
obrigatório. Sem autorização específica para substituir ou coexistir com o
Traefik, não prossiga com esta instalação.

## Fluxo seguro

Trate como mudança arquitetural de alto impacto. Faça baseline das rotas atuais,
confirme portas livres, preserve configuração do Traefik e valide primeiro em
host ou stack isolada. O Instalador Seguro coleta domínio e modo Portainer ou
Docker, mas essa coleta não elimina o conflito de gateway.

## Primeiro acesso e integrações

Se aprovado em ambiente isolado, altere a credencial administrativa inicial,
crie um único proxy host de teste e valide certificado e upstream sem expor
serviços internos. Use rede Docker comum para upstreams em vez de publicar
portas desnecessárias.

## Backup e atualização

Backup deve cobrir dados de configuração e certificados. Fixe versão para uso
controlado e teste atualização fora da produção. O rollback requer restaurar os
volumes e devolver ao gateway anterior a propriedade das portas e rotas sem
manter ambos respondendo de forma ambígua.

## Validação

Confirme ausência de conflito, acesso administrativo protegido, emissão ou
importação de certificado, proxy para alvo descartável, headers e persistência.
Teste também o rollback para Traefik. Tela administrativa aberta não prova que o
gateway está seguro.

## Riscos e limites

Status crítico no ambiente padrão porque o script publica porta de TLS usada
normalmente pelo Traefik. A imagem móvel e a administração de certificados por
dois componentes aumentam imprevisibilidade. Não recomende automaticamente este
setup em servidor Setup MNO já operacional.

## Diagnóstico

Primeiro verifique conflito de porta e qual gateway recebeu a conexão; depois
DNS, TLS, rede e upstream. Não altere o Traefik para “testar”. Use hostnames
fictícios e erros sanitizados, sem certificados privados ou credenciais.
