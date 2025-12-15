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
    
    mkdir -p ./artifacts/K1MeeValidator
    mkdir -p ./artifacts/Nexus
    mkdir -p ./artifacts/NexusBootstrap
    mkdir -p ./artifacts/NexusAccountFactory
    mkdir -p ./artifacts/NexusProxy
    mkdir -p ./artifacts/ComposableExecutionModule
    mkdir -p ./artifacts/ComposableStorage
    mkdir -p ./artifacts/EtherForwarder
    mkdir -p ./artifacts/NodePaymasterFactory
    
    cp ../../out/K1MeeValidator.sol/K1MeeValidator.json ./artifacts/K1MeeValidator/.
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
    forge verify-contract --show-standard-json-input $(cast address-zero) K1MeeValidator > ./artifacts/K1MeeValidator/verify.json    
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