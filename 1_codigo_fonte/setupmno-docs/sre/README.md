# Setup MNO SRE Knowledge Pack

- Estado: `implemented`
- Versão do pack: `1.2.0`
- Atualizado em: 2026-08-24
- Público: mantenedor PRO MASTER e futura adaptação didática para clientes
- Ambientes: Debian, Ubuntu, WSL2, Docker Desktop e Docker Swarm
- Publicação no Control Center: não publicada

## Resumo para leigos

Este pack ensina a investigar um servidor por camadas, preservar evidências e
propor uma correção segura antes de executar qualquer mudança. A v7.33.0
acrescenta o primeiro Especialista SRE BETA: uma fotografia sanitizada e
somente leitura, exibida no Assistente MNO sem executar correções.

SRE significa cuidar da confiabilidade de um serviço. Na prática, o trabalho
começa respondendo quatro perguntas:

1. O que deveria estar funcionando?
2. Qual camada realmente falhou?
3. Que evidência confirma essa conclusão?
4. Como voltar atrás se a correção piorar o cenário?

## Trilha recomendada

1. [Modelo operacional](architecture/operating-model.md): fatos, diagnóstico,
   plano e execução controlada.
2. [Debian e Ubuntu](manual/debian-ubuntu-baseline.md): baseline do host e
   atualizações seguras.
3. [WSL2 e Docker Desktop](manual/wsl2-docker-desktop.md): reconhecer integração
   desligada ou incorreta.
4. [Docker Swarm](manual/docker-swarm-triage.md): nós, quorum, serviços e tarefas.
5. [Traefik e Cloudflare](manual/traefik-cloudflare.md): separar DNS, borda,
   túnel, TLS, roteamento e aplicação.
6. [Backup e restauração](manual/backup-restore.md): provar que os dados podem
   voltar, não apenas que existe um arquivo de backup.
7. [Resposta a incidentes](manual/incident-response.md): estabilizar, registrar,
   corrigir e aprender.
8. [Perguntas frequentes](faq/primeiros-passos.md): dúvidas comuns de quem está
   começando.
9. [Skill Supply Chain Gate — BETA](architecture/skill-supply-chain-gate.md):
   arquitetura da alfândega de skills externas.
10. [Avaliar uma skill — BETA](manual/avaliar-skill-externa.md): assistente
    guiado e interpretação dos resultados.
11. [FAQ de skills externas — BETA](faq/skills-externas.md): dúvidas sobre
    origem, permissões, hashes e limites.
12. [Especialista SRE somente leitura — BETA](architecture/read-only-specialist.md):
    contrato fechado, dados permitidos, privacidade e fronteira de confiança.
13. [Usar o diagnóstico seguro — BETA](manual/usar-diagnostico-seguro.md):
    passo a passo para leigos, resultados esperados e sinais de falha.

## Limites e segurança

- O pack é documentação versionada, não um executor.
- Exemplos de diagnóstico são somente leitura, salvo quando o texto identifica
  claramente uma futura ação controlada.
- Nenhuma orientação concede `root`, `sudo`, grupo `docker`, Docker socket,
  shell de produção ou credenciais a um modelo de IA.
- Diagnóstico de IA é proposta; autorização é política determinística aplicada
  fora do modelo.
- Mudanças reais dependerão de runbooks fechados, dry-run, confirmação humana,
  evidência, backup e rollback nas etapas posteriores do roadmap.
- Dados reais de clientes, tokens, e-mails, IPs e hostnames não pertencem a esta
  base.

## Integridade e atualização

O arquivo `manifest.json` registra os documentos, fontes oficiais e SHA-256. O
validador é executado no repositório de construção:

```bash
python3 1_codigo_fonte/setupmno-docs/tools/validate-sre-knowledge.py
bash 1_codigo_fonte/setupmno-docs/tools/test-sre-knowledge-validator.sh
bash 1_codigo_fonte/setupmno-docs/tools/test-skill-supply-chain-gate.sh
```

Uma mudança documental sem atualização do manifesto falha. Essa proteção não é
uma assinatura criptográfica de release; ela detecta divergência dentro do
repositório. O Skill Supply Chain Gate BETA aplica um contrato adicional aos
pacotes externos, sem instalá-los ou executá-los.

## Limites atuais

- O único endpoint SRE é uma fotografia BETA, fixa, sanitizada e somente
  leitura; não existe endpoint genérico de Docker ou shell.
- Nenhum scanner foi instalado.
- Nenhuma IA recebeu acesso direto ao servidor ou ao Docker socket.
- Nenhuma skill externa foi instalada ou publicada.
- Nenhum relatório desta pasta entra automaticamente no Help.
- Nenhum diagnóstico substitui backup, observabilidade ou um profissional em
  incidentes críticos.

## Publicação futura no Help

Antes da publicação, cada capítulo deverá ser adaptado para telas curtas,
capturas sanitizadas, GIFs ou vídeos, revisão de segurança e teste de interface.
O Help não deve copiar o pack inteiro nem expor comandos administrativos fora de
contexto.
