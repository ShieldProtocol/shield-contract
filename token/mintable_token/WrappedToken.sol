// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract WrappedToken is ERC20, Ownable {
    event Burn(address indexed _sender, address indexed _to, uint256 amount);
    address public mint_address;

    constructor( address mint, string memory name, string memory symbol
        ) public ERC20(name, symbol) {
        mint_address = mint;
    }

    function burn(uint256 amount, address to) public {
        _burn(_msgSender(), amount);

        emit Burn(_msgSender(), to, amount);
    }

    function mint(address account, uint256 amount) public {
        require(msg.sender == mint_address, "unauthorized");
        _mint(account, amount);
    }
}
