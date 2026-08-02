---
{
  "schemaVersion": 1,
  "documentId": "setup-jitsi-meet-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "93a915d32e3e6d60938ba50cee6c44df4bc13f1cb594486018307f44a0966a18",
  "documentType": "setup",
  "title": "Jitsi Meet no Setup MNO",
  "setupId": "jitsi-meet",
  "setupVersion": "7.2.11",
  "architectures": [
    "amd64",
    "arm64"
  ],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": [
    "jitsi-meet",
    "videoconferencia",
    "webrtc",
    "xmpp"
  ],
  "sources": [
    {
      "sourceId": "jitsi-meet-installer",
      "title": "Instalador Jitsi Meet",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/jitsi.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "jitsi-meet-official-1",
      "title": "Documentação oficial de Jitsi Meet",
      "sourceType": "official-documentation",
      "location": "https://jitsi.github.io/handbook/docs/devops-guide/devops-guide-docker/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    }
  ],
  "homologation": {
    "verifiedAt": null,
    "verifiedPorts": [],
    "verifiedImages": []
  }
}
---
# Jitsi Meet no Setup MNO

## Quando usar

Use para oferecer videoconferência self-hosted com mídia em tempo real. A recomendação deve considerar finalidade, dados tratados, manutenção e alternativa mais simples; a existência no catálogo não significa homologação automática.

## Arquitetura no Setup MNO

O instalador coordena interface web, Prosody, Jicofo e videobridge em serviços relacionados. Além da rota HTTPS, WebRTC depende do tráfego de mídia e do endereço anunciado pelo videobridge; o catálogo estima carga elevada.

## Pré-requisitos

Exige pelo menos a capacidade indicada pelo catálogo, domínio e certificado válidos, conectividade UDP, IP público ou estratégia NAT e senhas internas fortes e únicas.

## Fluxo seguro

Execute somente pelo Instalador Seguro, confirme o resumo antes do deploy e não publique portas administrativas adicionais. Credenciais permanecem fora do Assistente e operações reais continuam sujeitas à confirmação humana.

## Primeiro acesso e integrações

Valide uma sala entre duas redes diferentes, microfone, câmera e compartilhamento de tela. Ative autenticação para criação de salas quando o serviço não for estritamente privado.

## Backup e atualização

Preserve configuração, segredos internos e personalizações; gravações, se habilitadas, exigem backup separado. Antes de atualizar, use a mesma família de release em todos os componentes.

## Validação

Confirme HTTPS, autenticação, persistência após recriação controlada, saúde das réplicas e o fluxo funcional mínimo com dados fictícios. Registre versões efetivas e evidências sem segredos; só promova após um teste de restauração aplicável.

## Riscos e limites

Sem fluxo UDP funcional, a página abre mas a mídia falha. Carga cresce com participantes e qualidade. WSL2, NAT e Cloudflare Tunnel não substituem automaticamente a rota de mídia.

## Diagnóstico

Teste em ordem: DNS/TLS, web, XMPP, foco, videobridge e mídia externa. Compare dois clientes de redes distintas e sanitize nomes de sala, IPs e identidades.
