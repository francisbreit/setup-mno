---
{
  "schemaVersion": 1,
  "documentId": "setup-setupmno-control-overview",
  "documentVersion": "1.5.0",
  "contentSHA256": "086b183d0ec127bb1ef319b8e1ccb09a81c84c7b9ca7c13c571c2d23fadea040",
  "documentType": "setup",
  "title": "Setup MNO Control Center",
  "setupId": "setupmno-control",
  "setupVersion": "7.7.35",
  "architectures": ["amd64", "arm64"],
  "category": "overview",
  "status": "reviewed",
  "updatedAt": "2026-08-02",
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

## Disponibilidade por plano

O Control Center pode ser instalado uma única vez nos planos pro, free, free1
e free2. Inventário, métricas, catálogo, terminal autenticado e diagnóstico
básico local permanecem disponíveis em todos eles.

No plano PRO, o usuário pode conectar OpenAI, OpenRouter, DeepSeek ou Ollama
quando os requisitos do servidor forem atendidos. Nos planos free, free1 e
free2, o Assistente com IA fica desativado e o modo BASIC é obrigatório, mesmo
que exista uma configuração residual de provedor. O instalador não solicita
chave, não cria stack de LLM e o painel bloqueia o proxy para o conector.

A Visão Geral apresenta separadamente versão do Setup MNO, versão do Control
Center, tipo de instalação e plano. O tipo de instalação é Cloudflare Tunnel
ou Tradicional (Traefik), conforme o estado runtime validado.

## Instalação opcional e única

Na primeira preparação da infraestrutura-base, o `dockerswarm.sh` explica a
finalidade do Control Center e pergunta se o usuário deseja instalá-lo. A
resposta negativa não altera o Setup MNO: a instalação continua disponível no
menu principal para outro momento.

Somente uma instalação é aceita por servidor. A presença de qualquer serviço
do Control Center no namespace reservado `mnoctrl` remove a opção do menu. O
instalador também executa o mesmo gate antes de solicitar domínio, usuário,
senha ou provedor, protegendo contra execução direta e menus antigos. Uma trava
exclusiva impede ainda duas instalações simultâneas antes da criação das
stacks.

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
