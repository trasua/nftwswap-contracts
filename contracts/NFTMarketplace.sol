// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import 'hardhat/console.sol';

/* NFT Marketplace
    List NFT, 
    Buy NFT, 
    Offer NFT, 
    Accept offer, 
    Create auction, 
    Bid place,
    & support Royalty
*/
contract NFTMarketplace is Ownable, ReentrancyGuard {
    receive() external payable {}

    uint256 platformFee;
    address payable feeRecipient;

    struct ListNFT {
        address nft;
        uint256 tokenId;
        address payable seller;
        address payToken;
        uint256 price;
        bool sold;
    }

    struct OfferNFT {
        address nft;
        uint256 tokenId;
        address offerer;
        address payToken;
        uint256 offerPrice;
        bool accepted;
    }

    struct AuctionNFT {
        address nft;
        uint256 tokenId;
        address payable creator;
        address payToken;
        uint256 initialPrice;
        uint256 minBid;
        uint256 startTime;
        uint256 endTime;
        address payable lastBidder;
        uint256 heighestBid;
        address winner;
        bool success;
    }

    mapping(address => bool) private payableToken;
    address[] private tokens;

    // nft => tokenId => list struct
    mapping(address => mapping(uint256 => ListNFT)) private listNfts;

    // nft => tokenId => offerer address => offer struct
    mapping(address => mapping(uint256 => mapping(address => OfferNFT)))
        private offerNfts;

    // nft => tokenId => auction struct
    mapping(address => mapping(uint256 => AuctionNFT)) private auctionNfts;

    // auciton index => bidding counts => bidder address => bid price
    mapping(uint256 => mapping(uint256 => mapping(address => uint256)))
        private bidPrices;

    // events
    event ListedNFT(
        address indexed nft,
        uint256 indexed tokenId,
        address payToken,
        uint256 price,
        address indexed seller
    );
    event BoughtNFT(
        address indexed nft,
        uint256 indexed tokenId,
        address payToken,
        uint256 price,
        address payable seller,
        address indexed buyer
    );
    event OfferredNFT(
        address indexed nft,
        uint256 indexed tokenId,
        address payToken,
        uint256 offerPrice,
        address indexed offerer
    );
    event CanceledOfferredNFT(
        address indexed nft,
        uint256 indexed tokenId,
        address payToken,
        uint256 offerPrice,
        address indexed offerer
    );
    event AcceptedNFT(
        address indexed nft,
        uint256 indexed tokenId,
        address payToken,
        uint256 offerPrice,
        address offerer,
        address payable indexed nftOwner
    );
    event CreatedAuction(
        address indexed nft,
        uint256 indexed tokenId,
        address payToken,
        uint256 price,
        uint256 minBid,
        uint256 startTime,
        uint256 endTime,
        address payable indexed creator
    );
    event PlacedBid(
        address indexed nft,
        uint256 indexed tokenId,
        address payToken,
        uint256 bidPrice,
        address indexed bidder
    );

    event ResultedAuction(
        address indexed nft,
        uint256 indexed tokenId,
        address payable creator,
        address indexed winner,
        uint256 price,
        address caller
    );

    constructor(address payable _feeRecipient, uint256 _platformFee) {
        require(_platformFee <= 10000, "can't more than 10 percent");
        feeRecipient = _feeRecipient;
        platformFee = _platformFee;
    }

    modifier isListedNFT(address _nft, uint256 _tokenId) {
        ListNFT memory listedNFT = listNfts[_nft][_tokenId];
        require(
            listedNFT.seller != address(0) && !listedNFT.sold,
            'not listed'
        );
        _;
    }

    modifier isNotListedNFT(address _nft, uint256 _tokenId) {
        ListNFT memory listedNFT = listNfts[_nft][_tokenId];
        require(
            listedNFT.seller == address(0) || listedNFT.sold,
            'already listed'
        );
        _;
    }

    modifier isAuction(address _nft, uint256 _tokenId) {
        AuctionNFT memory auction = auctionNfts[_nft][_tokenId];
        require(
            auction.nft != address(0) && !auction.success,
            'auction already created'
        );
        _;
    }

    modifier isNotAuction(address _nft, uint256 _tokenId) {
        AuctionNFT memory auction = auctionNfts[_nft][_tokenId];
        require(
            auction.nft == address(0) || auction.success,
            'auction already created'
        );
        _;
    }

    modifier isOfferredNFT(
        address _nft,
        uint256 _tokenId,
        address _offerer
    ) {
        OfferNFT memory offer = offerNfts[_nft][_tokenId][_offerer];
        require(
            offer.offerPrice > 0 && offer.offerer != address(0),
            'not offerred nft'
        );
        _;
    }

    modifier isPayableToken(address _payToken) {
        require(
            _payToken == address(0) || payableToken[_payToken],
            'invalid pay token'
        );
        _;
    }

    // @notice List NFT on Marketplace
    function listItem(
        address _nft,
        uint256 _tokenId,
        address _payToken,
        uint256 _price
    ) external isPayableToken(_payToken) {
        IERC721 nft = IERC721(_nft);
        require(nft.ownerOf(_tokenId) == msg.sender, 'not nft owner');
        nft.transferFrom(msg.sender, address(this), _tokenId);

        listNfts[_nft][_tokenId] = ListNFT({
            nft: _nft,
            tokenId: _tokenId,
            seller: payable(msg.sender),
            payToken: _payToken,
            price: _price,
            sold: false
        });

        emit ListedNFT(_nft, _tokenId, _payToken, _price, msg.sender);
    }

    // @notice Cancel listed NFT
    function cancelListedItem(address _nft, uint256 _tokenId)
        external
        isListedNFT(_nft, _tokenId)
    {
        ListNFT memory listedNFT = listNfts[_nft][_tokenId];
        require(listedNFT.seller == msg.sender, 'not listed owner');
        IERC721(_nft).transferFrom(address(this), msg.sender, _tokenId);
        delete listNfts[_nft][_tokenId];
    }

    // @notice Buy listed NFT
    function buyItem(address _nft, uint256 _tokenId)
        external
        payable
        isListedNFT(_nft, _tokenId)
    {
        ListNFT storage listedNft = listNfts[_nft][_tokenId];
        require(!listedNft.sold, 'nft already sold');

        listedNft.sold = true;
        uint256 totalPrice = listedNft.price;
        uint256 platformFeeTotal = calculatePlatformFee(totalPrice);

        // Calculate & Transfer platfrom fee
        if (listedNft.payToken == address(0)) {
            require(msg.value >= listedNft.price, 'buyItem: incorrect price');
            feeRecipient.transfer(platformFeeTotal);
            listedNft.seller.transfer(totalPrice - platformFeeTotal);
        } else {
            IERC20(listedNft.payToken).transferFrom(
                msg.sender,
                feeRecipient,
                platformFeeTotal
            );
            // Transfer to nft owner
            IERC20(listedNft.payToken).transferFrom(
                msg.sender,
                listedNft.seller,
                totalPrice - platformFeeTotal
            );
        }

        // Transfer NFT to buyer
        IERC721(listedNft.nft).safeTransferFrom(
            address(this),
            msg.sender,
            listedNft.tokenId
        );

        emit BoughtNFT(
            listedNft.nft,
            listedNft.tokenId,
            listedNft.payToken,
            listedNft.price,
            listedNft.seller,
            msg.sender
        );
    }

    // @notice Offer listed NFT
    function offerNFT(
        address _nft,
        uint256 _tokenId,
        address _payToken,
        uint256 _offerPrice
    ) external isListedNFT(_nft, _tokenId) {
        require(_offerPrice > 0, 'price can not 0');

        ListNFT memory nft = listNfts[_nft][_tokenId];
        IERC20(nft.payToken).transferFrom(
            msg.sender,
            address(this),
            _offerPrice
        );

        offerNfts[_nft][_tokenId][msg.sender] = OfferNFT({
            nft: nft.nft,
            tokenId: nft.tokenId,
            offerer: msg.sender,
            payToken: _payToken,
            offerPrice: _offerPrice,
            accepted: false
        });

        emit OfferredNFT(
            nft.nft,
            nft.tokenId,
            nft.payToken,
            _offerPrice,
            msg.sender
        );
    }

    // @notice Offerer cancel offerring
    function cancelOfferNFT(address _nft, uint256 _tokenId)
        external
        isOfferredNFT(_nft, _tokenId, msg.sender)
    {
        OfferNFT memory offer = offerNfts[_nft][_tokenId][msg.sender];
        require(offer.offerer == msg.sender, 'not offerer');
        require(!offer.accepted, 'offer already accepted');
        delete offerNfts[_nft][_tokenId][msg.sender];
        IERC20(offer.payToken).transfer(offer.offerer, offer.offerPrice);
        emit CanceledOfferredNFT(
            offer.nft,
            offer.tokenId,
            offer.payToken,
            offer.offerPrice,
            msg.sender
        );
    }

    // @notice listed NFT owner accept offerring
    function acceptOfferNFT(
        address _nft,
        uint256 _tokenId,
        address _offerer
    )
        external
        isOfferredNFT(_nft, _tokenId, _offerer)
        isListedNFT(_nft, _tokenId)
    {
        require(
            listNfts[_nft][_tokenId].seller == msg.sender,
            'not listed owner'
        );
        OfferNFT storage offer = offerNfts[_nft][_tokenId][_offerer];
        ListNFT storage list = listNfts[offer.nft][offer.tokenId];
        require(!list.sold, 'already sold');
        require(!offer.accepted, 'offer already accepted');

        list.sold = true;
        offer.accepted = true;

        uint256 offerPrice = offer.offerPrice;
        uint256 totalPrice = offerPrice;
        IERC20 payToken = IERC20(offer.payToken);

        // Calculate & Transfer platfrom fee
        uint256 platformFeeTotal = calculatePlatformFee(offerPrice);
        payToken.transfer(feeRecipient, platformFeeTotal);

        // Transfer to seller
        payToken.transfer(list.seller, totalPrice - platformFeeTotal);

        // Transfer NFT to offerer
        IERC721(list.nft).safeTransferFrom(
            address(this),
            offer.offerer,
            list.tokenId
        );

        emit AcceptedNFT(
            offer.nft,
            offer.tokenId,
            offer.payToken,
            offer.offerPrice,
            offer.offerer,
            list.seller
        );
    }

    // @notice Create autcion
    function createAuction(
        address _nft,
        uint256 _tokenId,
        address _payToken,
        uint256 _price,
        uint256 _minBid,
        uint256 _startTime,
        uint256 _endTime
    ) external isPayableToken(_payToken) isNotAuction(_nft, _tokenId) {
        IERC721 nft = IERC721(_nft);
        require(nft.ownerOf(_tokenId) == msg.sender, 'not nft owner');
        require(_endTime > _startTime, 'invalid end time');

        nft.transferFrom(msg.sender, address(this), _tokenId);

        auctionNfts[_nft][_tokenId] = AuctionNFT({
            nft: _nft,
            tokenId: _tokenId,
            creator: payable(msg.sender),
            payToken: _payToken,
            initialPrice: _price,
            minBid: _minBid,
            startTime: _startTime,
            endTime: _endTime,
            lastBidder: payable(address(0)),
            heighestBid: _price,
            winner: address(0),
            success: false
        });

        emit CreatedAuction(
            _nft,
            _tokenId,
            _payToken,
            _price,
            _minBid,
            _startTime,
            _endTime,
            payable(msg.sender)
        );
    }

    // @notice Cancel auction
    function cancelAuction(address _nft, uint256 _tokenId)
        external
        isAuction(_nft, _tokenId)
    {
        AuctionNFT memory auction = auctionNfts[_nft][_tokenId];
        require(auction.creator == msg.sender, 'not auction creator');
        require(block.timestamp < auction.startTime, 'auction already started');
        require(auction.lastBidder == address(0), 'already have bidder');

        IERC721 nft = IERC721(_nft);
        nft.transferFrom(address(this), msg.sender, _tokenId);
        delete auctionNfts[_nft][_tokenId];
    }

    // @notice Bid place auction
    function bidAuction(
        address _nft,
        uint256 _tokenId,
        uint256 _bidPrice
    ) external payable isAuction(_nft, _tokenId) {
        require(
            block.timestamp >= auctionNfts[_nft][_tokenId].startTime,
            'auction not start'
        );
        require(
            block.timestamp <= auctionNfts[_nft][_tokenId].endTime,
            'auction ended'
        );

        AuctionNFT storage auction = auctionNfts[_nft][_tokenId];
        uint256 bidPrice = auction.payToken == address(0)
            ? msg.value
            : _bidPrice;
        require(
            bidPrice >=
                auctionNfts[_nft][_tokenId].heighestBid +
                    auctionNfts[_nft][_tokenId].minBid,
            'less than min bid price'
        );

        if (auction.payToken == address(0)) {
            payable(address(this)).transfer(bidPrice);
        } else {
            IERC20 payToken = IERC20(auction.payToken);
            payToken.transferFrom(msg.sender, address(this), bidPrice);
        }

        if (auction.lastBidder != address(0)) {
            // Transfer back to last bidder
            if (auction.payToken == address(0)) {
                auction.lastBidder.transfer(auction.heighestBid);
            } else {
                IERC20(auction.payToken).transfer(
                    auction.lastBidder,
                    auction.heighestBid
                );
            }
        }

        // Set new heighest bid price
        auction.lastBidder = payable(msg.sender);
        auction.heighestBid = bidPrice;

        emit PlacedBid(_nft, _tokenId, auction.payToken, bidPrice, msg.sender);
    }

    // @notice Result auction, can call by auction creator, heighest bidder, or marketplace owner only!
    function resultAuction(address _nft, uint256 _tokenId) external {
        require(!auctionNfts[_nft][_tokenId].success, 'already resulted');
        require(
            msg.sender == owner() ||
                msg.sender == auctionNfts[_nft][_tokenId].creator ||
                msg.sender == auctionNfts[_nft][_tokenId].lastBidder,
            'not creator, winner, or owner'
        );
        require(
            block.timestamp > auctionNfts[_nft][_tokenId].endTime,
            'auction not ended'
        );

        AuctionNFT storage auction = auctionNfts[_nft][_tokenId];
        IERC721 nft = IERC721(auction.nft);

        auction.success = true;
        auction.winner = auction.creator;

        uint256 totalPrice = auction.heighestBid;
        uint256 platformFeeTotal = calculatePlatformFee(auction.heighestBid);

        // Calculate & Transfer platfrom fee
        if (auction.payToken == address(0)) {
            feeRecipient.transfer(platformFeeTotal);
            auction.creator.transfer(totalPrice - platformFeeTotal);
        } else {
            IERC20 payToken = IERC20(auction.payToken);
            payToken.transfer(feeRecipient, platformFeeTotal);
            // Transfer to auction creator
            payToken.transfer(auction.creator, totalPrice - platformFeeTotal);
        }

        // Transfer NFT to the winner
        nft.transferFrom(address(this), auction.lastBidder, auction.tokenId);

        emit ResultedAuction(
            _nft,
            _tokenId,
            payable(auction.creator),
            auction.lastBidder,
            auction.heighestBid,
            msg.sender
        );
    }

    function calculatePlatformFee(uint256 _price)
        public
        view
        returns (uint256)
    {
        return (_price * platformFee) / 10000;
    }

    function calculateRoyalty(uint256 _royalty, uint256 _price)
        public
        pure
        returns (uint256)
    {
        return (_price * _royalty) / 10000;
    }

    function getListedItem(address _nft, uint256 _tokenId)
        public
        view
        returns (ListNFT memory)
    {
        return listNfts[_nft][_tokenId];
    }

    function getPayableTokens() external view returns (address[] memory) {
        return tokens;
    }

    function checkIsPayableToken(address _payableToken)
        external
        view
        returns (bool)
    {
        return payableToken[_payableToken];
    }

    function addPayableToken(address _token) external onlyOwner {
        require(_token != address(0), 'invalid token');
        require(!payableToken[_token], 'already payable token');
        payableToken[_token] = true;
        tokens.push(_token);
    }

    function updatePlatformFee(uint256 _platformFee) external onlyOwner {
        require(_platformFee <= 10000, "can't more than 10 percent");
        platformFee = _platformFee;
    }

    function changeFeeRecipient(address payable _feeRecipient)
        external
        onlyOwner
    {
        require(_feeRecipient != address(0), "can't be 0 address");
        feeRecipient = _feeRecipient;
    }
}
