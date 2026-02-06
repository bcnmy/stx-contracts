export FOUNDRY_PROFILE="via-ir"

# Spinner function
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    printf " "
    while kill -0 $pid 2>/dev/null; do
        local temp=${spinstr#?}
        printf "[%c]" "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b"
    done
    printf "   \b\b\b"
}

read -r -p "Do you want to rebuild Stx-contracts artifacts from your local sources? (y/n): " proceed
if [ $proceed = "y" ]; then
    ### BUILD ARTIFACTS ###
    printf "Building Stx-contracts artifacts "
    { (forge build 1> ./deploy-logs/build/forge-build.log 2> ./deploy-logs/build/forge-build-errors.log) } &
    spinner $!
    wait $!
    if [ $? -ne 0 ]; then
        printf "\nBuild failed\n See logs for more details\n"
        exit 1
    fi
    printf "\n"
    printf "Copying Stx-contracts artifacts\n"
    
    # StxValidator and submodules
    mkdir -p ./artifacts/stx-validator/StxValidator
    mkdir -p ./artifacts/stx-validator/submodules/NoStxModeVerifier
    mkdir -p ./artifacts/stx-validator/submodules/SimpleModeSubmodule
    mkdir -p ./artifacts/stx-validator/submodules/PermitSubmodule
    mkdir -p ./artifacts/stx-validator/submodules/TxSubmodule
    mkdir -p ./artifacts/stx-validator/submodules/SafeAccountSubmodule
    mkdir -p ./artifacts/stx-validator/submodules/EOAStatelessValidator
    mkdir -p ./artifacts/stx-validator/submodules/P256StatelessValidator
    # Other contracts
    mkdir -p ./artifacts/Nexus
    mkdir -p ./artifacts/NexusBootstrap
    mkdir -p ./artifacts/NexusAccountFactory
    mkdir -p ./artifacts/NexusProxy
    mkdir -p ./artifacts/ComposableExecutionModule
    mkdir -p ./artifacts/ComposableStorage
    mkdir -p ./artifacts/EtherForwarder
    mkdir -p ./artifacts/NodePaymasterFactory

    # StxValidator and submodules
    cp ../../out/StxValidator.sol/StxValidator.json ./artifacts/stx-validator/StxValidator/.
    cp ../../out/NoStxModeVerifier.sol/NoStxModeVerifier.json ./artifacts/stx-validator/submodules/NoStxModeVerifier/.
    cp ../../out/SimpleModeSubmodule.sol/SimpleModeSubmodule.json ./artifacts/stx-validator/submodules/SimpleModeSubmodule/.
    cp ../../out/PermitSubmodule.sol/PermitSubmodule.json ./artifacts/stx-validator/submodules/PermitSubmodule/.
    cp ../../out/TxSubmodule.sol/TxSubmodule.json ./artifacts/stx-validator/submodules/TxSubmodule/.
    cp ../../out/SafeAccountSubmodule.sol/SafeAccountSubmodule.json ./artifacts/stx-validator/submodules/SafeAccountSubmodule/.
    cp ../../out/EOAStatelessValidator.sol/EOAStatelessValidator.json ./artifacts/stx-validator/submodules/EOAStatelessValidator/.
    cp ../../out/P256StatelessValidator.sol/P256StatelessValidator.json ./artifacts/stx-validator/submodules/P256StatelessValidator/.
    # Other contracts
    cp ../../out/Nexus.sol/Nexus.json ./artifacts/Nexus/.
    cp ../../out/NexusBootstrap.sol/NexusBootstrap.json ./artifacts/NexusBootstrap/.
    cp ../../out/NexusAccountFactory.sol/NexusAccountFactory.json ./artifacts/NexusAccountFactory/.
    cp ../../out/NexusProxy.sol/NexusProxy.json ./artifacts/NexusProxy/.
    cp ../../out/ComposableExecutionModule.sol/ComposableExecutionModule.json ./artifacts/ComposableExecutionModule/.
    cp ../../out/ComposableStorage.sol/ComposableStorage.json ./artifacts/ComposableStorage/.
    cp ../../out/EtherForwarder.sol/EtherForwarder.json ./artifacts/EtherForwarder/.
    cp ../../out/NodePaymasterFactory.sol/NodePaymasterFactory.json ./artifacts/NodePaymasterFactory/.
    
    printf "Artifacts copied\n"

    ### CREATE VERIFICATION ARTIFACTS ###
    printf "Creating verification artifacts\n"
    # StxValidator and submodules
    forge verify-contract --show-standard-json-input $(cast address-zero) StxValidator > ./artifacts/stx-validator/StxValidator/verify.json
    forge verify-contract --show-standard-json-input $(cast address-zero) NoStxModeVerifier > ./artifacts/stx-validator/submodules/NoStxModeVerifier/verify.json
    forge verify-contract --show-standard-json-input $(cast address-zero) SimpleModeSubmodule > ./artifacts/stx-validator/submodules/SimpleModeSubmodule/verify.json
    forge verify-contract --show-standard-json-input $(cast address-zero) PermitSubmodule > ./artifacts/stx-validator/submodules/PermitSubmodule/verify.json
    forge verify-contract --show-standard-json-input $(cast address-zero) TxSubmodule > ./artifacts/stx-validator/submodules/TxSubmodule/verify.json
    forge verify-contract --show-standard-json-input $(cast address-zero) SafeAccountSubmodule > ./artifacts/stx-validator/submodules/SafeAccountSubmodule/verify.json
    forge verify-contract --show-standard-json-input $(cast address-zero) EOAStatelessValidator > ./artifacts/stx-validator/submodules/EOAStatelessValidator/verify.json
    forge verify-contract --show-standard-json-input $(cast address-zero) P256StatelessValidator > ./artifacts/stx-validator/submodules/P256StatelessValidator/verify.json
    # Other contracts
    forge verify-contract --show-standard-json-input $(cast address-zero) Nexus > ./artifacts/Nexus/verify.json
    forge verify-contract --show-standard-json-input $(cast address-zero) NexusBootstrap > ./artifacts/NexusBootstrap/verify.json
    forge verify-contract --show-standard-json-input $(cast address-zero) NexusAccountFactory > ./artifacts/NexusAccountFactory/verify.json
    forge verify-contract --show-standard-json-input $(cast address-zero) NexusProxy > ./artifacts/NexusProxy/verify.json
    forge verify-contract --show-standard-json-input $(cast address-zero) ComposableExecutionModule > ./artifacts/ComposableExecutionModule/verify.json
    forge verify-contract --show-standard-json-input $(cast address-zero) ComposableStorage > ./artifacts/ComposableStorage/verify.json
    forge verify-contract --show-standard-json-input $(cast address-zero) EtherForwarder > ./artifacts/EtherForwarder/verify.json
    forge verify-contract --show-standard-json-input $(cast address-zero) NodePaymasterFactory > ./artifacts/NodePaymasterFactory/verify.json
    
    printf "Artifacts created\n"
else 
    printf "Precompiled artifacts will be used\n"
fi