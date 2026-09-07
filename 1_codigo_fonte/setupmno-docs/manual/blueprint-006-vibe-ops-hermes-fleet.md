# Manual Operacional: Blueprint #006 — Vibe Ops (Hermes Agent & Fleet Hub)

---

## 1. Identificação e Maturidade
- **Blueprint ID:** `blueprint-006-vibe-ops-hermes-fleet`
- **Versão:** `1.0.0`
- **Maturidade:** `homologated` (Produção)
- **Ambientes Homologados:** WSL2 + Docker Desktop (x86_64) e VPS Ubuntu/Debian (x86_64 / ARM64)
- **Data da Homologação:** 06/09/2026
- **Homologado por:** Francis Breit (Francis MNO)

---

## 2. Para Iniciantes (Visão Didática)

### O que este Blueprint faz?
Ele coloca uma Inteligência Artificial especializada em infraestrutura (o **Hermes Agent**) para cuidar da sua rede de servidores em tempo real, sem que você precise abrir terminais pretos ou digitar comandos difíceis do Linux.

1. **Monitoramento 24h com Zero Consumo de Memória:** O **MNO Sentinel** fica de vigia. Se a memória de uma VPS encher ou um servidor cair, ele detecta no mesmo instante;
2. **Triagem Automática:** Em vez de receber apenas um aviso assustador de erro, o Sentinel avisa o Hermes Agent, que investiga o servidor e explica para você: *"A VPS Hetzner está com 88% de memória porque o banco de dados recebeu muitos acessos. Sugiro instalar o novo aplicativo na VPS 2, que tem 6 GB livres"*;
3. **Conversa em Linguagem Natural:** Você pode perguntar no Telegram ou no WhatsApp: *"Como estão meus servidores hoje?"* e o Hermes responde com um boletim completo em segundos;
4. **Instalação com 1 Clique:** Se você quiser instalar o WordPress ou o Chatwoot em uma VPS da frota, o Hermes avalia o espaço e entrega o link exato do instalador seguro para você autorizar.

---

## 3. Nota Técnica para DevOps

### Topologia e Componentes
- **Torre Master (WSL2 / VPS):** Hospeda o `Setup MNO Control Center 4.44.3`, o inventário seguro do `Fleet Hub` e o daemon em goroutine `MNO Sentinel`.
- **API de Ferramentas (`/api/fleet/tools/schema.json`):** Expõe 6 ferramentas padronizadas no formato OpenAI Function Calling / Hermes Agent:
  - `fleet_get_status`
  - `fleet_list_nodes`
  - `fleet_diagnose_node`
  - `fleet_consult_dispatch`
  - `fleet_ping_node`
  - `fleet_sentinel_status`
- **Execução Segura (`/api/fleet/tools/execute`):** Executa sondagens atômicas com validação rigorosa de entrada, fail-closed e autenticação via Bearer token ou sessão ativa.
- **Túneis Cloudflare Tunnel:** Conexão criptografada de ponta a ponta sem qualquer porta exposta na internet pública (zero portas abertas no firewall).
- **Orquestrador n8n:** Recebe os webhooks do Sentinel, aciona o nó LangChain Agent (Hermes/OpenAI/Anthropic) e despacha alertas enriquecidos para canais administrativos.

### Requisitos de Recursos Medidos em Homologação
- **Overhead Adicional na VPS:** **0 MB de RAM** (o Sentinel e o Fleet Hub rodam dentro do binário já existente em Go, dispensando pilhas pesadas de Prometheus/Grafana de 2 GB).
- **Requisitos do n8n / Agente:** 1 a 2 GB de RAM no nó onde o n8n estiver alocado.

---

## 4. Roteiro Oficial de Instalação e Ativação

1. **Configuração de Alertas do Sentinel:**
   - Acesse o Setup MNO Control Center -> aba **Frota MNO** -> card **MNO Sentinel**;
   - Clique em **⚙️ Configurar Alertas**, configure os limites de RAM/Disco e informe o endpoint do Webhook do n8n;
   - Clique em **🧪 Testar Disparo de Alerta Agora** para auditar a conectividade.
2. **Importação dos Fluxos no n8n:**
   - Importe `01_Workflow_Hermes_Vibe_Ops_Fleet_Orchestrator.json` para habilitar o chat interativo com o Hermes SRE;
   - Importe `02_Workflow_Sentinel_Webhook_Triagem_IA.json` para habilitar a triagem autônoma de incidentes.
3. **Validação de Tool Calling:**
   - Envie a mensagem *"Qual o status consolidado da minha frota?"* para testar a chamada da ferramenta `fleet_get_status`.
   - Simule um probe com *"Faça um diagnóstico na VPS Debian1"* para validar `fleet_diagnose_node`.
