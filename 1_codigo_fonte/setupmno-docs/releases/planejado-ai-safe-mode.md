# AI Safe Mode

- Versão planejada: a definir após o gate de cadeia de suprimentos e SBOM
- Estado: `draft`
- Atualizado em: 2026-08-23
- Tipo: segurança, governança, UX e produtividade
- Impacto: crítico

## Resumo

O AI Safe Mode permitirá que usuários utilizem agentes como Codex, Claude
Code, Hermes Agent e OpenClaw para diagnóstico, aprendizagem e preparação de
mudanças sem entregar a eles acesso root, Docker socket ou autoridade direta
sobre a produção.

O projeto completo está em `../architecture/ai-safe-mode.md`.

## Decisão desta etapa

Esta etapa registra somente arquitetura, permissões, experiência, gates e
rollback. Não cria serviço, usuário Linux, stack, terminal, rota, DNS, segredo
ou mudança no Control Center.

## Dependência

A primeira implementação com artefatos externos deve consumir a futura
atestação de cadeia de suprimentos e SBOM. O desenho não substitui nem marca
esse item do roadmap como concluído.

## Rollback desta etapa documental

Como não existe mudança de runtime, o rollback consiste em reverter os arquivos
de documentação e a entrada do roadmap. Nenhum servidor de cliente é afetado.
