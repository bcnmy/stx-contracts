// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../../../../NexusTestBase.t.sol";

/// @title TestNexusFactory_SingleInitialization
/// @notice Specifies that an account can be initialized exactly once, including within the
/// transaction that deploys it.
///
/// NexusProxy's constructor sets the Initializable transient flag so that the proxy can run its
/// initialization. EIP-1153 transient storage keeps values for the duration of the transaction,
/// so the flag must be consumed by the initialization that uses it. Otherwise a further
/// initializeAccount() call in the same transaction would still satisfy requireInitializable()
/// and run a second bootstrap in the account's context.
contract TestNexusFactory_SingleInitialization is NexusTestBase {
    Vm.Wallet internal accountOwner;

    function setUp() public virtual override {
        init();
        accountOwner = newWallet("accountOwner");
    }

    function _ownerInitData() internal view returns (bytes memory) {
        BootstrapConfig[] memory validators =
            NexusBootstrapLib.createArrayConfig(address(VALIDATOR_MODULE), abi.encodePacked(accountOwner.addr));
        BootstrapConfig memory hook = NexusBootstrapLib.createSingleConfig(address(0), "");
        return abi.encode(address(BOOTSTRAPPER), abi.encodeCall(BOOTSTRAPPER.initNexusScoped, (validators, hook)));
    }

    /// A second initializeAccount() in the same transaction that deployed the account must
    /// revert, and the bootstrap it points at must not run.
    function test_SecondInitializationInSameTransaction_Reverts() public {
        address recipient = makeAddr("recipient");
        bytes memory ownerInit = _ownerInitData();
        bytes32 salt = keccak256("single-initialization");

        address payable account = FACTORY.computeAccountAddress(ownerInit, salt);

        // The account holds a balance at its counterfactual address before deployment.
        vm.deal(account, 10 ether);

        AlternateBootstrap alternate = new AlternateBootstrap();
        bytes memory secondInit =
            abi.encode(address(alternate), abi.encodeCall(AlternateBootstrap.forwardBalance, (recipient)));

        DeployAndInitializeCaller caller = new DeployAndInitializeCaller();
        vm.expectRevert(Initializable.NotInitializable.selector);
        caller.run(address(FACTORY), ownerInit, salt, account, secondInit);

        // The whole call reverted, so the alternate bootstrap never ran.
        assertEq(account.balance, 10 ether, "account balance should be unchanged");
        assertEq(recipient.balance, 0, "no balance should have been forwarded");
    }

    /// Deployment plus its own initialization must still succeed: the flag is set by the proxy
    /// constructor and consumed exactly once by that initialization.
    function test_DeploymentAndInitialization_Succeeds() public {
        bytes memory ownerInit = _ownerInitData();
        bytes32 salt = keccak256("single-initialization-happy-path");

        address payable account = FACTORY.createAccount(ownerInit, salt);

        assertTrue(account.code.length > 0, "account should be deployed");
        assertEq(IAccountConfig(account).accountId(), "biconomy.nexus.1.3.3", "unexpected account id");
        assertTrue(
            IModuleManager(account).isModuleInstalled(MODULE_TYPE_VALIDATOR, address(VALIDATOR_MODULE), ""),
            "configured validator should be installed"
        );
    }
}

/// Deploys an account and then calls initializeAccount() on it again, both in one transaction.
contract DeployAndInitializeCaller {
    function run(
        address factory,
        bytes calldata ownerInit,
        bytes32 salt,
        address account,
        bytes calldata secondInit
    )
        external
    {
        NexusAccountFactory(factory).createAccount(ownerInit, salt);
        INexus(account).initializeAccount(secondInit);
    }
}

/// A bootstrap that moves the account's balance, used to observe whether a second
/// initialization runs. It is delegatecalled from _initializeAccount.
contract AlternateBootstrap {
    function forwardBalance(address to) external {
        (bool ok,) = to.call{ value: address(this).balance }("");
        require(ok, "forward failed");
    }
}
