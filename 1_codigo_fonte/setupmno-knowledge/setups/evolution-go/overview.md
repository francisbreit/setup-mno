---
{
  "schemaVersion": 1,
  "documentId": "setup-evolution-go-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "e664f40e40215df432cac2205e55749a8260a0c2ec258b3eee9fa4bbbdbafb41",
  "documentType": "setup",
  "title": "Evolution Go no Setup MNO",
  "setupId": "evolution-go",
  "setupVersion": "7.7.44",
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
    "evolution-go",
    "whatsapp",
    "api",
    "mensageria"
  ],
  "sources": [
    {
      "sourceId": "evolution-go-installer",
      "title": "Instalador Evolution Go",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/evolutiongo.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "evolution-go-official-1",
      "title": "Documentação oficial de Evolution Go",
      "sourceType": "official-documentation",
      "location": "https://github.com/EvolutionAPI/evolution-go",
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
# Evolution Go no Setup MNO

## Quando usar

Use para avaliar a implementação em Go da API de integração WhatsApp do ecossistema Evolution. A recomendação deve considerar finalidade, dados tratados, manutenção e alternativa mais simples; a existência no catálogo não significa homologação automática.

## Arquitetura no Setup MNO

O instalador provisiona a API e o gerenciador conforme o script, com rota web e persistência. Embora leve, a aplicação mantém sessões e credenciais de mensageria que exigem proteção.

## Pré-requisitos

Exige domínio HTTPS, número de teste, chave forte, política de webhooks e cópia das sessões. Confirme release, arquitetura da imagem e compatibilidade dos clientes atuais.

## Fluxo seguro

Execute somente pelo Instalador Seguro, confirme o resumo antes do deploy e não publique portas administrativas adicionais. Credenciais permanecem fora do Assistente e operações reais continuam sujeitas à confirmação humana.

## Primeiro acesso e integrações

Crie uma instância de teste, proteja o gerenciador e valide conexão, envio e webhook com conteúdo sintético. Restrinja origens e não deixe o painel aberto.

## Backup e atualização

Preserve sessões, banco ou volume e configuração de webhooks. Registre a versão real; teste restauração e reconexão sem reutilizar credenciais produtivas.

## Validação

Confirme HTTPS, autenticação, persistência após recriação controlada, saúde das réplicas e o fluxo funcional mínimo com dados fictícios. Registre versões efetivas e evidências sem segredos; só promova após um teste de restauração aplicável.

## Riscos e limites

Integrações não oficiais de WhatsApp podem quebrar ou causar bloqueio. O Setup não garante disponibilidade do provedor nem estabilidade do protocolo. Procedência de imagens deve ser homologada.

## Diagnóstico

Separe gerenciador, API, sessão, rede e webhook. Use códigos de erro e horários, removendo QR, tokens, números e mensagens antes de compartilhar evidência.
