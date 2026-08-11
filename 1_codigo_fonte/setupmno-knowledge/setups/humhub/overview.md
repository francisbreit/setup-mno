---
{
  "schemaVersion": 1,
  "documentId": "setup-humhub-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "a554c668c5c75dce6c7ed9456e424d7977f7badb20b1b1aa8e64e0ffb50691e5",
  "documentType": "setup",
  "title": "HumHub no Setup MNO",
  "setupId": "humhub",
  "setupVersion": "7.12.4",
  "architectures": [
    "amd64"
  ],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "high",
  "language": "pt-BR",
  "tags": [
    "humhub",
    "rede-social",
    "intranet",
    "colaboracao"
  ],
  "sources": [
    {
      "sourceId": "humhub-installer",
      "title": "Instalador HumHub",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/humhub.sh",
      "license": "project-internal",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "humhub-official-1",
      "title": "Documentação oficial de HumHub",
      "sourceType": "official-documentation",
      "location": "https://docs.humhub.org/",
      "license": "documentation-reference",
      "verifiedAt": "2026-08-01"
    },
    {
      "sourceId": "humhub-official-2",
      "title": "Documentação oficial de HumHub",
      "sourceType": "official-documentation",
      "location": "https://github.com/humhub/humhub",
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
# HumHub no Setup MNO

## Quando usar

Use para criar uma intranet ou comunidade social privada. A recomendação deve considerar finalidade, dados tratados, manutenção e alternativa mais simples; a existência no catálogo não significa homologação automática.

## Arquitetura no Setup MNO

O instalador está limitado a amd64 e executa HumHub com banco e volume persistente atrás do proxy. Módulos adicionais alteram schema, permissões e requisitos de manutenção.

## Pré-requisitos

Exige domínio HTTPS, SMTP, banco, política de cadastro e moderação. Defina responsáveis, retenção, limites de upload e módulos permitidos.

## Fluxo seguro

Execute somente pelo Instalador Seguro, confirme o resumo antes do deploy e não publique portas administrativas adicionais. Credenciais permanecem fora do Assistente e operações reais continuam sujeitas à confirmação humana.

## Primeiro acesso e integrações

Crie o administrador, feche cadastro se a comunidade for privada e configure funções e moderação. Teste espaço, postagem, convite e notificação com usuários fictícios.

## Backup e atualização

Preserve banco, arquivos enviados, configuração e lista de módulos. Atualize primeiro módulos compatíveis e ensaie a migração; rollback precisa dos mesmos arquivos e banco.

## Validação

Confirme HTTPS, autenticação, persistência após recriação controlada, saúde das réplicas e o fluxo funcional mínimo com dados fictícios. Registre versões efetivas e evidências sem segredos; só promova após um teste de restauração aplicável.

## Riscos e limites

Conteúdo de usuários exige moderação, privacidade e resposta a abuso. Módulos de terceiros podem introduzir vulnerabilidades. Não habilite federação ou acesso público sem decisão explícita.

## Diagnóstico

Diferencie rota, banco, SMTP, permissões de arquivo e módulo. Desative somente o módulo identificado em ambiente de teste e sanitize nomes, mensagens e anexos.
