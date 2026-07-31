---
{
  "schemaVersion": 1,
  "documentId": "setup-setupmno-control-overview",
  "documentVersion": "1.3.0",
  "contentSHA256": "6a64421e8e584ff4c80f2fa2efb69231c9cc2f93d153f2b0472b52a68799b21f",
  "documentType": "setup",
  "title": "Setup MNO Control Center",
  "setupId": "setupmno-control",
  "setupVersion": "4.99.1",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-07-31",
  "sourceType": "setup-mno",
  "risk": "critical",
  "language": "pt-BR",
  "tags": ["setupmno-control", "devops", "assistente"],
  "sources": [
    {
      "sourceId": "setupmno-control-installer",
      "title": "Instalador do Control Center",
      "sourceType": "setup-mno",
      "location": "x86/SetupLowCodeMno/setupmno_control.sh",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    },
    {
      "sourceId": "setupmno-control-readme",
      "title": "Arquitetura do Control Center",
      "sourceType": "setup-mno",
      "location": "setupmno-control/README.md",
      "license": "project-internal",
      "verifiedAt": "2026-07-30"
    }
  ],
  "homologation": {
    "verifiedAt": null,
    "verifiedPorts": [],
    "verifiedImages": []
  }
}
---
# Setup MNO Control Center

## Quando usar

Use para visualizar estado sanitizado do ambiente, consultar o Assistente e
acessar o Instalador Seguro autenticado. O painel não substitui Portainer nem
oferece administração Docker genérica.

## Arquitetura no Setup MNO

Painel, agente de leitura, terminal e conector do Assistente são stacks
separadas. Somente agente e terminal recebem acessos estritamente necessários.
O painel permanece sem socket Docker e sem mount do host.

## Pré-requisitos

Exige infraestrutura-base, domínio, memória mínima do modo escolhido e pacote
runtime consistente. OpenAI, OpenRouter, DeepSeek e Ollama são opcionais; o
diagnóstico básico deve permanecer disponível. OpenAI é a seleção inicial do
instalador quando os requisitos mínimos de memória são atendidos.

## Fluxo seguro

O instalador constrói imagens no Whiptail, executa gates de compatibilidade,
cria secrets e implanta stacks isoladas. O Terminal Seguro expõe somente um
menu fixo para abrir o instalador original ou a Central de Configurações, após
autenticação, e limita sessões concorrentes.

Os fontes compactados do painel permanecem fora do script protegido pelo SHC.
O arquivo `control-source.tar.gz` possui tamanho e SHA-256 no manifesto,
é promovido atomicamente para o estado runtime e validado novamente antes do
build local.

## Central de Configurações

A opção Configurações fica abaixo de Auditoria no menu lateral. Ela apresenta
o usuário administrador e o provedor ativo, mas não coleta credenciais no
navegador. Alterações de usuário, senha, provedor, modelo e chave são feitas
no Whiptail do Terminal Seguro com confirmação da senha atual.

Senhas e chaves seguem rotação por Docker Secrets versionados. O novo serviço
precisa atingir estado saudável antes da remoção da referência anterior; se a
validação falhar, o serviço executa rollback. O painel e o Assistente continuam
sem socket Docker, mount do host, shell ou endpoint genérico de escrita.

## RAG fundamentado

Quando um provedor de LLM está ativo, o retrieval local seleciona candidatos
do pacote canônico. Somente resultados de confiança alta ou média, sem fallback
legado e provenientes de documentos `reviewed` ou `homologated`, podem
fundamentar a resposta. Baixa confiança e evidências inválidas permanecem
somente na inspeção.

O contexto enviado ao provedor aceita no máximo quatro trechos, 1.800
caracteres por trecho e 6.000 no total. Documento, versão, seção, arquitetura e
SHA-256 acompanham cada referência `[Fonte N]`. A evidência segue em uma
mensagem de dados separada das instruções do sistema, que proíbem documentos de
alterar identidade, autoridade ou políticas e tratam comandos apenas como
conteúdo explicativo.

A inspeção continua efêmera e permanece somente na sessão do navegador. Ela
não inclui pergunta, histórico, contexto operacional ou score bruto. A
interface distingue evidências usadas na resposta das mantidas apenas para
auditoria. O modo básico e a contingência local não executam o RAG.

## Validação

Confirme autenticação, versões separadas, catálogo runtime, métricas, terminal
desktop e touch, troca de usuário e senha, cada provedor, Assistente básico e
fallback. Em consultas com LLM, abra a inspeção, confirme as fontes usadas e
verifique citações `[Fonte N]`. Teste confiança insuficiente, fallback legado,
limites do contexto e prompt injection em documentos. Conectores opcionais
exigem testes válidos e inválidos sem vazamento de dados operacionais, pergunta
ou histórico no bloco de evidências.

## Riscos e limites

Adicionar shell ou comando Docker ao painel ou ao Assistente quebra a
arquitetura. Somente o Terminal Seguro pode aplicar as transações previamente
permitidas. Estado runtime inconsistente exige fallback marcado como
desatualizado. Nenhuma ação real pode ser executada pelo Copiloto durante o
Beta.

## Diagnóstico

Identifique primeiro qual stack falhou. Painel sem dados difere de terminal
indisponível e provedor de IA fora do ar. O fallback local deve permanecer
visível e registrar a ocorrência na auditoria.
