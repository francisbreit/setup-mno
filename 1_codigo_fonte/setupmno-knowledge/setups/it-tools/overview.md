---
{
  "schemaVersion": 1,
  "documentId": "setup-it-tools-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "6268c3dd90be66a572b8fc453e60eb00daec4e29ac8df646aaca5a7b1a7a9b3e",
  "documentType": "setup",
  "title": "IT-Tools no Setup MNO",
  "setupId": "it-tools",
  "setupVersion": "7.48.16",
  "architectures": [
    "amd64",
    "arm64"
  ],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "medium",
  "language": "pt-BR",
  "tags": [
    "it-tools",
    "utilitarios",
    "desenvolvimento",
    "privacidade"
  ],
  "sources": [
    {
      "sourceId": "it-tools-installer",
      "title": "Instalador IT-Tools",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/it_tools.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "it-tools-official-1",
      "title": "Documentação oficial de IT-Tools",
      "sourceType": "official-documentation",
      "location": "https://github.com/CorentinTh/it-tools",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "it-tools-official-2",
      "title": "Documentação oficial de IT-Tools",
      "sourceType": "official-documentation",
      "location": "https://hub.docker.com/r/corentinth/it-tools/",
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
# IT-Tools no Setup MNO

## Quando usar

Use para oferecer utilitários de texto, rede, codificação e desenvolvimento diretamente no navegador. A recomendação deve considerar finalidade, dados tratados, manutenção e alternativa mais simples; a existência no catálogo não significa homologação automática.

## Arquitetura no Setup MNO

O instalador entrega uma aplicação web estática atrás do Traefik ou túnel, sem banco operacional obrigatório. O baixo estado simplifica backup, mas a imagem e a rota ainda precisam de controle de versão.

## Pré-requisitos

Exige domínio HTTPS e decisão sobre exposição pública. Mesmo com processamento no navegador, não assuma privacidade sem verificar o utilitário e o bundle efetivo.

## Fluxo seguro

Execute somente pelo Instalador Seguro, confirme o resumo antes do deploy e não publique portas administrativas adicionais. Credenciais permanecem fora do Assistente e operações reais continuam sujeitas à confirmação humana.

## Primeiro acesso e integrações

Abra alguns utilitários com dados fictícios e confirme que não há cadastro ou endpoint administrativo. Restrinja a rota se a política não permitir ferramenta pública.

## Backup e atualização

Não há conteúdo de negócio esperado; preserve apenas configuração específica, se houver. Para rollback, restaure a imagem e labels anteriores e confirme o mesmo conjunto de ferramentas.

## Validação

Confirme HTTPS, autenticação, persistência após recriação controlada, saúde das réplicas e o fluxo funcional mínimo com dados fictícios. Registre versões efetivas e evidências sem segredos; só promova após um teste de restauração aplicável.

## Riscos e limites

Nunca cole senhas, tokens, chaves privadas ou dados de clientes em utilitários web. Ferramentas de criptografia e conversão não substituem processos auditados. Tags flutuantes podem mudar o bundle.

## Diagnóstico

Separe falha de DNS/TLS, proxy e assets do navegador. Teste janela anônima, cache limpo e um valor fictício; não inclua o dado original em logs.
