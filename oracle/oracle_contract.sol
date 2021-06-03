pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;
import "../Common.sol";
contract Oracle{

    uint256 public constant PRICE_PRECISION = 10;
    uint256 constant decimal_one = 10**PRICE_PRECISION;
    uint256 constant decimal_u64 = 2e64 - 1;
    uint256 constant MAX_LIMIT = 30;

    struct Config{
        address owner;
        address usdt_asset;
        address platform_asset;
    }

    struct PriceResponse{
        uint256 rate;
        uint256 last_update_base; 
        uint256 last_update_quote;
    }

    struct PriceResponseElem{
        address asset_token;
        uint256 price;
        uint256 last_update_time;
    }

    struct RegisterAssetRes{
        address asset_token;
        address feeder;
    }

    struct FeedPriceReq{
        address token;
        uint256 price;
    }

    struct PriceInfo{
        uint256 price;
        uint256 last_update_time;
    }

    struct itmap {
        mapping(address => uint256) data;
        address[] keys;
    }

    struct KeyFlag {
        address key;
        bool deleted;
    }

    itmap price_indexs;

    Config public config;

    constructor(
            address _owner,
            address _usdt_asset,
            address _platform_asset
        )public{
            config.owner = _owner;
            config.usdt_asset = _usdt_asset;
            config.platform_asset = _platform_asset;
    }

    mapping(address => RegisterAssetRes) asset_usdt_config;
    mapping(address => RegisterAssetRes) asset_platform_config;

    mapping(address => PriceInfo)public UsdtFeedPrice;
    mapping(address => PriceInfo)public PlatformFeedPrice;

    event register_asset(address , address);
    event usdt_feed_price_log(address , uint256);
    event platform_feed_price_log(address , uint256);

    function UpdateConfig(address  _owner) external{
        require (msg.sender == config.owner,"Oracle: UpdateConfig Unauthoruzed");
        config.owner = _owner;
    }

    function RegisterAsset(address _asset_token,address _usdt_feeder,address _platform_feeder) public{
        _register_usdt_asset(_asset_token,_usdt_feeder);
        _register_platform_asset(_asset_token,_platform_feeder);
        _itmap_insert(_asset_token);
    }

    function FeedPrice(
                       FeedPriceReq[] memory _usdt_price,
                       FeedPriceReq[] memory _platform_price)public{

        for(uint i = 0;i < _usdt_price.length; i++){
            require( asset_usdt_config[_usdt_price[i].token].asset_token != address(0),"Oracle: FeedPrice usdt_asset_token Not Found");
            require(_usdt_price[i].price > 0, "Oracle: FeedPrice usdt_asset_token Price Less Zero");
            require(msg.sender == asset_usdt_config[_usdt_price[i].token].feeder,"Oracle: Feeder is not a specified address");
            UsdtFeedPrice[_usdt_price[i].token].price = _usdt_price[i].price;
            UsdtFeedPrice[_usdt_price[i].token].last_update_time = block.timestamp;
            emit usdt_feed_price_log(_usdt_price[i].token,_usdt_price[i].price);
        }
         for(uint i = 0;i < _platform_price.length; i++){
            require(asset_platform_config[_platform_price[i].token].asset_token != address(0),"Oracle: FeedPrice platform_asset_token Not Found");
            require(_platform_price[i].price > 0, "Oracle: FeedPrice platform_asset_token Price Less Zero");
            require(msg.sender == asset_platform_config[_platform_price[i].token].feeder,"Oracle: Feeder is not a specified address");
            PlatformFeedPrice[_platform_price[i].token].price = _platform_price[i].price;
            PlatformFeedPrice[_platform_price[i].token].last_update_time = block.timestamp;
            emit platform_feed_price_log(_platform_price[i].token,_platform_price[i].price);
        }
    }

    function QueryConfig() public view returns (Config memory){
        return config;
    }

    function QueryUsdtFeeder(address _asset_token)
        public view returns(RegisterAssetRes memory result){
        result.asset_token = asset_usdt_config[_asset_token].asset_token;
        result.feeder = asset_usdt_config[_asset_token].feeder;
    }

    function QueryPlatformFeeder(address _asset_token)
        public view returns(RegisterAssetRes memory result){
        result.asset_token = asset_platform_config[_asset_token].asset_token;
        result.feeder = asset_platform_config[_asset_token].feeder;
    }

    function QueryUsdtPrice(address base,address quote)
        public view returns (PriceResponse memory result){
        PriceInfo memory quote_price;
        PriceInfo memory base_price;

        if (config.usdt_asset == quote){
            quote_price.price = decimal_one;
            quote_price.last_update_time = decimal_u64;
        }else{
            quote_price.price = UsdtFeedPrice[quote].price;
            quote_price.last_update_time = UsdtFeedPrice[quote].last_update_time;
            require(quote_price.price > 0 && quote_price.last_update_time > 0,"Orcale: price or timestamp is zero");
        }

        if (config.usdt_asset == base){
            base_price.price = decimal_one;
            base_price.last_update_time = decimal_u64;
        }else{
            base_price.price = UsdtFeedPrice[base].price;
            base_price.last_update_time = UsdtFeedPrice[base].last_update_time;
            require(quote_price.price > 0 && quote_price.last_update_time > 0,"Orcale: price or timestamp is zero");
        }
        result.rate = CommonPlatformLib.UintDecimalDiv(
            base_price.price,
            quote_price.price,
            PRICE_PRECISION);
        result.last_update_base = base_price.last_update_time;
        result.last_update_quote = quote_price.last_update_time;
    }

    function QueryPlatformPrice(address base,address quote)
        public view returns (PriceResponse memory result){
        PriceInfo memory quote_price;
        PriceInfo memory base_price;

        if (config.platform_asset == quote){
            quote_price.price = decimal_one;
            quote_price.last_update_time = decimal_u64;
        }else{
            quote_price.price = PlatformFeedPrice[quote].price;
            quote_price.last_update_time = PlatformFeedPrice[quote].last_update_time;
        }

        if (config.platform_asset == base){
            base_price.price = decimal_one;
            base_price.last_update_time = decimal_u64;
        }else{
            base_price.price = PlatformFeedPrice[base].price;
            base_price.last_update_time = PlatformFeedPrice[base].last_update_time;
        }
         result.rate = CommonPlatformLib.UintDecimalDiv(
                    base_price.price,
                    quote_price.price,
                    PRICE_PRECISION);
        result.last_update_base = base_price.last_update_time;
        result.last_update_quote = quote_price.last_update_time;
    }

    function _itmap_iterate_next(uint256 keyIndex) internal view returns (uint256 r_keyIndex) {
        keyIndex++;
        while (
            keyIndex < price_indexs.keys.length
        ) keyIndex++;
        return keyIndex;
    }

    function _itmap_keyindex(address key) internal view returns (uint256) {
        return price_indexs.data[key];
    }

    function _itmap_iterate_prev(uint256 keyIndex) internal view returns (uint256 r_keyIndex) {
        if (keyIndex > price_indexs.keys.length || keyIndex == 0) return price_indexs.keys.length;
        keyIndex--;
        while (keyIndex > 0) keyIndex--;
        return keyIndex;
    }

    function _itmap_iterate_valid(uint256 keyIndex) internal view returns (bool) {
        return keyIndex != 0 && keyIndex <= price_indexs.keys.length;

    }

    function _itmap_iterate_get_usdt(uint256 keyIndex) internal view returns (PriceResponseElem memory value) {
        value.asset_token = price_indexs.keys[keyIndex-1];
        value.price = UsdtFeedPrice[price_indexs.keys[keyIndex-1]].price;
        value.last_update_time = UsdtFeedPrice[price_indexs.keys[keyIndex-1]].last_update_time;
    }

    function _itmap_iterate_get_platform(uint256 keyIndex) internal view returns (PriceResponseElem memory value) {
        value.asset_token = price_indexs.keys[keyIndex-1];
        value.price = PlatformFeedPrice[price_indexs.keys[keyIndex-1]].price;
        value.last_update_time = PlatformFeedPrice[price_indexs.keys[keyIndex-1]].last_update_time;
    }

    function QueryUsdtPrices(address _start_after,uint256 _limit,bool _isAsc)
        public view returns(PriceResponseElem[] memory result,uint256 len){
        uint256 limit = _limit;
        if (limit > MAX_LIMIT) {
            limit = MAX_LIMIT;
        }

        result = new PriceResponseElem[](limit);

        if (price_indexs.data[_start_after] == 0 && _start_after != address(0)){
            return (result,len);
        }

        uint256 keyindex;

        if (_start_after != address(0)){
            keyindex = _itmap_keyindex(_start_after);
        }

        if (_isAsc) {
            keyindex++;
            if (keyindex > price_indexs.keys.length) {
                return (result, len);
            }
            for ( uint256 i = keyindex; _itmap_iterate_valid(i) && (len < limit);
                  i++) {
                result[len++] =  _itmap_iterate_get_usdt(i);
            }
        }else {
            if (keyindex <= 1) {
                return (result, len);
            }
            keyindex--;
            for (uint256 i = keyindex; _itmap_iterate_valid(i) && (len < limit);
                i--) {
                result[len++] = _itmap_iterate_get_usdt(i);
            }
        }

    }

    function QueryPlatformPrices(address _start_after,uint256 _limit,bool _isAsc)
        public view returns(PriceResponseElem[] memory result,uint256 len){
        uint256 limit = _limit;
        if (limit > MAX_LIMIT) {
            limit = MAX_LIMIT;
        }
        result = new PriceResponseElem[](limit);

        if (price_indexs.data[_start_after] == 0 && _start_after != address(0)){
            return (result,len);
        }
        uint256 keyindex;

        if (_start_after != address(0)){
            keyindex = _itmap_keyindex(_start_after);
        }

        if (_isAsc) {

            keyindex++;
            if (keyindex > price_indexs.keys.length) {
                return (result, len);
            }

            for ( uint256 i = keyindex; _itmap_iterate_valid(i) && (len < limit);
                  i++) {
                result[len++] =  _itmap_iterate_get_platform(i);
            }
        }else {
            if (keyindex <= 1) {
                return (result, len);
            }
            keyindex--;
            for (uint256 i = keyindex; _itmap_iterate_valid(i) && (len < limit);
                i--) {
                result[len++] = _itmap_iterate_get_platform(i);
            }
        }
    }


    function _register_platform_asset(address _asset_token,
                              address _feeder) private{
        require(msg.sender == config.owner,"Oracle: Regplatform Unauthoruzed");
        require(asset_platform_config[_asset_token].asset_token == address(0),"Oracle: Platform Asset was already Registered");
        asset_platform_config[_asset_token].asset_token = _asset_token;
        asset_platform_config[_asset_token].feeder = _feeder;
        emit register_asset(_asset_token,_feeder);
    }

    function _register_usdt_asset(address _asset_token,
                               address _feeder) private {
        require(msg.sender == config.owner,"Oracle: Regusdt Unauthoruzed");
        require(asset_usdt_config[_asset_token].asset_token == address(0),"Oracle: Usdt Asset was already Registered");
        asset_usdt_config[_asset_token].asset_token = _asset_token;
        asset_usdt_config[_asset_token].feeder = _feeder;

        emit register_asset(_asset_token,_feeder);
    }

    function _itmap_insert(address key) internal returns (bool) {
        uint256 keyIndex = price_indexs.data[key];
        if (keyIndex > 0) return false;
        price_indexs.keys.push(key);
        price_indexs.data[key] = price_indexs.keys.length;
        return true;
    }
}
