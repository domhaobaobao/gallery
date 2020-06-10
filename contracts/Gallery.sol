
pragma solidity ^0.6.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/ERC721.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

contract Gallery is ERC721, Ownable {

    // Mapping from tokenId to the creator's address.
    mapping(uint256 => address) private tokenCreators;

    // Mapping of address to boolean indicating whether the address is whitelisted
    mapping(address => bool) private whitelistMap;

    // flag controlling whether whitelist is enabled.
    bool private whitelistEnabled = true;

    // Mapping from tokenId to sale price.
    mapping(uint256 => uint256) private tokenPrices;

    // Mapping from tokenId to whether the token has been sold before.
    mapping(uint256 => bool) private soldBefore;

    // Mapping from tokenId to token owner that set the sale price.
    mapping(uint256 => address) private priceSetters;

    // Mapping from tokenId to the current bid amount.
    mapping(uint256 => uint256) private tokenCurrentBids;

    // Mapping from tokenId to the current bidder.
    mapping(uint256 => address) private tokenCurrentBidders;

    // Marketplace fee paid to the owner of the contract.
    uint256 private marketplaceFee = 3; // 3 %

    // Royalty fee paid to the creator of a token on secondary sales.
    uint256 private royaltyFee = 3; // 3 %

    // Primary sale fee split.
    uint256 private primarySaleFee = 15; // 15 %


    constructor() ERC721 ("MyGallery", "MG") public {}

    /*
    * @dev Function to set the marketplace fee percentage.
    * @param _percentage uint256 fee to take from purchases.
    */
    function setMarketplaceFee(uint256 _percentage)
        public onlyOwner
    {
        marketplaceFee = _percentage;
    }

    /*
    * @dev Function to set the royalty fee percentage.
    * @param _percentage uint256 royalty fee to take split between seller and creator.
    */
    function setRoyaltyFee(uint256 _percentage)
        public onlyOwner
    {
        royaltyFee = _percentage;
    }

    /*
    * @dev Function to set the primary sale fee percentage.
    * @param _percentage uint256 fee to take from purchases.
    */
    function setPrimarySaleFee(uint256 _percentage)
        public onlyOwner
    {
        primarySaleFee = _percentage;
    }

    /**
    * @dev Enable or disable the whitelist
    * @param _enabled bool of whether to enable the whitelist.
    */
    function setEnabledWhitelist(bool _enabled) 
        public onlyOwner
    {
        whitelistEnabled = _enabled;
    }

    /**
    * @dev batch add addresses to the whitelist
    * @param _addresses address[] of addresses to whitelist.
    */
    function addToWhitelist(address[] memory _addresses)
        public onlyOwner
    {
        // Add all whitelistees.
        for (uint256 i = 0; i < _addresses.length; i++) {
            address _address = _addresses[i];
            if (!isWhitelisted(_address)) {
                whitelistMap[_address] = true;
            }
        }
    }


    /**
    * @dev batch remove addresses from the whitelist
    * @param _addresses address[] of addresses to whitelist.
    */
    function removeFromWhitelist(address[] memory _addresses) 
        public onlyOwner
    {
        // Add all whitelistees.
        for (uint256 i = 0; i < _addresses.length; i++) {
            address _address = _addresses[i];
            if (isWhitelisted(_address)) {
                whitelistMap[_address] = false;
            }
        }
    }

    /**
    * @dev Returns whether the address is whitelisted
    * @param _address address to check
    * @return bool
    */
    function isWhitelisted(address _address) 
        public view returns (bool)
    {
        if (whitelistEnabled) {
            return whitelistMap[_address];
        } else {
            return true;
        }
    }

    /**
    * @dev Creates a new unique token.
    * @param _uri string metadata uri associated with the token.
    */
    function createToken(string memory _uri)
        public
    {
        address _creator = msg.sender;
        require(
            isWhitelisted(_creator),
            "must be whitelisted to create tokens"
        );
        uint256 _newTokenId = totalSupply()+1;
        _mint(_creator, _newTokenId);
        _setTokenURI(_newTokenId, _uri);
        tokenCreators[_newTokenId] = _creator;
    }


    /* @dev Checks that the token owner is approved for the ERC721Market
    * @param _tokenId uint256 ID of the token
    */
    modifier ownerMustHaveMarketplaceApproved(uint256 _tokenId) {
        address owner = ownerOf(_tokenId);
        require(
            isApprovedForAll(owner, address(this)),
            "owner must have approved contract"
        );
        _;
    }

    /*
    * @dev Checks that the token is owned by the sender
    * @param _tokenId uint256 ID of the token
    */
    modifier senderMustBeTokenOwner(uint256 _tokenId) {
        address owner = ownerOf(_tokenId);
        require(
            owner == msg.sender,
            "sender must be the token owner"
        );
        _;
    }

    /*
    * @dev Checks that the token is owned by the same person who set the sale price.
    * @param _tokenId address of the contract storing the token.
    */
    function _priceSetterStillOwnsTheToken(uint256 _tokenId)
        internal view returns (bool)
    {
        ownerOf(_tokenId) == priceSetters[_tokenId];
    }


    /*
    * @dev Set the token for sale
    * @param _tokenId uint256 ID of the token
    * @param _amount uint256 wei value that the item is for sale
    */
    function setSalePrice(uint256 _tokenId, uint256 _amount)
        public
        ownerMustHaveMarketplaceApproved(_tokenId)
        senderMustBeTokenOwner(_tokenId)
    {
        tokenPrices[_tokenId] = _amount;
        priceSetters[_tokenId] = msg.sender;
        // emit SetSalePrice(_originContract, _amount, _tokenId);
    }


    /*
    * @dev Purchases the token if it is for sale.
    * @param _tokenId uint256 ID of the token.
    */
    function buy(uint256 _tokenId)
        public
        payable
        ownerMustHaveMarketplaceApproved(_tokenId)
    {
        // Check that the person who set the price still owns the token.
        require(
            _priceSetterStillOwnsTheToken(_tokenId),
            "Current token owner must be the person to have the latest price."
        );

        // Check that token is for sale.
        uint256 tokenPrice = tokenPrices[_tokenId];
        require(tokenPrice > 0, "Tokens priced at 0 are not for sale.");

        // Check that enough ether was sent.
        uint256 requiredCost = tokenPrice + _calcMarketplaceFee(tokenPrice);
        require(
            requiredCost == msg.value,
            "Must purchase the token for the correct price"
        );

        address tokenOwner = ownerOf(_tokenId);

        // Payout all parties.
        _payout(tokenPrice, payable(tokenOwner), _tokenId);

        // Transfer token.
        safeTransferFrom(tokenOwner, msg.sender, _tokenId);

        // Wipe the token price.
        _resetTokenPrice(_tokenId);

        // set the token as sold
        _setTokenAsSold(_tokenId);

        // if the buyer had an existing bid, return it  // TODO: what if someone else had a bid?
        if (_addressHasBidOnToken(msg.sender, _tokenId)) {
            _refundBid(_tokenId);
        }


        // emit Sold(msg.sender, tokenOwner, tokenPrice, _tokenId);
    }


    /**
    * @dev Gets the sale price of the token
    * @param _tokenId uint256 ID of the token
    * @return sale price of the token
    */
    function tokenPrice(uint256 _tokenId)
        public
        view
        returns (uint256)
    {
        if (_priceSetterStillOwnsTheToken(_tokenId)) {
            return tokenPrices[_tokenId];
        }
        return 0;
    }

    /*
    * @dev Internal function to set a token as sold.
    * @param _tokenId uin256 id of the token.
    */
    function _setTokenAsSold(uint256 _tokenId)
        internal
    {
        if (soldBefore[_tokenId]) {
            return;
        }
        soldBefore[_tokenId] = true;
    }

    /* @dev Internal function to set token price to 0 for a give contract.
    * @param _tokenId uin256 id of the token.
    */
    function _resetTokenPrice(uint256 _tokenId)
        internal
    {
        tokenPrices[_tokenId] = 0;
        priceSetters[_tokenId] = address(0);
    }


    /*
    * @dev Internal function to calculate Marketplace fees.
    *      If primary sale:  fee + split with seller
          otherwise:        just fee.
    * @param _amount uint256 value to be split
    * @param _tokenId id of the token
    */
    function _calcMarketplacePayment(uint256 _amount, uint256 _tokenId)
        internal view returns (uint256)
    {
        uint256 marketplaceFeePayment = _calcMarketplaceFee(_amount);
        bool isPrimarySale = !soldBefore[_tokenId];
        if (isPrimarySale) {
            uint256 primarySalePayment = _amount.mul(primarySaleFee).div(100);
            return marketplaceFeePayment + primarySalePayment;
        }
        return marketplaceFeePayment;
    }

    /*
    * @dev Internal function calculate marketplace fee for a given amount.
    *      f(_amount) =  _amount * (fee % / 100)
    * @param _amount uint256 value to be split.
    */
    function _calcMarketplaceFee(uint256 _amount)
        internal view returns (uint256)
    {
        return _amount.mul(marketplaceFee).div(100);
    }

    /*
    * @dev Internal function to calculate royalty payment.
    *      If primary sale: 0
    *      otherwise:       artist royalty.
    * @param _amount uint256 value to be split
    * @param _tokenId id of the token
    */
    function _calcRoyaltyPayment(uint256 _amount, uint256 _tokenId) 
        internal view returns (uint256) 
    {
        if(soldBefore[_tokenId]) {
            return _amount.mul(royaltyFee).div(100);
        } else {
            return(0);
        }
    }


    /*
    * @dev Internal function to calculate seller payment.
    *      If primary sale: _amount - split with marketplace,
    *      otherwise:       _amount - artist royalty.
    * @param _amount uint256 value to be split
    * @param _tokenId id of the token
    */
    function _calcSellerPayment(uint256 _amount, uint256 _tokenId) 
        internal view returns (uint256) 
    {
        if(soldBefore[_tokenId]) {
            return _amount - _calcRoyaltyPayment(_amount,_tokenId);
        } else {
            return _amount - _amount.mul(primarySaleFee).div(100);
        }

    }


    /* @dev Internal function to return an existing bid on a token to the
    *      bidder and reset bid.
    * @param _tokenId uin256 id of the token.
    */
    function _refundBid(uint256 _tokenId) 
        internal
    {
        address payable currentBidder = payable(tokenCurrentBidders[_tokenId]);
        uint256 currentBid = tokenCurrentBids[_tokenId];
        uint256 valueToReturn = currentBid + _calcMarketplaceFee(currentBid);
        if (currentBidder == address(0)) {
            return;
        }
        _resetBid( _tokenId);
        currentBidder.transfer(valueToReturn);
    }

    /*
    * @dev Internal function to reset bid by setting bidder and bid to 0.
    * @param _tokenId uin256 id of the token.
    */
    function _resetBid(uint256 _tokenId)
        internal
    {
        tokenCurrentBidders[_tokenId] = address(0);
        tokenCurrentBids[_tokenId] = 0;
    }

    /*
    * @dev Internal function to set a bid.
    * @param _amount uint256 value in wei to bid. Does not include marketplace fee.
    * @param _bidder address of the bidder.
    * @param _tokenId uin256 id of the token.
    */
    function _setBid(uint256 _amount, address _bidder, uint256 _tokenId) 
        internal
    {
        // Check bidder not 0 address.
        require(_bidder != address(0), "Bidder cannot be 0 address.");

        // Set bid.
        tokenCurrentBidders[_tokenId] = _bidder;
        tokenCurrentBids[_tokenId] = _amount;
    }

    /* @dev Internal function see if the given address has an existing bid on a token.
    * @param _bidder address that may have a current bid.
    * @param _tokenId uin256 id of the token.
    */
    function _addressHasBidOnToken(address _bidder, uint256 _tokenId) 
        internal view returns (bool) 
    {
        return tokenCurrentBidders[_tokenId] == _bidder;
    }


    /*
    * @dev Internal function see if the token has an existing bid.
    * @param _tokenId uin256 id of the token.
    */
    function _tokenHasBid(uint256 _tokenId)
        internal view returns (bool)
    {
        return tokenCurrentBidders[_tokenId] != address(0);
    }

    /* @dev Internal function to pay the seller, creator, and maintainer.
    * @param _amount uint256 value to be split.
    * @param _seller address seller of the token.
    * @param _originContract address of the token contract.
    * @param _tokenId uint256 ID of the token.
    */
    function _payout(uint256 _amount, address payable _seller, uint256 _tokenId) 
        private
    {
        address payable maintainer = payable(this.owner());
        address payable creator = payable(tokenCreators[_tokenId]);

        uint256 marketplacePayment = _calcMarketplacePayment(_amount,_tokenId);
        uint256 sellerPayment = _calcSellerPayment(_amount,_tokenId);
        uint256 royaltyPayment = _calcRoyaltyPayment(_amount, _tokenId);

        if (marketplacePayment > 0) {
            maintainer.transfer(marketplacePayment);
        }
        if (sellerPayment > 0) {
            _seller.transfer(sellerPayment);
        }
        if (royaltyPayment > 0) {
            creator.transfer(royaltyPayment);
        }
    }

    /*
    * @dev Bids on the token, replacing the bid if the bid is higher than the current bid. You cannot bid on a token you already own.
    * @param _newBidAmount uint256 value in wei to bid, plus marketplace fee.
    * @param _tokenId uint256 ID of the token
    */
    function bid(uint256 _newBidAmount, uint256 _tokenId) 
        public payable 
        ownerMustHaveMarketplaceApproved( _tokenId)
    {
        // Check that bid is greater than 0.
        require(_newBidAmount > 0, "Cannot bid 0 Wei.");

        // Check that bid is higher than previous bid
        uint256 currentBidAmount = tokenCurrentBids[_tokenId];
        require(
            _newBidAmount > currentBidAmount,
            "Must place higher bid than existing bid."
        );

        // Check that enough ether was sent.
        uint256 requiredCost = _newBidAmount + _calcMarketplaceFee(_newBidAmount);
        require(
            requiredCost == msg.value,
            "Must purchase the token for the correct price."
        );

        // Check that bidder is not owner.
        address bidder = msg.sender;
        require(ownerOf(_tokenId) != bidder, "Bidder cannot be owner.");

        // Refund previous bidder.
        _refundBid( _tokenId);

        // Set the new bid.
        _setBid(_newBidAmount, bidder, _tokenId);

        // emit Bid(_originContract, bidder, _newBidAmount, _tokenId);
    }


    /**
    * @dev Accept the bid on the token.
    * @param _tokenId uint256 ID of the token
    */
    function acceptBid(uint256 _tokenId)
        public
        ownerMustHaveMarketplaceApproved( _tokenId)
        senderMustBeTokenOwner(_tokenId)
    {
        // Check that a bid exists.
        require(
            _tokenHasBid(_tokenId),
            "Cannot accept a bid when there is none."
        );

        // Payout all parties.
        (uint256 bidAmount, address bidder) = currentBidDetailsOfToken(_tokenId);
        _payout(bidAmount, msg.sender, _tokenId);

        // Transfer token.
        safeTransferFrom(msg.sender, bidder, _tokenId);

        // Wipe the token price and bid.
        _resetTokenPrice(_tokenId);
        _resetBid(_tokenId);

        // set the token as sold
        _setTokenAsSold(_tokenId);

        // emit AcceptBid(bidder, msg.sender, bidAmount, _tokenId);
    }


    /*
    * @dev Cancel the bid on the token.
    * @param _tokenId uint256 ID of the token.
    */
    function cancelBid(uint256 _tokenId) 
        public 
    {
        // Check that sender has a current bid.
        address bidder = msg.sender;
        require(
            _addressHasBidOnToken(bidder, _tokenId),
            "Cannot cancel a bid if sender hasn't made one."
        );

        // Refund the bidder.
        _refundBid(_tokenId);

        // uint256 bidAmount = tokenCurrentBids[_tokenId];
        // emit CancelBid(_originContract, bidder, bidAmount, _tokenId);
    }

    /*
    * @dev Function to get current bid and bidder of a token.
    * @param _tokenId uin256 id of the token.
    */
    function currentBidDetailsOfToken(uint256 _tokenId)
        public view returns (uint256, address)
    {
        return (
            tokenCurrentBids[_tokenId],
            tokenCurrentBidders[_tokenId]
        );
    }


}
