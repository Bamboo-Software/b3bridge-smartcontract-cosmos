// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import "@chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface ICustomCoin {
    function mint(address to, uint256 amount) external;

    function burn(address from, uint256 amount) external;

    function balanceOf(address account) external view returns (uint256);

    function owner() external view returns (address);

    function transferOwnership(address newOwner) external;

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);
}

contract B3BridgeDest is CCIPReceiver, Ownable, ReentrancyGuard {
    using ECDSA for bytes32;
    mapping(bytes32 => address) public tokenMapping;
    address public sourceBridge;
    uint64 public sourceChainSelector;

    address[] public validators;
    uint256 public threshold;
    address public immutable wTokenNative;
    mapping(bytes32 => mapping(address => bool)) public signatures;
    mapping(bytes32 => uint256) public signatureCount;
    mapping(bytes32 => MessageData) public messageData;
    mapping(bytes32 => bool) public processedMessages;
    mapping(address => uint256) public nonces;
    bytes32 public constant MESSAGE_TYPEHASH =
        keccak256(
            "Message(bytes user,uint256 amount,uint8 tokenType,address tokenAddr,uint256 nonce)"
        );
    bytes32 public domainSeparator;
    struct MessageData {
        bytes user;
        uint256 amount;
        uint8 tokenType;
        address tokenAddr;
        uint256 nonce;
    }
    event DebugTokenAddress(bytes32 tokenId, address tokenAddress);
    event MintTokenCCIP(
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
        address receiver,
        bytes32 tokenId,
        uint256 amount
    );
    event BurnTokenVL(
        address indexed sender,
        uint256 amount,
        address indexed sourceBridge,
        string tokenSymbol
    );
    event MintedTokenVL(bytes user, address token, uint256 amount);
    event DebugMsg(string message);
    event DebugFee(uint256 fee);
    event BurnTokenCCIP(
        bytes32 indexed messageId,
        address indexed user,
        bytes32 tokenId,
        uint256 amount
    );
    event ThresholdUpdated(uint256 newThreshold);
    event ValidatorAdded(address validator);
    event ValidatorRemoved(address validator);
    event SignatureSubmitted(
        bytes32 indexed messageHash,
        address indexed signer
    );
    event Executed(bytes32 indexed messageHash);

    constructor(
        address router,
        address _sourceBridge,
        uint64 _sourceChainSelector,
        address[] memory _validators,
        uint256 _threshold,
        address _wTokenNative
    ) CCIPReceiver(router) Ownable(msg.sender) {
        require(_validators.length > 0, "Validator list cannot be empty");
        require(
            _threshold > 0 && _threshold <= _validators.length,
            "Invalid threshold"
        );

        wTokenNative = _wTokenNative;

        sourceBridge = _sourceBridge;
        sourceChainSelector = _sourceChainSelector;

        validators = _validators;
        threshold = _threshold;
        domainSeparator = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("B3BridgeDest")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    // Hàm thêm hoặc cập nhật mapping token
    function setTokenMapping(
        bytes32 tokenId,
        address tokenAddress
    ) external onlyOwner {
        require(tokenAddress != address(0), "Invalid token address");
        tokenMapping[tokenId] = tokenAddress;
    }

    function getFeeCCIP(
        uint256 amount,
        bytes32 tokenId
    ) external view returns (uint256) {
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(sourceBridge),
            data: abi.encode(msg.sender, tokenId, amount),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                Client.GenericExtraArgsV2({
                    gasLimit: 300_000,
                    allowOutOfOrderExecution: true
                })
            ),
            feeToken: address(0)
        });

        return IRouterClient(getRouter()).getFee(sourceChainSelector, message);
    }

    function _ccipReceive(
        Client.Any2EVMMessage memory message
    ) internal override {
        // Kiểm tra chain nguồn
        require(
            message.sourceChainSelector == sourceChainSelector,
            "Invalid source chain"
        );

        // Decode dữ liệu từ message: (receiver, tokenId, amount)
        (address receiver, bytes32 tokenId, uint256 amount) = abi.decode(
            message.data,
            (address, bytes32, uint256)
        );

        address tokenAddress = tokenMapping[tokenId];
        require(tokenAddress != address(0), "Unsupported token");

        // Mint
        ICustomCoin(tokenAddress).mint(receiver, amount);

        emit MintTokenCCIP(
            message.messageId,
            message.sourceChainSelector,
            receiver,
            tokenId,
            amount
        );
    }

    function burnTokenCCIP(
        bytes32 tokenId,
        uint256 amount
    ) external payable returns (bytes32 messageId) {
        require(amount > 0, "Amount must be greater than 0");

        address tokenAddress = tokenMapping[tokenId];
        emit DebugTokenAddress(tokenId, tokenAddress);
        require(tokenAddress != address(0), "Unsupported token");

        emit DebugMsg("Start burnTokenCCIP");

        uint256 allowance = ICustomCoin(tokenAddress).allowance(
            msg.sender,
            address(this)
        );
        require(allowance >= amount, "Insufficient allowance");

        uint256 userBalance = ICustomCoin(tokenAddress).balanceOf(msg.sender);
        require(userBalance >= amount, "Insufficient user balance");
        emit DebugMsg("User balance OK");

        bool success = ICustomCoin(tokenAddress).transferFrom(
            msg.sender,
            address(this),
            amount
        );
        require(success, "transferFrom failed");
        emit DebugMsg("transferFrom success");

        uint256 contractBalance = ICustomCoin(tokenAddress).balanceOf(
            address(this)
        );
        require(
            contractBalance >= amount,
            "Contract balance too low after transferFrom"
        );

        // Burn token
        ICustomCoin(tokenAddress).burn(address(this), amount);
        emit DebugMsg("Token burned");

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(sourceBridge),
            data: abi.encode(msg.sender, tokenId, amount),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                Client.GenericExtraArgsV2({
                    gasLimit: 300_000,
                    allowOutOfOrderExecution: true
                })
            ),
            feeToken: address(0)
        });

        IRouterClient router = IRouterClient(getRouter());
        uint256 fee = router.getFee(sourceChainSelector, message);
        emit DebugFee(fee);

        require(msg.value >= fee, "Insufficient fee sent");

        messageId = router.ccipSend{value: msg.value}(
            sourceChainSelector,
            message
        );

        emit BurnTokenCCIP(messageId, msg.sender, tokenId, amount);

        // Refund leftover fee nếu có
        if (msg.value > fee) {
            uint256 refund = msg.value - fee;
            (bool sent, ) = payable(msg.sender).call{value: refund}("");
            if (sent) {
                emit DebugMsg("Refund succeeded");
            } else {
                emit DebugMsg("Refund failed");
            }
        }

        emit DebugMsg("End burnTokenCCIP");
        return messageId;
    }

    function burnTokenVL(uint256 amount) external payable {
        require(amount > 0, "Amount must be greater than 0");

        uint256 allowance = ICustomCoin(wTokenNative).allowance(
            msg.sender,
            address(this)
        );
        require(allowance >= amount, "Insufficient allowance");

        uint256 userBalance = ICustomCoin(wTokenNative).balanceOf(msg.sender);
        require(userBalance >= amount, "Insufficient user balance");
        emit DebugMsg("User balance OK");

        bool success = ICustomCoin(wTokenNative).transferFrom(
            msg.sender,
            address(this),
            amount
        );
        require(success, "transferFrom failed");
        emit DebugMsg("transferFrom success");

        uint256 contractBalance = ICustomCoin(wTokenNative).balanceOf(
            address(this)
        );
        require(
            contractBalance >= amount,
            "Contract balance too low after transferFrom"
        );

        // Burn token
        ICustomCoin(wTokenNative).burn(address(this), amount);
        emit DebugMsg("Token burned");
        emit BurnTokenVL(msg.sender, amount, sourceBridge, "wSEI");
    }

    function setThreshold(uint256 newThreshold) external onlyOwner {
        require(newThreshold > 0, "Threshold must be > 0");
        require(
            newThreshold <= validators.length,
            "Threshold exceeds validator count"
        );
        require(
            newThreshold >= (validators.length * 2 + 2) / 3,
            "Threshold too low"
        );

        threshold = newThreshold;
        emit ThresholdUpdated(newThreshold);
    }

    function _updateThreshold() internal {
        if (validators.length == 0) {
            threshold = 0;
        } else {
            threshold = (validators.length * 2 + 2) / 3;
        }
        emit ThresholdUpdated(threshold);
    }

    function _isValidator(address addr) internal view returns (bool) {
        for (uint256 i = 0; i < validators.length; i++) {
            if (validators[i] == addr) return true;
        }
        return false;
    }

    // Khi thêm validator thì update luôn threshold
    function addValidator(address validator) external onlyOwner {
        require(validator != address(0), "Invalid validator address");
        require(!_isValidator(validator), "Validator already exists");
        require(validators.length < type(uint256).max, "Validator list full");

        validators.push(validator);

        _updateThreshold();

        emit ValidatorAdded(validator);
    }

    function removeValidator(address validator) external onlyOwner {
        require(_isValidator(validator), "Validator not found");

        for (uint256 i = 0; i < validators.length; i++) {
            if (validators[i] == validator) {
                validators[i] = validators[validators.length - 1];
                validators.pop();

                _updateThreshold();
                emit ValidatorRemoved(validator);
                break;
            }
        }
    }

    function getValidatorCount() external view returns (uint256) {
        return validators.length;
    }

    function hashMessage(
        MessageData memory data
    ) internal view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    domainSeparator,
                    keccak256(
                        abi.encode(
                            MESSAGE_TYPEHASH,
                            keccak256(data.user),
                            data.amount,
                            data.tokenType,
                            data.tokenAddr,
                            data.nonce
                        )
                    )
                )
            );
    }

    function bytesToAddress(
        bytes memory b
    ) internal pure returns (address addr) {
        require(b.length >= 20, "Invalid user bytes");
        assembly {
            // Lấy 32 bytes từ b + 32 (bỏ qua phần length)
            // rồi shift phải 12 bytes (96 bits) để lấy đúng 20 bytes địa chỉ
            addr := div(mload(add(b, 32)), 0x1000000000000000000000000)
        }
    }

    function submitSignature(
        bytes32 messageHash,
        bytes memory signature,
        bytes memory user,
        uint256 amount,
        uint8 tokenType,
        address tokenAddr,
        uint256 nonce
    ) public {
        require(_isValidator(msg.sender), "Not validator");
        require(!signatures[messageHash][msg.sender], "Already signed");

        // Kiểm tra nonce không bị reuse theo user
        address userAddr = bytesToAddress(user);
        require(nonce == nonces[userAddr] + 1, "Invalid nonce");

        // Tạo message hash từ dữ liệu nhập, kiểm tra trùng với messageHash
        MessageData memory data = MessageData(
            user,
            amount,
            tokenType,
            tokenAddr,
            nonce
        );
        bytes32 calcHash = hashMessage(data);
        require(calcHash == messageHash, "Invalid message hash");

        // Xác thực chữ ký theo chuẩn eth-signed-message
        require(
            _verifySignature(messageHash, signature, msg.sender),
            "Invalid signature"
        );

        if (signatureCount[messageHash] == 0) {
            // Chữ ký đầu tiên, lưu dữ liệu message
            require(user.length >= 20, "Invalid user address length");
            require(amount > 0, "Amount must be > 0");

            if (tokenType == 1) {
                require(tokenAddr != address(0), "Invalid token address");
            } else if (tokenType != 0) {
                revert("Unsupported token type");
            }

            messageData[messageHash] = data;
        } else {
            // Đã có chữ ký trước đó → kiểm tra dữ liệu khớp
            MessageData memory stored = messageData[messageHash];
            require(
                stored.amount == amount &&
                    stored.tokenType == tokenType &&
                    stored.tokenAddr == tokenAddr &&
                    stored.nonce == nonce &&
                    keccak256(stored.user) == keccak256(user),
                "Data mismatch"
            );
        }

        // Đánh dấu validator đã ký, tăng số chữ ký
        signatures[messageHash][msg.sender] = true;
        signatureCount[messageHash] += 1;

        emit SignatureSubmitted(messageHash, msg.sender);

        // Nếu đủ threshold → thực thi hành động
        if (signatureCount[messageHash] >= threshold) {
            // Cập nhật nonce cho user
            nonces[userAddr] = nonce;
            _execute(messageHash);
        }
    }

    function _execute(bytes32 messageHash) internal {
        require(!processedMessages[messageHash], "Message already processed");
        MessageData memory data = messageData[messageHash];
        require(data.amount > 0, "Invalid amount");
        require(data.user.length >= 20, "Invalid user address length");
        address userAddress = address(uint160(bytes20(data.user)));
        require(userAddress != address(0), "Invalid user address");

        processedMessages[messageHash] = true;

        require(data.tokenAddr != address(0), "Invalid token address");
        ICustomCoin(data.tokenAddr).mint(userAddress, data.amount);
        emit MintedTokenVL(data.user, data.tokenAddr, data.amount);

        // Dọn dẹp dữ liệu để tránh tái xử lý
        delete messageData[messageHash];
        delete signatureCount[messageHash];
        for (uint256 i = 0; i < validators.length; i++) {
            delete signatures[messageHash][validators[i]];
        }

        emit Executed(messageHash);
    }

    function _verifySignature(
        bytes32 messageHash,
        bytes memory signature,
        address signer
    ) internal pure returns (bool) {
        // bytes32 ethSignedMessageHash = ECDSA.toEthSignedMessageHash(messageHash);
        return ECDSA.recover(messageHash, signature) == signer;
    }

    function _splitSignature(
        bytes memory sig
    ) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(sig.length == 65, "Invalid signature length");
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }

    function transferTokenOwnership(
        address newOwner,
        bytes32 tokenId
    ) public virtual onlyOwner {
        require(newOwner != address(0), "New owner is zero address");

        address tokenAddress = tokenMapping[tokenId];
        require(tokenAddress != address(0), "Unsupported token");

        require(
            ICustomCoin(tokenAddress).owner() == address(this),
            "Bridge is not token owner"
        );

        ICustomCoin(tokenAddress).transferOwnership(newOwner);
    }

    function withdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw");
        payable(owner()).transfer(balance);
    }

    // Hàm để nhận native token (nếu cần)
    receive() external payable {}

    function updateSourceBridge(
        address _sourceBridge,
        uint64 _sourceChainSelector
    ) external onlyOwner {
        sourceBridge = _sourceBridge;
        sourceChainSelector = _sourceChainSelector;
    }
}
