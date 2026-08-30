# Guia de Onboarding e Primeiros Passos no Setup MNO

- Versão documental: `1.0.0`
- Estado: `implemented`
- Maturidade: `BETA`
- Escopo: Todos os usuários e planos (Free, Pro, Pro Master)
- Ambientes: Desktop e Mobile (Android/iOS) em VPS e WSL2

## Para iniciantes

Bem-vindo ao Setup MNO! Se você acabou de instalar o servidor ou abriu o painel pela primeira vez, este guia orienta sua jornada em **4 passos simples**:

### Passo 1: Verificação da Saúde do Servidor
No topo do painel (**Visão Geral**), confira se os medidores de Processador (CPU), Memória RAM e Armazenamento em Disco estão dentro dos limites seguros (abaixo de 80%).

### Passo 2: Validação dos Serviços Base
O Setup MNO utiliza uma base sólida composta por:
- **PostgreSQL (`postgres_db`):** Banco de dados relacional principal;
- **Redis:** Cache de alta performance para filas e sessões;
- **Traefik / Cloudflare:** Roteamento seguro com HTTPS automático.
Confira se esses serviços estão com status verde em **Aplicações instaladas**.

### Passo 3: Realizar o seu Primeiro Deploy
Abra o **Catálogo de Setups** ou clique em **Novo deploy** no topo da tela:
- Escolha uma ferramenta (ex: *Chatwoot*, *Evolution API*, *N8N*, *Typebot* ou *Dify*);
- Abra o Instalador Seguro e informe os dados solicitados (domínio e senha);
- Aguarde a conclusão do deploy e acesse a URL gerada!

### Passo 4: Segurança e Resiliência
- Ative a autenticação de dois fatores (**Cloudflare MFA**) nas Configurações;
- Visite a aba **Resiliência** para conferir a prontidão de backup e persistência da sua aplicação.

---

## Modelo mental

Configurar o servidor é como entrar em um escritório novo:
1. Primeiro você confere a eletricidade e a rede (Hardware/Swarm);
2. Liga a água e os serviços básicos (Bancos/Proxy);
3. Coloca os computadores e ferramentas de trabalho (Aplicações instaladas);
4. Tranca as portas e guarda a chave reserva no cofre (MFA e Backups).

---

## Dicas para Navegação no Celular (Android / iOS)

- O menu lateral pode ser aberto e fechado tocando no botão **☰** no canto superior esquerdo;
- Os cartões de métricas e status adaptam-se automaticamente à tela na vertical;
- Para alternar entre o modo escuro e o modo claro, toque no ícone de sol/lua **☀** no topo da tela.
