# AI Safe Mode — primeiros passos

- Estado: `draft`
- Público: usuários iniciantes e operadores experientes
- Disponibilidade: planejada; ainda não existe no produto
- Atualizado em: 2026-08-23

## O que será

O AI Safe Mode será o local seguro para pedir ajuda a uma IA sobre o servidor.
A IA poderá explicar, diagnosticar e preparar uma proposta, mas não alterará a
produção diretamente.

Enquanto a função não estiver implementada, este documento é apenas uma
prévia da experiência desejada.

## Jornada esperada

1. O usuário abre **AI Safe Mode**.
2. Escolhe entre **Entender um problema**, **Planejar uma aplicação**,
   **Verificar segurança** ou **Avaliar capacidade**.
3. A tela informa exatamente quais dados serão analisados.
4. O Setup MNO coleta somente informações permitidas e remove dados sensíveis.
5. A IA apresenta uma explicação simples e um plano; a faixa
   **Nenhuma alteração foi realizada** permanece visível.
6. Se houver uma proposta técnica, o Setup MNO executa gates determinísticos e
   mostra o resultado em verde, amarelo ou vermelho.
7. Testes que exijam execução ocorrem somente em laboratório isolado.
8. Uma alteração real continua no Instalador Seguro, com confirmação humana,
   backup aplicável e rollback definido.

## O que o usuário nunca deverá fazer

- abrir o agente como `root` na pasta `/root`;
- conceder acesso ao Docker socket;
- colar senhas, tokens, chaves SSH ou arquivos `.env` no chat;
- desligar permissões ou usar modos como `yolo`;
- aceitar exclusão de volume ou alteração de banco sem backup e restore
  comprovados;
- tratar uma resposta da IA como prova de homologação.

## Mensagens que a interface deve usar

- **Nenhuma alteração foi realizada.**
- **A IA preparou uma proposta; o Setup MNO ainda precisa validá-la.**
- **Bloqueado por segurança: esta ação exige acesso não permitido.**
- **Teste executado somente no laboratório. A produção não foi alterada.**
- **Rollback indisponível para os dados atuais; a publicação foi bloqueada.**

## Onde pedir detalhes

O modo simples esconderá comandos e detalhes internos. A opção **Ver detalhes
técnicos** mostrará evidências, hashes, digests, gates e logs sanitizados para
operadores experientes.
