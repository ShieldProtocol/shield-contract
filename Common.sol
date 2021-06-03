pragma solidity ^0.6.0;

library CommonPlatformLib {
    function UintDecimalMul(uint256 num1, uint256 num2, uint256 num2_precision) internal pure returns (uint256) {
        return _mul(num1,num2)/(10**num2_precision);
    }

    function UintDecimalDiv(uint256 num1, uint256 num2, uint256 num2_precision) internal pure returns (uint256) {

        return _mul(num1 , 10**num2_precision)/num2;
    }

    function Min(uint256 num1, uint256 num2) internal pure returns (uint256) {
        if (num1 > num2) {
            return num2;
        }
        return num1;
    }

    function Max(uint256 num1, uint256 num2) internal pure returns (uint256) {
        if (num1 > num2) {
            return num1;
        }
        return num2;
    }

    function _mul(uint256 a, uint256 b) internal pure returns (uint256 c) {
        if (a == 0) {
            return 0;
        }
        c = a * b;
        assert(c / a == b);
        return c;
  }
}
