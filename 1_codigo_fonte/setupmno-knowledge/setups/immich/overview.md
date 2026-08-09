---
{
  "schemaVersion": 1,
  "documentId": "setup-immich-overview",
  "documentVersion": "1.0.0",
  "contentSHA256": "d928abb292fd0de643f0c5766c0ce162e53208505530ce6a4757ff35b3cc521c",
  "documentType": "setup",
  "title": "Immich no Setup MNO",
  "setupId": "immich",
  "setupVersion": "7.7.51",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-01",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": ["immich", "fotos", "postgresql", "valkey", "machine-learning"],
  "sources": [
    {"sourceId":"immich-installer","title":"Instalador Immich","sourceType":"setup-mno","location":"x86/SetupLowCodeMno/immich.sh","license":"project-internal","verifiedAt":"2026-08-01"},
    {"sourceId":"immich-requirements","title":"Requirements","sourceType":"official-documentation","location":"https://docs.immich.app/install/requirements/","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"immich-compose","title":"Docker Compose installation","sourceType":"official-documentation","location":"https://docs.immich.app/install/docker-compose/","license":"documentation-reference","verifiedAt":"2026-08-01"},
    {"sourceId":"immich-backup","title":"Backup and restore","sourceType":"official-documentation","location":"https://docs.immich.app/administration/backup-and-restore/","license":"documentation-reference","verifiedAt":"2026-08-01"}
  ],
  "homologation": {"verifiedAt":null,"verifiedPorts":[],"verifiedImages":[]}
}
---
# Immich no Setup MNO

## Quando usar

Use para organizar e consultar uma biblioteca privada de fotos e vídeos com
aplicativos móveis e recursos de aprendizado de máquina. Não trate o Immich
como a única cópia dos arquivos; mídia pessoal exige backup independente e
restauração ensaiada.

## Arquitetura no Setup MNO

O instalador cria banco PostgreSQL especializado, Valkey, serviço de machine
learning e servidor Immich na mesma stack, com volumes de biblioteca, banco,
cache e modelos. A configuração usa a série v3, mas dependências precisam
seguir a matriz oficial da mesma release.

## Pré-requisitos

Exige domínio, TLS, armazenamento local compatível com permissões Unix e espaço
para originais, miniaturas, transcodificação, banco e backup. A documentação
proíbe banco em compartilhamento de rede e requer memória própria para o banco
quando há limites; caminhos NTFS montados pelo WSL2 não são adequados.

## Fluxo seguro

Confirme capacidade e localização dos volumes antes do Instalador Seguro. Não
importe a biblioteca principal até validar conta administrativa, persistência,
processamento e backup. Limite acesso externo e preserve a senha do banco fora
de logs e suporte.

## Primeiro acesso e integrações

Crie o administrador, habilite MFA quando disponível e teste upload descartável
pelo navegador e cliente móvel. Bibliotecas externas, OAuth e aceleração devem
ser configuradas separadamente, seguindo a versão implantada.

## Backup, atualização e rollback

Backup precisa cobrir banco e arquivos da biblioteca de forma coordenada; o
banco não contém a mídia. Antes de atualizar, leia notas e breaking changes,
preserve volumes e banco, mantenha a versão anterior e teste restauração. Não
faça downgrade de schema por simples troca de imagem.

## Validação

Valide upload, miniatura, pesquisa, transcodificação, jobs, persistência e
restauração de item descartável, além de espaço livre e saúde do banco.

## Diagnóstico

Separe proxy, servidor, workers, machine learning, Valkey, PostgreSQL e volumes.
Não envie fotos, nomes de arquivos, coordenadas, credenciais ou dumps ao
Assistente.

## Riscos e limites

O setup é de nó único e não constitui backup nem alta disponibilidade. A
compatibilidade de cada imagem v3 e o consumo real precisam ser homologados nas
duas arquiteturas antes de uma recomendação de produção.
