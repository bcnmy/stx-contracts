import { StxValidator_Base_Test } from "./StxValidator_Base_Test.t.sol";
import { Vm } from "forge-std/Test.sol";

contract StxValidator_NoStx_Mode_Test is StxValidator_Base_Test {
    bytes32 internal constant APP_DOMAIN_SEPARATOR = 0xa1a044077d7677adbbfa892ded5390979b33993e0e2a457e3f974bbcda53821b;

    function setUp() public virtual override {
        super.setUp();
    }
}
