---
{
  "schemaVersion": 1,
  "documentId": "setup-uptime-kuma-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "ad9d9c80a0d490c71258d41ac7d82c69e5e5f9573f816d65adc152a2024e579a",
  "documentType": "setup",
  "title": "Uptime Kuma no Setup MNO",
  "setupId": "uptime-kuma",
  "setupVersion": "7.48.23",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "medium",
  "language": "pt-BR",
  "tags": ["uptime-kuma", "monitoramento", "disponibilidade", "alertas"],
  "sources": [
    {"sourceId":"uptime-kuma-installer","title":"Instalador Uptime Kuma","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/uptimekuma.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"uptime-kuma-repository","title":"Repositório oficial Uptime Kuma","sourceType":"official-documentation","location":"https://github.com/louislam/uptime-kuma","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"uptime-kuma-update","title":"Atualização oficial do Uptime Kuma","sourceType":"official-documentation","location":"https://github.com/louislam/uptime-kuma/wiki/%F0%9F%86%99-How-to-Update","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# Uptime Kuma no Setup MNO

## Quando usar

Use para monitorar disponibilidade, tempo de resposta, certificados e serviços
externos ou internos, com notificações e páginas de status. Ele mede sintomas;
não substitui métricas profundas, logs, tracing nem monitoramento externo ao
mesmo provedor onde a aplicação está hospedada.

## Arquitetura no Setup MNO

O instalador cria uma réplica no manager, volume persistente e rota pública pelo
Traefik ou túnel. O banco e as configurações ficam no diretório persistente da
aplicação. A entrada atual usa a linha principal antiga do projeto por
compatibilidade e deve ser atualizada em janela planejada.

## Pré-requisitos

Exige domínio, volume, destinos de notificação e uma lista de serviços com
responsável e objetivo de disponibilidade. Defina intervalos que não sobrecarreguem
os alvos, dependências de rede e pelo menos um monitor externo para o próprio
servidor quando isso for crítico.

## Fluxo seguro

O Instalador Seguro coleta domínio e modo Portainer ou Docker, cria volume e
implanta o serviço. No primeiro acesso, crie o administrador, configure
notificação de teste e adicione poucos monitores. Credenciais de destinos devem
ter escopo mínimo e não aparecer em nomes ou mensagens públicas.

## Primeiro acesso e integrações

Teste um alvo descartável em estados saudável e indisponível. Configure
notificações, janelas de manutenção e dependências para evitar tempestade de
alertas. Páginas de status devem publicar apenas informações apropriadas ao
público.

## Backup e atualização

Faça backup direto do volume ou diretório de dados; o backup interno da aplicação
não deve ser a única cópia. Antes de migrar entre linhas principais, consulte as
instruções oficiais, preserve cópia restaurável e valide em instância isolada.
Recriar o contêiner só é seguro quando o mesmo volume é remontado.

## Validação

Confirme login, criação do monitor, transição controlada de estado, entrega e
recuperação da notificação, persistência e página de status quando usada. Verifique
também se o próprio monitor continua acessível após recriação.

## Riscos e limites

Monitor no mesmo host pode ficar indisponível junto com o serviço monitorado e
não alertar. Intervalos agressivos causam falso positivo ou carga. A linha de
imagem atual é dívida de atualização e não deve ser apresentada como versão mais
recente do projeto.

## Diagnóstico

Separe falha do alvo, DNS, TLS, rota do monitor, notificação e relógio. Use URL
fictícia e erro sanitizado. Não envie tokens de notificação, destinos privados,
lista real de clientes ou conteúdo de incidentes ao Assistente.
