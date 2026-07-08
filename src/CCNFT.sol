// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC721} from "lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "lib/openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {Counters} from "lib/openzeppelin-contracts/contracts/utils/Counters.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

contract CCNFT is ERC721Enumerable, Ownable, ReentrancyGuard {
    // ============================================================
    // EVENTOS
    // ============================================================

    // Compra de NFTs.
    event Buy(address indexed buyer, uint256 indexed tokenId, uint256 value);

    // Reclamo (claim) de un NFT: el usuario quema el NFT y recibe su valor en tokens ERC20.
    event Claim(address indexed claimer, uint256 indexed tokenId);

    // Transferencia (venta) de un NFT de un usuario a otro.
    event Trade(
        address indexed buyer,
        address indexed seller,
        uint256 indexed tokenId,
        uint256 value
    );

    // Puesta en venta de un NFT.
    event PutOnSale(uint256 indexed tokenId, uint256 price);

    // ============================================================
    // ESTRUCTURAS
    // ============================================================

    // Estado de venta de un NFT.
    struct TokenSale {
        bool onSale; // Indica si el NFT está en venta.
        uint256 price; // Precio del NFT si está en venta.
    }

    // ============================================================
    // VARIABLES DE ESTADO
    // ============================================================

    using Counters for Counters.Counter;

    // Contador para asignar IDs únicos a cada NFT.
    Counters.Counter private tokenIdTracker;

    // Valor (respaldo) asociado a cada tokenId.
    mapping(uint256 => uint256) public values;

    // Valores permitidos para los NFTs.
    mapping(uint256 => bool) public validValues;

    // Estado de venta de cada NFT.
    mapping(uint256 => TokenSale) public tokensOnSale;

    // Lista de los IDs de NFTs actualmente en venta.
    uint256[] public listTokensOnSale;

    address public fundsCollector; // Recolector de fondos por las ventas.
    address public feesCollector; // Recolector de tarifas de transacción.

    bool public canBuy; // Habilita/deshabilita la compra.
    bool public canClaim; // Habilita/deshabilita el reclamo.
    bool public canTrade; // Habilita/deshabilita el intercambio.

    uint256 public totalValue; // Valor total acumulado en circulación.
    uint256 public maxValueToRaise; // Valor máximo a recaudar.

    uint16 public buyFee; // Tarifa de compra (base 10000 = 100%).
    uint16 public tradeFee; // Tarifa de intercambio (base 10000 = 100%).

    uint16 public maxBatchCount; // Máximo de NFTs por operación.

    uint32 public profitToPay; // Porcentaje adicional a pagar en los reclamos.

    IERC20 public fundsToken; // Token ERC20 usado como medio de pago.

    // ============================================================
    // CONSTRUCTOR
    // ============================================================

    constructor() ERC721("CryptoCampo NFT", "CCNFT") {}

    // ============================================================
    // PUBLIC FUNCTIONS
    // ============================================================

    // Compra de NFTs.
    // value: valor de cada NFT que se compra.
    // amount: cantidad de NFTs a comprar.
    function buy(uint256 value, uint256 amount) external nonReentrant {
        require(canBuy, "Buy is not allowed");

        require(
            amount > 0 && amount <= maxBatchCount,
            "Invalid amount"
        );

        require(validValues[value], "Value not allowed");

        require(
            totalValue + (value * amount) <= maxValueToRaise,
            "Max value to raise reached"
        );

        totalValue += value * amount;

        for (uint256 i = 1; i <= amount; i++) {
            values[tokenIdTracker.current()] = value;
            _safeMint(_msgSender(), tokenIdTracker.current());
            emit Buy(_msgSender(), tokenIdTracker.current(), value);
            tokenIdTracker.increment();
        }

        // Transferencia del valor total de la compra al recolector de fondos.
        if (!fundsToken.transferFrom(_msgSender(), fundsCollector, value * amount)) {
            revert("Cannot send funds tokens");
        }

        // Transferencia de la tarifa de compra al recolector de tarifas.
        if (
            !fundsToken.transferFrom(
                _msgSender(),
                feesCollector,
                (value * amount * buyFee) / 10000
            )
        ) {
            revert("Cannot send fees tokens");
        }
    }

    // Reclamo de NFTs: quema los NFTs y devuelve su valor (más profitToPay) en tokens ERC20.
    function claim(uint256[] calldata listTokenId) external nonReentrant {
        require(canClaim, "Claim is not allowed");

        require(
            listTokenId.length > 0 && listTokenId.length <= maxBatchCount,
            "Invalid amount"
        );

        uint256 claimValue = 0;
        TokenSale storage tokenSale;

        for (uint256 i = 0; i < listTokenId.length; i++) {
            require(_exists(listTokenId[i]), "Token does not exist");

            require(
                _msgSender() == ownerOf(listTokenId[i]),
                "Only owner can Claim"
            );

            claimValue += values[listTokenId[i]];
            values[listTokenId[i]] = 0;

            tokenSale = tokensOnSale[listTokenId[i]];
            tokenSale.onSale = false;
            tokenSale.price = 0;

            removeFromArray(listTokensOnSale, listTokenId[i]);
            _burn(listTokenId[i]);
            emit Claim(_msgSender(), listTokenId[i]);
        }

        totalValue -= claimValue;

        // Transferencia desde fundsCollector al reclamante: valor + ganancia.
        if (
            !fundsToken.transferFrom(
                fundsCollector,
                _msgSender(),
                claimValue + ((claimValue * profitToPay) / 10000)
            )
        ) {
            revert("cannot send funds");
        }
    }

    // Compra de un NFT que está en venta.
    function trade(uint256 tokenId) external nonReentrant {
        require(canTrade, "Trade is not allowed");
        require(_exists(tokenId), "Token does not exist");
        require(ownerOf(tokenId) != _msgSender(), "Buyer is the Seller");

        TokenSale storage tokenSale = tokensOnSale[tokenId];
        require(tokenSale.onSale, "Token not On Sale");

        address seller = ownerOf(tokenId);
        uint256 price = tokenSale.price;

        // Transferencia del precio de venta del comprador al vendedor.
        if (!fundsToken.transferFrom(_msgSender(), seller, price)) {
            revert("Cannot send funds to seller");
        }

        // Transferencia de la tarifa de intercambio del comprador al feesCollector.
        if (
            !fundsToken.transferFrom(
                _msgSender(),
                feesCollector,
                (price * tradeFee) / 10000
            )
        ) {
            revert("Cannot send fees to feesCollector");
        }

        emit Trade(_msgSender(), seller, tokenId, price);

        _safeTransfer(seller, _msgSender(), tokenId, "");

        tokenSale.onSale = false;
        tokenSale.price = 0;
        removeFromArray(listTokensOnSale, tokenId);
    }

    // Poner un NFT en venta.
    function putOnSale(uint256 tokenId, uint256 price) external {
        require(canTrade, "Trade is not allowed");
        require(_exists(tokenId), "Token does not exist");
        require(ownerOf(tokenId) == _msgSender(), "Only owner can put on sale");

        TokenSale storage tokenSale = tokensOnSale[tokenId];
        tokenSale.onSale = true;
        tokenSale.price = price;

        addToArray(listTokensOnSale, tokenId);

        emit PutOnSale(tokenId, price);
    }

    // ============================================================
    // SETTERS
    // ============================================================

    function setFundsToken(address token) external onlyOwner {
        require(token != address(0), "Invalid address");
        fundsToken = IERC20(token);
    }

    function setFundsCollector(address _address) external onlyOwner {
        require(_address != address(0), "Invalid address");
        fundsCollector = _address;
    }

    function setFeesCollector(address _address) external onlyOwner {
        require(_address != address(0), "Invalid address");
        feesCollector = _address;
    }

    function setProfitToPay(uint32 _profitToPay) external onlyOwner {
        profitToPay = _profitToPay;
    }

    function setCanBuy(bool _canBuy) external onlyOwner {
        canBuy = _canBuy;
    }

    function setCanClaim(bool _canClaim) external onlyOwner {
        canClaim = _canClaim;
    }

    function setCanTrade(bool _canTrade) external onlyOwner {
        canTrade = _canTrade;
    }

    function setMaxValueToRaise(uint256 _maxValueToRaise) external onlyOwner {
        maxValueToRaise = _maxValueToRaise;
    }

    function addValidValues(uint256 value) external onlyOwner {
        validValues[value] = true;
    }

    function setMaxBatchCount(uint16 _maxBatchCount) external onlyOwner {
        maxBatchCount = _maxBatchCount;
    }

    function setBuyFee(uint16 _buyFee) external onlyOwner {
        buyFee = _buyFee;
    }

    function setTradeFee(uint16 _tradeFee) external onlyOwner {
        tradeFee = _tradeFee;
    }

    // ============================================================
    // ARRAYS
    // ============================================================

    // Agrega un valor al array evitando duplicados.
    function addToArray(uint256[] storage list, uint256 value) private {
        uint256 index = find(list, value);
        if (index == list.length) {
            list.push(value);
        }
    }

    // Elimina un valor del array (swap con el último y pop).
    function removeFromArray(uint256[] storage list, uint256 value) private {
        uint256 index = find(list, value);
        if (index < list.length) {
            list[index] = list[list.length - 1];
            list.pop();
        }
    }

    // Busca un valor en el array. Retorna su índice, o la longitud si no existe.
    function find(uint256[] storage list, uint256 value)
        private
        view
        returns (uint256)
    {
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == value) {
                return i;
            }
        }
        return list.length;
    }

    // ============================================================
    // NOT SUPPORTED FUNCTIONS
    // ============================================================
    // Se deshabilitan las transferencias directas de NFTs: la única forma
    // de mover un NFT es a través de la función trade().

    function transferFrom(address, address, uint256)
        public
        pure
        override(ERC721, IERC721)
    {
        revert("Not Allowed");
    }

    function safeTransferFrom(address, address, uint256)
        public
        pure
        override(ERC721, IERC721)
    {
        revert("Not Allowed");
    }

    function safeTransferFrom(address, address, uint256, bytes memory)
        public
        pure
        override(ERC721, IERC721)
    {
        revert("Not Allowed");
    }

    // ============================================================
    // COMPLIANCE REQUERIDO POR SOLIDITY
    // ============================================================

    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        override(ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }
}
