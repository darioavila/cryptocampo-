# CryptoCampo — Proyecto Final (CCNFT + BUSD)

Plataforma que **tokeniza bienes agrícolas mediante NFTs**. Cada NFT (`CCNFT`) representa una unidad de valor de un bien agrícola y se compra/vende/reclama usando un token ERC20 (`BUSD`) como medio de pago.

- **`BUSD`** — Token ERC20 (fungible). Moneda de pago. Se mintean 10.000.000 al desplegar.
- **`CCNFT`** — Colección ERC721Enumerable. Permite `buy`, `trade`, `putOnSale` y `claim`.

---

## 1. Requisitos previos

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (`forge`, `cast`, `anvil`)
- MetaMask con la red **Sepolia** agregada
- **ETH de Sepolia** (usá un faucet, ej. https://sepoliafaucet.com)
- API key de **Etherscan** (https://etherscan.io/myapikey)
- Un RPC de Sepolia (Infura / Alchemy)

Instalar Foundry:

```shell
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

---

## 2. Inicializar el proyecto e instalar dependencias

Si partís de cero:

```shell
forge init cryptocampo
cd cryptocampo
```

Instalar OpenZeppelin **v4.5.0** y forge-std:

```shell
forge install OpenZeppelin/openzeppelin-contracts@v4.5.0 --no-commit
forge install foundry-rs/forge-std --no-commit
```

(o simplemente `make install`)

---

## 3. Compilar

```shell
forge build      # o: make build
```

---

## 4. Testear

```shell
forge test -vvv  # o: make test
```

Los tests cubren todos los setters, los guards de `trade`, y los flujos completos de `buy`, `claim` y `trade`.

---

## 5. Configurar variables de entorno

Copiá `.env.example` a `.env` y completá tus datos:

```shell
cp .env.example .env
```

```dotenv
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/TU_API_KEY
PRIVATE_KEY=0xTU_CLAVE_PRIVADA        # NUNCA la subas a GitHub
ETHERSCAN_API_KEY=TU_API_KEY_ETHERSCAN
```

> ⚠️ `.env` está en `.gitignore`. No lo subas nunca al repositorio.

---

## 6. Desplegar y verificar en Sepolia

```shell
make deploy-busd     # despliega y verifica BUSD
make deploy-ccnft    # despliega y verifica CCNFT
```

Anotá las **direcciones** que imprime cada script.

---

## 7. Importar el token BUSD a MetaMask

MetaMask → *Importar tokens* → pegá la **dirección del contrato BUSD** desplegado. Vas a ver tu balance de 10.000.000 BUSD.

---

## 8. Aprobar (`approve`) el contrato CCNFT

Antes de comprar, el contrato CCNFT tiene que tener permiso para mover tus BUSD.

Desde Etherscan (pestaña *Write Contract* del **BUSD**) ejecutá `approve`:

- `spender`: **dirección del contrato CCNFT**
- `value`: `10000000000000000000000000` (los 10M con 18 decimales)

---

## 9. Setear las funciones que condicionan a `buy`

En Etherscan, pestaña *Write Contract* del **CCNFT** (conectá tu wallet, tenés que ser el owner). Todas estas deben estar seteadas antes del `buy`:

| Función | Valor de ejemplo | Para qué |
|---|---|---|
| `setFundsCollector` | tu dirección | recibe el pago de las ventas |
| `setFeesCollector` | tu dirección | recibe las comisiones |
| `setFundsToken` | dirección del **BUSD** | define el ERC20 de pago |
| `setCanBuy` | `true` | habilita la compra |
| `setMaxBatchCount` | `10` | máx. NFTs por operación |
| `setBuyFee` | `100` | comisión 1% (base 10000) |
| `setMaxValueToRaise` | `100000000000000000000000` | tope a recaudar (100.000) |
| `addValidValues` | `1000000000000000000` | permite NFTs de valor 1 BUSD |

> Los valores van en **wei** (18 decimales). `1 BUSD = 1000000000000000000`.

---

## 10. Ejecutar `buy`

En *Write Contract* del **CCNFT**:

- `value`: `1000000000000000000`
- `amount`: `1`

La transacción mintea el NFT, transfiere el pago al `fundsCollector` y la comisión al `feesCollector`.

Importalo en MetaMask (*Importar NFT* → dirección del CCNFT + tokenId `0`).

---

## Otras funciones

- **`putOnSale(tokenId, price)`** — pone tu NFT en venta (requiere `canTrade = true`).
- **`trade(tokenId)`** — otro usuario compra un NFT en venta; paga el precio al vendedor y la comisión (`tradeFee`) al `feesCollector`.
- **`claim(uint256[] tokenIds)`** — quema tus NFTs y recibís su valor + `profitToPay` en BUSD.

> Las transferencias directas (`transferFrom` / `safeTransferFrom`) están **deshabilitadas** a propósito: la única forma de mover un NFT es vía `trade`.

---

## Estructura del proyecto