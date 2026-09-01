# Revisão de Segurança: Blueprint #001

## Identificação
- **Blueprint:** `blueprint-001-whatsapp-marketing-completo`
- **Versão:** `1.0.0`
- **Data de Revisão:** 2026-08-31
- **Responsável:** Equipe de Segurança e Arquitetura Setup MNO

## Análise de Riscos e Mitigações
1. **Proteção Anti-Bloqueio (Anti-Ban):**
   - Implementação obrigatória de delay randômico de 5 a 15 segundos entre disparos no n8n.
   - Enfileiramento via RabbitMQ que impede sobrecarga instantânea na Evolution API.
2. **Segregação de Redes e Acesso:**
   - Comunicação interna entre n8n, RabbitMQ e MinIO através de rede overlay privada (`interna`).
   - Autenticação com Bearer Token e Global API Key em todos os endpoints de webhooks.
3. **Isolamento de Secrets:**
   - Credenciais de banco PostgreSQL, RabbitMQ e MinIO gerenciadas via Docker Secrets/Configs sem exposição em variáveis públicas.
4. **Resiliência de Armazenamento:**
   - S3 MinIO configurado com buckets separados e políticas de acesso restritas para Chatwoot e Typebot.

## Conclusão
A arquitetura atende a todos os requisitos de segurança, confidencialidade e isolamento para operação em produção.
