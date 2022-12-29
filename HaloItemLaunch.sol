/***
* MIT License
* ===========
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*                             
*     __  _____    __    ____ 
*    / / / /   |  / /   / __ \
*   / /_/ / /| | / /   / / / /
*  / __  / ___ |/ /___/ /_/ / 
* /_/ /_/_/  |_/_____/\____/  
*                             
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";


contract HaloItemLaunch is Ownable {

    struct Condition{
        uint256 startTime;
        uint256 endTime;
        address costErc20;
        uint256 costAmount;
        bytes32 signCode;      
        bytes wlSignature;     
    }

    using EnumerableSet for EnumerableSet.Bytes32Set;
    using ECDSA for bytes32;
    using Address for address;
    using SafeERC20 for IERC20;

    mapping(address=>uint256) public _checkInDB;
    EnumerableSet.Bytes32Set private _signCodes;//signCode

    uint256 public _allCount;   //registered count
    uint256 public _allAmount;  //registered funds amount

    event eRegister(address owner,uint256 createdTime, uint256 amount);

    struct EIP712Domain {
        string  name;
        string  version;
        uint256 chainId;
        address verifyingContract;
    }

    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 public constant EIP712DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    //type hash
    bytes32 public constant TYPE_HASH = keccak256(
        "Condition(uint256 startTime,uint256 endTime,address costErc20,uint256 costAmount,bytes32 signCode,bytes wlSignature)"
    );

    address public _SIGNER;

    constructor(address SIGNER) {

        _SIGNER = SIGNER;

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                EIP712DOMAIN_TYPEHASH,
                keccak256("HaloItemLaunch"),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }

    //dev: pay to register according to centralized conditions
    function register( Condition calldata condition, bytes memory dataSignature ) public {

        require(_checkInDB[msg.sender]==0, "already joined!");
        require(block.timestamp > condition.startTime && block.timestamp < condition.endTime, "inalid register time!");
        require(verify(condition, msg.sender, dataSignature),"invalid data signature!");
        require(isValidSignCode(condition.signCode),"invalid signCode!");

        IERC20 costErc20 = IERC20(condition.costErc20);
        costErc20.safeTransferFrom(msg.sender, address(this), condition.costAmount);

        _checkInDB[msg.sender] = condition.costAmount;

        _allCount++;
        _allAmount+=condition.costAmount;

        _signCodes.add(condition.signCode);

        emit eRegister(msg.sender,block.timestamp, condition.costAmount);
    }

    //dev: check the owner is registered
    function isRegister( address owner ) public view returns(bool){
        return _checkInDB[owner] != 0;
    }

    function updateSigner( address signer) external onlyOwner {
        _SIGNER = signer;
    }

    //dev: urgency withdraw erc20
    function urgencyWithdrawErc20(address erc20, address target) public  onlyOwner {
        IERC20(erc20).safeTransfer(target, IERC20(erc20).balanceOf(address(this)));
    }

     //dev: refund of unwon funds
    function returned(address erc20, address[] calldata whiteList, uint256[] calldata amounts) onlyOwner external  {

        require(whiteList.length == amounts.length, "count not match!");

        uint256 cost = 0;
        for(uint256 i=0; i<amounts.length; i++){
            cost = cost + amounts[i];
        }

        require( IERC20(erc20).balanceOf(address(this)) >= cost, "invalid cost amount! ");
        
        for (uint256 i=0; i<whiteList.length; i++) {
            require(whiteList[i] != address(0),"Address is not valid");
             IERC20(erc20).safeTransfer(whiteList[i], amounts[i]);
        }
        
    }
    
    //dev: get the condition data hash
    function hashCondition(Condition calldata condition) public pure returns (bytes32) {

        // uint256 startTime;
        // uint256 endTime;
        // address costErc20;
        // uint256 costAmount;
        // bytes32 signCode;      
        // bytes wlSignature;   

        return keccak256(
            abi.encode(
                TYPE_HASH,
                condition.startTime,
                condition.endTime,
                condition.costErc20,
                condition.costAmount,
                condition.signCode,
                keccak256(condition.wlSignature))
        );
    }

    //dev: get the user address hash
    function hashWhiteList( address user, bytes32 signCode ) public pure returns (bytes32) {

        bytes32 message = keccak256(abi.encodePacked(user, signCode));
        // hash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", message));
        return message.toEthSignedMessageHash();
    }

    //dev: valid a sign code
    function isValidSignCode(bytes32 signCode) view public returns(bool) {
        return !_signCodes.contains(signCode);
    }

    //dev: get the condition data hash
    function hashDigest(Condition calldata condition) public view returns (bytes32) {
        return keccak256(abi.encodePacked(
            "\x19\x01",
            DOMAIN_SEPARATOR,
            hashCondition(condition)
        ));
    }

    //dev: valid a data signature
    function verifySignature(bytes32 hash, bytes memory  signature) public view returns (bool) {
        //hash must be a soliditySha3 with accounts.sign
        return hash.recover(signature) == _SIGNER;
    }

    //dev: valid the condition data
    function verifyCondition(Condition calldata condition, uint8 v, bytes32 r, bytes32 s) public view returns (bool) {
        bytes32 digest = hashDigest(condition);
        return ecrecover(digest, v, r, s) == _SIGNER;    
    }

    //dev: valid the condition data
    function verify(  Condition calldata condition, address user, bytes memory dataSignature ) public view returns (bool) {
       
        require(condition.signCode != "","invalid sign code!");

        bytes32 digest = hashDigest(condition);
        require(verifySignature(digest,dataSignature)," invalid dataSignatures! ");

        if(condition.wlSignature.length >0 ){
            bytes32 hash = hashWhiteList(user, condition.signCode);
            require( verifySignature(hash, condition.wlSignature), "invalid wlSignature! ");
        }

        return true;
    }

}