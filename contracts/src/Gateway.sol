// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2023 Snowfork <hello@snowfork.com>
pragma solidity 0.8.23;

import {MerkleProof} from "openzeppelin/utils/cryptography/MerkleProof.sol";
import {Verification} from "./Verification.sol";

import {Assets} from "./Assets.sol";
import {AgentExecutor} from "./AgentExecutor.sol";
import {Agent} from "./Agent.sol";
import {
    Channel,
    ChannelID,
    InboundMessage,
    OperatingMode,
    ParaID,
    Command,
    MultiAddress,
    Ticket,
    Costs,
    TokenInfo,
    AgentExecuteCommand
} from "./Types.sol";
import {IGateway} from "./interfaces/IGateway.sol";
import {IInitializable} from "./interfaces/IInitializable.sol";
import {ERC1967} from "./utils/ERC1967.sol";
import {Address} from "./utils/Address.sol";
import {SafeNativeTransfer} from "./utils/SafeTransfer.sol";
import {Call} from "./utils/Call.sol";
import {Math} from "./utils/Math.sol";
import {ScaleCodec} from "./utils/ScaleCodec.sol";

import {
    UpgradeParams,
    CreateAgentParams,
    AgentExecuteParams,
    CreateChannelParams,
    UpdateChannelParams,
    SetOperatingModeParams,
    TransferNativeFromAgentParams,
    SetTokenTransferFeesParams,
    SetPricingParametersParams
} from "./Params.sol";

import {CoreStorage} from "./storage/CoreStorage.sol";
import {PricingStorage} from "./storage/PricingStorage.sol";
import {AssetsStorage} from "./storage/AssetsStorage.sol";

import {UD60x18, ud60x18, convert} from "prb/math/src/UD60x18.sol";

contract Gateway is IGateway, IInitializable {
    using Address for address;
    using SafeNativeTransfer for address payable;

    // ChannelIDs
    ChannelID internal constant PRIMARY_GOVERNANCE_CHANNEL_ID = ChannelID.wrap(bytes32(uint256(1)));
    ChannelID internal constant SECONDARY_GOVERNANCE_CHANNEL_ID = ChannelID.wrap(bytes32(uint256(2)));

    // Gas used for:
    // 1. Mapping a command id to an implementation function
    // 2. Calling implementation function
    uint256 DISPATCH_OVERHEAD_GAS = 10_000;

    error InvalidProof();
    error InvalidNonce();
    error NotEnoughGas();
    error Unauthorized();
    error AgentAlreadyCreated();
    error AgentDoesNotExist();
    error ChannelAlreadyCreated();
    error ChannelDoesNotExist();
    error InvalidChannelUpdate();
    error AgentExecutionFailed(bytes returndata);
    error InvalidAgentExecutionPayload();
    error InvalidCodeHash();
    error InvalidConstructorParams();
    error AlreadyInitialized();

    // handler functions are privileged
    modifier onlySelf() {
        if (msg.sender != address(this)) {
            revert Unauthorized();
        }
        _;
    }

    // handler functions are privileged from agent only
    modifier onlyAgent(bytes32 agentID) {
        bytes32 _agentID = _ensureAgentAddress(msg.sender);
        if (_agentID != agentID) {
            revert Unauthorized();
        }
        _;
    }

    /// @dev Submit a message from Polkadot for verification and dispatch
    /// @param message A message produced by the OutboundQueue pallet on BridgeHub
    /// @param leafProof A message proof used to verify that the message is in the merkle tree committed by the OutboundQueue pallet
    /// @param headerProof A proof that the commitment is included in parachain header that was finalized by BEEFY.
    function submitV1(
        InboundMessage calldata message,
        bytes32[] calldata leafProof,
        Verification.Proof calldata headerProof
    ) external {
        uint256 startGas = gasleft();

        Channel storage channel = _ensureChannel(message.channelID);

        // Ensure this message is not being replayed
        if (message.nonce != channel.inboundNonce + 1) {
            revert InvalidNonce();
        }

        // Increment nonce for origin.
        // This also prevents the re-entrancy case in which a malicious party tries to re-enter by calling `submitInbound`
        // again with the same (message, leafProof, headerProof) arguments.
        channel.inboundNonce++;

        // Produce the commitment (message root) by applying the leaf proof to the message leaf
        bytes32 leafHash = keccak256(abi.encode(message));
        bytes32 commitment = MerkleProof.processProof(leafProof, leafHash);

        // Verify that the commitment is included in a parachain header finalized by BEEFY.
        if (!_verifyCommitment(commitment, headerProof)) {
            revert InvalidProof();
        }

        // Make sure relayers provide enough gas so that inner message dispatch
        // does not run out of gas.
        uint256 maxDispatchGas = message.maxDispatchGas;
        if (gasleft() < maxDispatchGas + DISPATCH_OVERHEAD_GAS) {
            revert NotEnoughGas();
        }

        bool success = true;

        // Dispatch message to a handler
        if (message.command == Command.AgentExecute) {
            try Gateway(this).agentExecute{gas: maxDispatchGas}(message.params) {}
            catch {
                success = false;
            }
        } else if (message.command == Command.CreateAgent) {
            try Gateway(this).createAgent{gas: maxDispatchGas}(message.params) {}
            catch {
                success = false;
            }
        } else if (message.command == Command.CreateChannel) {
            try Gateway(this).createChannel{gas: maxDispatchGas}(message.params) {}
            catch {
                success = false;
            }
        } else if (message.command == Command.UpdateChannel) {
            try Gateway(this).updateChannel{gas: maxDispatchGas}(message.params) {}
            catch {
                success = false;
            }
        } else if (message.command == Command.SetOperatingMode) {
            try Gateway(this).setOperatingMode{gas: maxDispatchGas}(message.params) {}
            catch {
                success = false;
            }
        } else if (message.command == Command.TransferNativeFromAgent) {
            try Gateway(this).transferNativeFromAgent{gas: maxDispatchGas}(message.params) {}
            catch {
                success = false;
            }
        } else if (message.command == Command.Upgrade) {
            try Gateway(this).upgrade{gas: maxDispatchGas}(message.params) {}
            catch {
                success = false;
            }
        } else if (message.command == Command.SetTokenTransferFees) {
            try Gateway(this).setTokenTransferFees{gas: maxDispatchGas}(message.params) {}
            catch {
                success = false;
            }
        } else if (message.command == Command.SetPricingParameters) {
            try Gateway(this).setPricingParameters{gas: maxDispatchGas}(message.params) {}
            catch {
                success = false;
            }
        }

        // Calculate a gas refund, capped to protect against huge spikes in `tx.gasprice`
        // that could drain funds unnecessarily. During these spikes, relayers should back off.
        uint256 gasUsed = _transactionBaseGas() + (startGas - gasleft());
        uint256 refund = gasUsed * Math.min(tx.gasprice, message.maxFeePerGas);

        // Add the reward to the refund amount. If the sum is more than the funds available
        // in the channel agent, then reduce the total amount
        uint256 amount = Math.min(refund + message.reward, address(channel.agent).balance);

        // Do the payment if there funds available in the agent
        if (amount > _dustThreshold()) {
            _transferNativeFromAgent(channel.agent, payable(msg.sender), amount);
        }

        emit IGateway.InboundMessageDispatched(message.channelID, message.nonce, message.id, success);
    }

    /**
     * Getters
     */
    function operatingMode() external view returns (OperatingMode) {
        return CoreStorage.layout().mode;
    }

    function channelOperatingModeOf(ChannelID channelID) external view returns (OperatingMode) {
        Channel storage ch = _ensureChannel(channelID);
        return ch.mode;
    }

    function channelNoncesOf(ChannelID channelID) external view returns (uint64, uint64) {
        Channel storage ch = _ensureChannel(channelID);
        return (ch.inboundNonce, ch.outboundNonce);
    }

    function agentOf(bytes32 agentID) external view returns (address) {
        return _ensureAgent(agentID);
    }

    function pricingParameters() external view returns (UD60x18, uint128) {
        PricingStorage.Layout storage pricing = PricingStorage.layout();
        return (pricing.exchangeRate, pricing.deliveryCost);
    }

    function implementation() public view returns (address) {
        return ERC1967.load();
    }

    /**
     * Handlers
     */

    // Execute code within an agent
    function agentExecute(bytes calldata data) external onlySelf {
        AgentExecuteParams memory params = abi.decode(data, (AgentExecuteParams));

        address agent = _ensureAgent(params.agentID);

        if (params.payload.length == 0) {
            revert InvalidAgentExecutionPayload();
        }

        (AgentExecuteCommand command, bytes memory payload) = abi.decode(params.payload, (AgentExecuteCommand, bytes));

        bytes memory call = abi.encodeCall(AgentExecutor.execute, (params.agentID, command, payload));

        address executor = CoreStorage.layout().agentExecutor;
        (bool success, bytes memory returndata) = Agent(payable(agent)).invoke(executor, call);
        if (!success) {
            revert AgentExecutionFailed(returndata);
        }

        if (command == AgentExecuteCommand.RegisterToken) {
            (bytes memory result) = abi.decode(returndata, (bytes));
            (bytes32 tokenID, address token) = abi.decode(result, (bytes32, address));
            Assets.registerTokenByID(tokenID, token, params.agentID);
            emit IGateway.ForeignTokenRegistered(tokenID, params.agentID, token);
        }
    }

    /// @dev Create an agent for a consensus system on Polkadot
    function createAgent(bytes calldata data) external onlySelf {
        CoreStorage.Layout storage $ = CoreStorage.layout();

        CreateAgentParams memory params = abi.decode(data, (CreateAgentParams));

        // Ensure we don't overwrite an existing agent
        if (address($.agents[params.agentID]) != address(0)) {
            revert AgentAlreadyCreated();
        }

        address payable agent = payable(new Agent(params.agentID));
        $.agents[params.agentID] = agent;

        emit AgentCreated(params.agentID, agent);
    }

    /// @dev Create a messaging channel for a Polkadot parachain
    function createChannel(bytes calldata data) external onlySelf {
        CoreStorage.Layout storage $ = CoreStorage.layout();

        CreateChannelParams memory params = abi.decode(data, (CreateChannelParams));

        // Ensure that specified agent actually exists
        address agent = _ensureAgent(params.agentID);

        // Ensure channel has not already been created
        Channel storage ch = $.channels[params.channelID];
        if (address(ch.agent) != address(0)) {
            revert ChannelAlreadyCreated();
        }

        ch.mode = params.mode;
        ch.agent = agent;
        ch.inboundNonce = 0;
        ch.outboundNonce = 0;

        emit ChannelCreated(params.channelID);
    }

    /// @dev Update the configuration for a channel
    function updateChannel(bytes calldata data) external onlySelf {
        UpdateChannelParams memory params = abi.decode(data, (UpdateChannelParams));

        Channel storage ch = _ensureChannel(params.channelID);

        // Extra sanity checks when updating the primary governance channel, which should never be halted.
        if (params.channelID == PRIMARY_GOVERNANCE_CHANNEL_ID && (params.mode != OperatingMode.Normal)) {
            revert InvalidChannelUpdate();
        }

        ch.mode = params.mode;
        emit ChannelUpdated(params.channelID);
    }

    /// @dev Perform an upgrade of the gateway
    function upgrade(bytes calldata data) external onlySelf {
        UpgradeParams memory params = abi.decode(data, (UpgradeParams));

        // Verify that the implementation is actually a contract
        if (!params.impl.isContract()) {
            revert InvalidCodeHash();
        }

        // As a sanity check, ensure that the codehash of implementation contract
        // matches the codehash in the upgrade proposal
        if (params.impl.codehash != params.implCodeHash) {
            revert InvalidCodeHash();
        }

        // Update the proxy with the address of the new implementation
        ERC1967.store(params.impl);

        // Apply the initialization function of the implementation only if params were provided
        if (params.initParams.length > 0) {
            (bool success, bytes memory returndata) =
                params.impl.delegatecall(abi.encodeCall(IInitializable.initialize, params.initParams));
            Call.verifyResult(success, returndata);
        }

        emit Upgraded(params.impl);
    }

    // @dev Set the operating mode of the gateway
    function setOperatingMode(bytes calldata data) external onlySelf {
        CoreStorage.Layout storage $ = CoreStorage.layout();
        SetOperatingModeParams memory params = abi.decode(data, (SetOperatingModeParams));
        $.mode = params.mode;
        emit OperatingModeChanged(params.mode);
    }

    // @dev Transfer funds from an agent to a recipient account
    function transferNativeFromAgent(bytes calldata data) external onlySelf {
        TransferNativeFromAgentParams memory params = abi.decode(data, (TransferNativeFromAgentParams));

        address agent = _ensureAgent(params.agentID);

        _transferNativeFromAgent(agent, payable(params.recipient), params.amount);
        emit AgentFundsWithdrawn(params.agentID, params.recipient, params.amount);
    }

    // @dev Set token fees of the gateway
    function setTokenTransferFees(bytes calldata data) external onlySelf {
        AssetsStorage.Layout storage $ = AssetsStorage.layout();
        SetTokenTransferFeesParams memory params = abi.decode(data, (SetTokenTransferFeesParams));
        $.assetHubCreateAssetFee = params.assetHubCreateAssetFee;
        $.assetHubReserveTransferFee = params.assetHubReserveTransferFee;
        $.registerTokenFee = params.registerTokenFee;
        emit TokenTransferFeesChanged();
    }

    // @dev Set pricing params of the gateway
    function setPricingParameters(bytes calldata data) external onlySelf {
        PricingStorage.Layout storage pricing = PricingStorage.layout();
        SetPricingParametersParams memory params = abi.decode(data, (SetPricingParametersParams));
        pricing.exchangeRate = params.exchangeRate;
        pricing.deliveryCost = params.deliveryCost;
        pricing.multiplier = params.multiplier;
        emit PricingParametersChanged();
    }

    /**
     * Internal functions
     */

    // Best-effort attempt at estimating the base gas use of `submitInbound` transaction, outside the block of
    // code that is metered.
    // This includes:
    // * Cost paid for every transaction: 21000 gas
    // * Cost of calldata: Zero byte = 4 gas, Non-zero byte = 16 gas
    // * Cost of code inside submitInitial that is not metered: 14_698
    //
    // The major cost of calldata are the merkle proofs, which should dominate anything else (including the message payload)
    // Since the merkle proofs are hashes, they are much more likely to be composed of more non-zero bytes than zero bytes.
    //
    // Reference: Ethereum Yellow Paper
    function _transactionBaseGas() internal pure returns (uint256) {
        return 21_000 + 14_698 + (msg.data.length * 16);
    }

    // Verify that a message commitment is considered finalized by our BEEFY light client.
    function _verifyCommitment(bytes32 commitment, Verification.Proof calldata proof)
        internal
        view
        virtual
        returns (bool)
    {
        CoreStorage.Layout storage $ = CoreStorage.layout();
        address beefyClient = $.beefyClient;
        bytes4 bridgeHubParaIDEncoded = $.bridgeHubParaIDEncoded;
        return Verification.verifyCommitment(beefyClient, bridgeHubParaIDEncoded, commitment, proof);
    }

    /// @dev Ensure that the specified parachain has a channel allocated
    function _ensureChannel(ChannelID channelID) internal view returns (Channel storage ch) {
        ch = CoreStorage.layout().channels[channelID];
        // A channel always has an agent specified.
        if (ch.agent == address(0)) {
            revert ChannelDoesNotExist();
        }
    }

    /// @dev Ensure that the specified agentID has a corresponding contract
    function _ensureAgent(bytes32 agentID) internal view returns (address agent) {
        agent = CoreStorage.layout().agents[agentID];
        if (agent == address(0)) {
            revert AgentDoesNotExist();
        }
    }

    /// @dev Ensure that the specified address is an valid agent
    function _ensureAgentAddress(address agent) internal view returns (bytes32 agentID) {
        agentID = CoreStorage.layout().agentAddresses[agent];
        if (agentID == bytes32(0)) {
            revert AgentDoesNotExist();
        }
    }

    /// @dev Invoke some code within an agent
    function _invokeOnAgent(address agent, bytes memory data) internal returns (bytes memory) {
        address executor = CoreStorage.layout().agentExecutor;
        (bool success, bytes memory returndata) = (Agent(payable(agent)).invoke(executor, data));
        return Call.verifyResult(success, returndata);
    }

    /// @dev Transfer ether from an agent
    function _transferNativeFromAgent(address agent, address payable recipient, uint256 amount) internal {
        bytes memory call = abi.encodeCall(AgentExecutor.transferNative, (recipient, amount));
        _invokeOnAgent(agent, call);
    }

    /// @dev Define the dust threshold as the minimum cost to transfer ether between accounts
    function _dustThreshold() internal view returns (uint256) {
        return 21000 * tx.gasprice;
    }

    /**
     * Upgrades
     */

    // Initial configuration for bridge
    struct Config {
        /// @dev The beefy client
        address beefyClient;
        /// @dev The agent executor
        address agentExecutor;
        /// @dev The bridgehub ParaID
        ParaID bridgeHubParaID;
        /// @dev The bridgehub agentID
        bytes32 bridgeHubAgentID;
        /// @dev The decimals of relaychain token
        uint8 foreignTokenDecimals;
        /// @dev The operating mode
        OperatingMode mode;
        /// @dev The fee charged to users for submitting outbound messages (DOT)
        uint128 deliveryCost;
        /// @dev The ETH/DOT exchange rate
        UD60x18 exchangeRate;
        ParaID assetHubParaID;
        bytes32 assetHubAgentID;
        /// @dev The extra fee charged for registering tokens (DOT)
        uint128 assetHubCreateAssetFee;
        /// @dev The extra fee charged for sending tokens (DOT)
        uint128 assetHubReserveTransferFee;
        /// @dev extra fee to discourage spamming
        uint256 registerTokenFee;
        /// @dev Fee multiplier
        UD60x18 multiplier;
    }

    /// @dev Initialize storage in the gateway
    /// NOTE: This is not externally accessible as this function selector is overshadowed in the proxy
    function initialize(bytes calldata data) external virtual {
        // Prevent initialization of storage in implementation contract
        if (ERC1967.load() == address(0)) {
            revert Unauthorized();
        }

        CoreStorage.Layout storage core = CoreStorage.layout();

        if (core.channels[PRIMARY_GOVERNANCE_CHANNEL_ID].agent != address(0)) {
            revert AlreadyInitialized();
        }

        Config memory config = abi.decode(data, (Config));

        if (config.bridgeHubParaID == ParaID.wrap(0) || config.bridgeHubAgentID == 0) {
            revert InvalidConstructorParams();
        }

        core.beefyClient = config.beefyClient;
        core.agentExecutor = config.agentExecutor;
        core.bridgeHubParaID = config.bridgeHubParaID;
        core.bridgeHubParaIDEncoded = ScaleCodec.encodeU32(uint32(ParaID.unwrap(config.bridgeHubParaID)));
        core.bridgeHubAgentID = config.bridgeHubAgentID;
        core.foreignTokenDecimals = config.foreignTokenDecimals;

        core.mode = config.mode;

        // Initialize agent for BridgeHub
        address bridgeHubAgent = address(new Agent(config.bridgeHubAgentID));
        core.agents[config.bridgeHubAgentID] = bridgeHubAgent;
        core.agentAddresses[bridgeHubAgent] = config.bridgeHubAgentID;

        // Initialize channel for primary governance track
        core.channels[PRIMARY_GOVERNANCE_CHANNEL_ID] =
            Channel({mode: OperatingMode.Normal, agent: bridgeHubAgent, inboundNonce: 0, outboundNonce: 0});

        // Initialize channel for secondary governance track
        core.channels[SECONDARY_GOVERNANCE_CHANNEL_ID] =
            Channel({mode: OperatingMode.Normal, agent: bridgeHubAgent, inboundNonce: 0, outboundNonce: 0});

        // Initialize agent for for AssetHub
        address assetHubAgent = address(new Agent(config.assetHubAgentID));
        core.agents[config.assetHubAgentID] = assetHubAgent;
        core.agentAddresses[assetHubAgent] = config.assetHubAgentID;

        // Initialize channel for AssetHub
        core.channels[config.assetHubParaID.into()] =
            Channel({mode: OperatingMode.Normal, agent: assetHubAgent, inboundNonce: 0, outboundNonce: 0});

        // Initialize pricing storage
        PricingStorage.Layout storage pricing = PricingStorage.layout();
        pricing.exchangeRate = config.exchangeRate;
        pricing.deliveryCost = config.deliveryCost;
        pricing.multiplier = config.multiplier;

        // Initialize assets storage
        AssetsStorage.Layout storage assets = AssetsStorage.layout();

        assets.assetHubParaID = config.assetHubParaID;
        assets.assetHubAgent = assetHubAgent;
        assets.registerTokenFee = config.registerTokenFee;
        assets.assetHubCreateAssetFee = config.assetHubCreateAssetFee;
        assets.assetHubReserveTransferFee = config.assetHubReserveTransferFee;
    }
}
