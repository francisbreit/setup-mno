# FAQ — supply chain e SBOM

## A v7.30.0 garante que todas as imagens são seguras?

Não. Ela cria rastreabilidade e evidencia referências mutáveis. Segurança de
imagem também exige atualização, análise de vulnerabilidades, origem confiável
e, futuramente, política de assinatura.

## Por que o SBOM aparece como incompleto?

Porque ele descreve o pacote do Setup MNO e referências detectadas nos scripts.
Ele ainda não enumera cada biblioteca interna de cada container. Declarar essa
limitação evita uma falsa sensação de cobertura total.

## Hash SHA-256 é o mesmo que assinatura digital?

Não. O hash detecta alteração em relação ao manifesto recebido. Uma assinatura
independente também vincula a evidência a uma identidade criptográfica. A
primeira versão ainda não usa DSSE nem chave de assinatura.

## A feature muda containers ou atualiza imagens?

Não. Ela é somente leitura em runtime. Não executa pull, deploy, restart, DNS,
Cloudflare ou alteração de volumes.

## Todos os planos recebem os arquivos?

Sim, pois integridade do runtime é uma proteção básica. A Central do Mantenedor
e aprovações finais continuam exclusivas do PRO MASTER.
