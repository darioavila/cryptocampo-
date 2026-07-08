-include .env

.PHONY: install build test clean deploy-busd deploy-ccnft

install:
	forge install OpenZeppelin/openzeppelin-contracts@v4.5.0 --no-commit
	forge install foundry-rs/forge-std --no-commit

build:
	forge build

test:
	forge test -vvv

clean:
	forge clean

deploy-busd:
	forge script script/BUSD.s.sol:DeployBUSD \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast --verify \
		--etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv

deploy-ccnft:
	forge script script/CCNFT.s.sol:DeployCCNFT \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast --verify \
		--etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
