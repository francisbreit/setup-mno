# Revisão de Segurança: Blueprint #002

## Identificação
- **Blueprint:** `blueprint-002-ia-whatsapp-sdr-crm`
- **Versão:** `1.0.0`
- **Data de Revisão:** 2026-09-03
- **Responsável:** Equipe de Segurança e Arquitetura Setup MNO

## Análise de Riscos e Mitigações
1. **Proteção de Chaves de API e Provedores de IA:**
   - Credenciais de modelos LLM (OpenAI, Groq ou endpoint local vLLM/Ollama) restritas às variáveis internas do n8n sem exposição em frontends públicos.
2. **Mitigação de Alucinação e Prompt Injection:**
   - Persona de SDR configurada com boundary rígido: recusa comandos externos de execução e opera exclusivamente em modo consultivo de produtos/serviços.
3. **Proteção Anti-Bloqueio (Anti-Ban) no WhatsApp:**
   - Respostas geradas com intervalo humanizado e envio prévio de presença de digitação (`composing`) via Evolution API.
   - Follow-up anti-vácuo com intervalo mínimo de 2 horas e limite máximo de 3 contatos antes de arquivamento.
4. **Segregação de Dados e LGPD:**
   - Dados de clientes e históricos de conversas armazenados em volumes privados do Docker Swarm na rede overlay interna.

## Conclusão
A arquitetura atende a todos os critérios de conformidade, confidencialidade e segurança para operação em ambientes corporativos e agências.
