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

pragma solidity 0.8.16;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "./Interface/IAdorn1155.sol";

contract HaloItemClaim is Ownable,ReentrancyGuard{

    using ECDSA for bytes32;
    using Address for address;

    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableMap for EnumerableMap.UintToUintMap;

    //event mint
    event eMint(
        address user,
        uint256[] ids,
        uint256 mintCount,
        uint256 stage
    );

    struct Condition {
        uint256 startTime;      //the start time
        uint256 endTime;        //the end tim
        uint256[] tokenIds;     //the token id
        uint256[] idSoldLimit;  //the token id, the max sold amount
        uint256 stage;          //cur stage
        bytes32 signCode;       //signCode
        bytes wlSignature;      //enable white
    }

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
        "Condition(uint256 startTime,uint256 endTime,uint256[] tokenIds,uint256[] idSoldLimit,uint256 stage,bytes32 signCode,bytes wlSignature)"
    );

    // super minters
    EnumerableSet.AddressSet private _claimedAddress; //claimed address
    EnumerableSet.Bytes32Set private _signCodes;//signCode

    // the 1155 had sold count
    mapping( uint256 => uint256 ) public _1155SoldCount;//tokenid->sold count

    address public _SIGNER;
    address public _haloItem;

    constructor(address SIGNER, address haloItem) {

        _SIGNER = SIGNER;
        _haloItem = haloItem;

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                EIP712DOMAIN_TYPEHASH,
                keccak256("HaloItemClaim"),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }

    function isClaimed(address minter) view public returns(bool) {
        return _claimedAddress.contains(minter);
    }

    function isValidSignCode(bytes32 signCode) view public returns(bool) {
        return !_signCodes.contains(signCode);
    }

    function getSoldCount(uint256[] calldata tokenId) view public returns(uint256[] memory soldCounts) {

        soldCounts = new uint256[](tokenId.length);
        for(uint256 i=0; i< tokenId.length; i++){
            soldCounts[i] = _1155SoldCount[tokenId[i]];
        }
    }

    function claim(Condition calldata condition, bytes memory dataSignature )  public nonReentrant {

        require( block.timestamp >= condition.startTime && block.timestamp < condition.endTime, "out date" );

        if(condition.stage == 1){
            require( !isClaimed(msg.sender), "once mint!" );
        }

        require( condition.tokenIds.length == condition.idSoldLimit.length, "the array length is not match!" );
        require( isValidSignCode(condition.signCode),"invalid signCode!");
        require( verify(condition, msg.sender, dataSignature), "this sign is not valid");

        uint256 soldCount;
        uint256 tokenId;
       
        for(uint256 i=0; i< condition.idSoldLimit.length; i++){

            tokenId = condition.tokenIds[i];
            soldCount = _1155SoldCount[tokenId];
            soldCount += 1;
            require(soldCount <= condition.idSoldLimit[i],"sold count is max!");

            _1155SoldCount[tokenId]=soldCount;

            IAdorn1155(_haloItem).mint(msg.sender,tokenId,1,"");
        }

        _signCodes.add(condition.signCode);
        _claimedAddress.add(msg.sender);

        emit eMint(
                msg.sender,
                condition.tokenIds,
                1,
                condition.stage
            );
    } 

    function updateSigner( address signer) external onlyOwner {
        _SIGNER = signer;
    }
    
    function updateHaloItem( address haloItem) external onlyOwner {
        _haloItem = haloItem;
    }

    function hashCondition(Condition calldata condition) public pure returns (bytes32) {

        // uint256 startTime;      //the start time
        // uint256 endTime;        //the end tim
        // uint256[] tokenIds;     //the token id
        // uint256[] idSoldLimit;  //the token id, the max sold amount
        // uint256 stage;          //cur stage
        // bytes32 signCode;       //signCode
        // bytes wlSignature;      //enable white

        return keccak256(
            abi.encode(
                TYPE_HASH,
                condition.startTime,
                condition.endTime,
                keccak256(abi.encodePacked(condition.tokenIds)),
                keccak256(abi.encodePacked(condition.idSoldLimit)),
                condition.stage,
                condition.signCode,
                keccak256(condition.wlSignature))
        );
    }

    function hashWhiteList( address user, bytes32 signCode ) public pure returns (bytes32) {

        bytes32 message = keccak256(abi.encodePacked(user, signCode));
        // hash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", message));
        return message.toEthSignedMessageHash();
    }

    function hashDigest(Condition calldata condition) public view returns (bytes32) {
        return keccak256(abi.encodePacked(
            "\x19\x01",
            DOMAIN_SEPARATOR,
            hashCondition(condition)
        ));
    }

    function verifySignature(bytes32 hash, bytes memory  signature) public view returns (bool) {
        //hash must be a soliditySha3 with accounts.sign
        return hash.recover(signature) == _SIGNER;
    }

    function verifyCondition(Condition calldata condition, uint8 v, bytes32 r, bytes32 s) public view returns (bool) {
        bytes32 digest = hashDigest(condition);
        return ecrecover(digest, v, r, s) == _SIGNER;    
    }

    function verify(  Condition calldata condition, address user, bytes memory dataSignature ) public view returns (bool) {
       
        require(condition.signCode != "","invalid sign code!");

        bytes32 digest = hashDigest(condition);
        require(verifySignature(digest,dataSignature)," invalid dataSignatures! ");

        //if(condition.wlSignature.length > 0 ){
            bytes32 hash = hashWhiteList(user, condition.signCode);
            require( verifySignature(hash, condition.wlSignature), "invalid wlSignature! ");
        //}

        return true;
    }
}
