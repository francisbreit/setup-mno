# Verificar supply chain no WSL2

Este roteiro valida a v7.30.0 sem editar arquivos da instalação.

## Antes de atualizar

1. Abra o Docker Desktop e aguarde o estado `Engine running`.
2. Confirme que a integração WSL está habilitada para a distribuição Ubuntu.
3. No Ubuntu, execute `docker info` e confirme que não há erro de conexão.
4. Registre o plano e o tipo de instalação exibidos pelo Setup MNO.

## Atualização

Execute o bootstrap oficial já utilizado pela instalação. Conclua a atualização
sem trocar domínio, túnel ou plano apenas para este teste.

## Gates de leitura

Como root no Ubuntu:

```bash
jq '{setupVersion,architecture,supplyChainSchemaVersion,supplyChainSignatureStatus,supplyChainImageReferences,supplyChainDigestPinnedImages,supplyChainUnresolvedReferences}' /root/SetupLowCodeMno/.control/release.json
find /root/SetupLowCodeMno/.control/supply-chain -maxdepth 1 -type f -printf '%f\n' | sort
jq '{schemaVersion,setupVersion,architecture,sbom,attestation,inventory}' /root/SetupLowCodeMno/.control/supply-chain/manifest.json
jq '{bomFormat,specVersion,version,components:(.components|length),compositions}' /root/SetupLowCodeMno/.control/supply-chain/sbom.cdx.json
jq '{_type,predicateType,subjects:(.subject|length)}' /root/SetupLowCodeMno/.control/supply-chain/attestation.intoto.json
```

Resultado esperado: versão 7.30.0, arquitetura `amd64`, schema 1, CycloneDX 1.6,
dois subjects e componentes coerentes com o manifesto e status
`unsigned-sha256-bound`. A quantidade exata de imagens pode mudar quando os
scripts mudarem.

## Control Center

Abra o catálogo e procure a faixa `Supply chain validada`. Ela deve informar a
quantidade de referências, imagens por digest, expressões não resolvidas e que
a atestação ainda não possui assinatura independente.

## Teste negativo seguro

Não adultere `/root/SetupLowCodeMno`. O teste de adulteração é executado na
construção usando uma cópia temporária. No ambiente instalado, apenas confirme
que todos os quatro arquivos são regulares e não são links:

```bash
find /root/SetupLowCodeMno/.control/supply-chain -maxdepth 1 -type l -print
```

O comando não deve retornar nada.
