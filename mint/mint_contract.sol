pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "../token/mintable_token/WrappedToken.sol";
import "../Common.sol";
import "../oracle/oracle_contract.sol";
import "../token/mintable_token/TransferHelper.sol";

contract Mint {
    using SafeMath for uint256;
    
    uint256 public constant PRICE_PRECISION = 10; 
    uint256 public constant AUCTION_DISCOUNT_PRECISION = 2; 
    uint256 public constant PROTOCOL_FEE_RATE_PRECISION = 3; 
    uint256 public constant COLLATERAL_RATIO_PRECISION = 4; 

    uint256 public constant MAX_LIMIT = 30; 
    uint256 public price_expire_time = 3600; 

    Config public config; 
    uint256 public position_idx = 1; 
    mapping(address => AssetConfig) public asset_platform_config; 
    mapping(address => AssetConfig) public asset_usdt_config; 
    itmap positions; 

    struct Config {
        address owner; 
        address oracle; 
        address collector; 
        address usdt_denom; 
        address platform_denom; 
        uint256 protocol_fee_rate; 
    }

    struct AssetConfig {
        address token; 
        uint256 auction_discount; 
        uint256 min_collateral_ratio; 
        uint256 end_price; 
    }

    struct Position {
        uint256 idx; 
        address owner; 
        address denom_token; 
        Asset collateral; 
        Asset asset; 
    }

    struct Asset {
        address token; 
        uint256 amount; 
    }

    struct PriceQueryInfo {
        address base_asset; 
        address quote_asset; 
        uint256 base_end_price; 
        uint256 quote_end_price; 
        uint256 block_time; 
    }

    struct itmap {
        mapping(uint256 => IndexValue) data; 
        mapping(address => uint256[]) indexAsset; 
        mapping(address => uint256[]) indexUser; 
        KeyFlag[] keys; 
        uint256 size; 
    }
    struct IndexValue {
        uint256 keyIndex; 
        uint256 assetKeyIndex; 
        uint256 userKeyIndex; 
        Position value; 
    }
    struct KeyFlag {
        uint256 key;
        bool deleted; 
    }

    event update_config(address owner, address oracle, address collector, uint256 protocol_fee_rate);
    event register_asset(address token);
    event update_asset(address token);
    event register_migration(address token, uint256 end_price);
    event open_position(uint256 position_idx, address token, address denom_token, uint256 mint_amount,
        uint256 collateral_amount);
    event deposit(uint256 position_idx, uint256 collateral_amount);
    event withdraw(uint256 position_idx, uint256 withdraw_amount, uint256 protocol_fee);
    event mint_asset(uint256 position_idx, uint256 mint_amount);
    event burn(uint256 position_idx, uint256 burn_amount);
    event auction(uint256 _position_idx, address position_owner, uint256 return_collateral_amount,
        uint256 liquidated_asset_amount, uint256 protocol_fee);

    modifier assertAuctionDiscount(uint256 _auction_discount) {
        require( _auction_discount < 1 * (10**AUCTION_DISCOUNT_PRECISION),
            "Mint: auction_discount must be smaller than 1");
        _;
    }

    modifier assertMinCollateralRatio(uint256 _min_collateral_ratio) {
        require( _min_collateral_ratio > 1 * (10**COLLATERAL_RATIO_PRECISION),
            "Mint: min_collateral_ratio must be bigger than 100%");
        _;
    }

    modifier assertProtocalFeeRate(uint256 _protocol_fee_rate) {
        require( _protocol_fee_rate < 1 * (10**PROTOCOL_FEE_RATE_PRECISION),
            "Mint: protocol_fee_rate must be smaller than 1");
        _;
    }

    constructor(address _owner, address _oracle, address _collector, address _usdt_denom,
        address _platform_denom, uint256 _protocol_fee_rate) public
        assertProtocalFeeRate(_protocol_fee_rate) {
        config.owner = _owner;
        config.oracle = _oracle;
        config.collector = _collector;
        config.usdt_denom = _usdt_denom;
        config.platform_denom = _platform_denom;
        config.protocol_fee_rate = _protocol_fee_rate;
    }

    function UpdatePriceExpireTime(uint256 _price_expire_time) external {
        require(config.owner == msg.sender, "Mint: UpdatePriceExpireTime unauthorized");
        require(_price_expire_time > 0, "Mint: UpdatePriceExpireTime price_expire_time is 0");
        price_expire_time = _price_expire_time;
    }

    function UpdateConfig(address _owner, address _oracle, address _collector, uint256 _protocol_fee_rate
        ) external assertProtocalFeeRate(_protocol_fee_rate) {
        require(config.owner == msg.sender, "Mint: UpdateConfig unauthorized");
        config.owner = _owner;
        config.oracle = _oracle;
        config.collector = _collector;
        config.protocol_fee_rate = _protocol_fee_rate;
        emit update_config(_owner, _oracle, _collector, _protocol_fee_rate);
    }

    function RegisterAsset(address _asset_token, uint256 _auction_discount,
        uint256 _min_collateral_ratio) external assertAuctionDiscount(_auction_discount)
        assertMinCollateralRatio(_min_collateral_ratio) {
        require( config.owner == msg.sender, "Mint: RegisterAsset unauthorized");
        require( asset_usdt_config[_asset_token].token == address(0),
            "Mint: _registerUsdtAsset was already registered");
        asset_platform_config[_asset_token].token = _asset_token;
        asset_platform_config[_asset_token]
            .auction_discount = _auction_discount;
        asset_platform_config[_asset_token]
            .min_collateral_ratio = _min_collateral_ratio;
        asset_platform_config[_asset_token].end_price = 0;

        asset_usdt_config[_asset_token].token = _asset_token;
        asset_usdt_config[_asset_token].auction_discount = _auction_discount;
        asset_usdt_config[_asset_token]
            .min_collateral_ratio = _min_collateral_ratio;
        asset_usdt_config[_asset_token].end_price = 0;
        emit register_asset(_asset_token);
    }

    function UpdateAsset(address _asset_token, uint256 _auction_discount,
        uint256 _min_collateral_ratio) external assertAuctionDiscount(_auction_discount)
        assertMinCollateralRatio(_min_collateral_ratio) {
        require( config.owner == msg.sender, "Mint: UpdateAsset unauthorized");
        require( asset_usdt_config[_asset_token].token == _asset_token,
            "Mint: UpdateUsdtAsset asset was not registered");
        require( asset_usdt_config[_asset_token].end_price == 0,
            "Mint: UpdateUsdtAsset asset was already abandoned or migrated");
        asset_usdt_config[_asset_token].auction_discount = _auction_discount;
        asset_usdt_config[_asset_token]
            .min_collateral_ratio = _min_collateral_ratio;

        asset_platform_config[_asset_token]
            .auction_discount = _auction_discount;
        asset_platform_config[_asset_token]
            .min_collateral_ratio = _min_collateral_ratio;
        emit update_asset(_asset_token);
    }

    function RegisterMigrate(address _asset_token, uint256 _end_price) external {
        require( config.owner == msg.sender, "Mint: RegisterMigrate unauthorized");
        require( _end_price > 0, "Mint: RegisterMigrate end_price must be bigger than 0");
        require( asset_usdt_config[_asset_token].end_price == 0,
            "Mint: RegisterMigrate asset was already abandoned or migrated");
        require( asset_usdt_config[_asset_token].token == _asset_token,
            "Mint: RegisterUsdtMigrate asset was not registered");
        asset_usdt_config[_asset_token].min_collateral_ratio =
            1 * (10**COLLATERAL_RATIO_PRECISION);
        asset_usdt_config[_asset_token].end_price = _end_price;

        asset_platform_config[_asset_token].min_collateral_ratio =
            1 * (10**COLLATERAL_RATIO_PRECISION);

        asset_platform_config[_asset_token].end_price = _end_price;
        emit register_migration( _asset_token, _end_price);
    }

    function OpenPosition(address _asset_token, address _collateral_token, uint256 _collateral_ratio) external {
        require(_asset_token != _collateral_token, "Mint: OpenPosition asset_token can't equal collateral_token");
        require(asset_usdt_config[_asset_token].end_price == 0, "Mint: OpenPosition asset was already abandoned or migrated");
        WrappedToken collateral_token = WrappedToken(_collateral_token);
        uint256 collateral_amount = collateral_token.allowance(msg.sender, address(this));
        require(collateral_amount > 0, "Mint: OpenPosition wrong collateral");
        TransferHelper.safeTransferFrom(_collateral_token, msg.sender, address(this), collateral_amount);

        require( _collateral_ratio >= asset_usdt_config[_asset_token].min_collateral_ratio,
            "Mint: OpenPosition can not open a position with low collateral ratio than minimum");

        uint256 price = 0;
        if (_collateral_token == config.platform_denom) { 
            price = QueryPlatformPrice(_asset_token, _collateral_token, block.timestamp);
        } else {
            price = LoadPrice(
                PriceQueryInfo({
                    base_asset: _asset_token,
                    quote_asset: _collateral_token,
                    base_end_price: asset_usdt_config[_collateral_token]
                        .end_price,
                    quote_end_price: asset_usdt_config[_asset_token].end_price,
                    block_time: block.timestamp
                }));
        }

        uint256 mint_amount = (CommonPlatformLib.UintDecimalDiv(
                collateral_amount,
                price,
                PRICE_PRECISION
                ) * 1 * (10**COLLATERAL_RATIO_PRECISION)).div(_collateral_ratio);

        require(mint_amount > 0, "Mint: OpenPosition collateral is too small");

        _itmap_insert_or_update( position_idx,
            Position({
                idx: position_idx,
                owner: msg.sender,
                denom_token: config.usdt_denom,
                collateral: Asset({
                    token: _collateral_token,
                    amount: collateral_amount
                }),
                asset: Asset({token: _asset_token, amount: mint_amount})
            }));

        ++position_idx;

        WrappedToken token = WrappedToken(_asset_token);
  
        token.mint(msg.sender, mint_amount);

        emit open_position( position_idx - 1, _asset_token, config.usdt_denom,
            mint_amount, collateral_amount);
    }

    function Deposit(uint256 _position_idx) external {
        require( positions.data[_position_idx].value.idx > 0,
            "Mint: Deposit position_idx error");
        Position storage position = positions.data[_position_idx].value;
        require(position.owner == msg.sender, "Mint: Deposit unauthorized");
        WrappedToken token = WrappedToken(position.collateral.token);
        uint256 collateral_amount = token.allowance(msg.sender, address(this));
        require(collateral_amount > 0, "Mint: Deposit wrong collateral");
        TransferHelper.safeTransferFrom(position.collateral.token, msg.sender, address(this), collateral_amount);
        if (position.denom_token == config.platform_denom) {
            require( asset_platform_config[position.asset.token].end_price == 0,
                "Mint: Deposit operation is not allowed for the deprecated asset");
        } else {
            require( asset_usdt_config[position.asset.token].end_price == 0,
                "Mint: Deposit operation is not allowed for the deprecated asset");
        }

        position.collateral.amount = position.collateral.amount.add(collateral_amount);
        emit deposit(_position_idx, collateral_amount);
    }

    function Withdraw(uint256 _position_idx, uint256 _collateral_amount) public {
        require( positions.data[_position_idx].value.idx > 0,
            "Mint: Withdraw position_idx error");
        Position storage position = positions.data[_position_idx].value;
        require(position.owner == msg.sender, "Mint: Withdraw unauthorized");
        require(_collateral_amount > 0, "Mint: Withdraw wrong collateral");
        require( _collateral_amount <= position.collateral.amount,
            "Mint: Withdraw cannot withdraw more than you provide");

        uint256 price = 0;
        if (position.collateral.token == config.platform_denom) { 
            price = QueryPlatformPrice(position.asset.token, position.collateral.token, block.timestamp);
        } else {
            price = LoadPrice(
                PriceQueryInfo({
                    base_asset: position.asset.token,
                    quote_asset: position.collateral.token,
                    base_end_price: asset_usdt_config[position.asset.token]
                        .end_price,
                    quote_end_price: asset_usdt_config[
                        position.collateral.token
                    ]
                        .end_price,
                    block_time: block.timestamp
                }));
        }

        uint256 collateral_amount = position.collateral.amount.sub(_collateral_amount);

        uint256 asset_value_in_collateral_asset =
            CommonPlatformLib.UintDecimalMul(position.asset.amount,
                price, PRICE_PRECISION);

        if (position.denom_token == config.platform_denom) {
            require( CommonPlatformLib.UintDecimalMul(
                    asset_value_in_collateral_asset,
                    asset_platform_config[position.asset.token]
                        .min_collateral_ratio,
                    COLLATERAL_RATIO_PRECISION
                ) <= collateral_amount,
                "Mint: Withdraw cannot withdraw collateral over than minimum collateral ratio");
        } else {
            require( CommonPlatformLib.UintDecimalMul(
                    asset_value_in_collateral_asset,
                    asset_usdt_config[position.asset.token]
                        .min_collateral_ratio,
                    COLLATERAL_RATIO_PRECISION
                ) <= collateral_amount,
                "Mint: Withdraw cannot withdraw collateral over than minimum collateral ratio"
            );
        }
        position.collateral.amount = collateral_amount;
        uint256 protocol_fee = CommonPlatformLib.UintDecimalMul(
                _collateral_amount, config.protocol_fee_rate,
                PROTOCOL_FEE_RATE_PRECISION);
        _collateral_amount = _collateral_amount.sub(protocol_fee);
        TransferHelper.safeTransfer(position.collateral.token, msg.sender, _collateral_amount);
        if (protocol_fee > 0) {
            TransferHelper.safeTransfer(position.collateral.token, config.collector, protocol_fee);
        }
        if (position.collateral.amount == 0 && position.asset.amount == 0) {
            _itmap_remove(_position_idx);
        }

        emit withdraw(_position_idx, _collateral_amount, protocol_fee);
    }

    function MintAsset(uint256 _position_idx, uint256 _asset_amount) external {
        require( positions.data[_position_idx].value.idx > 0,
            "Mint: MintAsset position_idx error");
        Position storage position =
            positions.data[_position_idx].value;
        require(position.owner == msg.sender, "Mint: MintAsset unauthorized");

        if (position.denom_token == config.platform_denom) {
            require( asset_platform_config[position.asset.token].end_price == 0,
                "Mint: MintAsset asset was already abandoned or migrated");
        } else {
            require( asset_usdt_config[position.asset.token].end_price == 0,
                "Mint: MintAsset asset was already abandoned or migrated");
        }

        uint256 price = 0;
        if (position.collateral.token == config.platform_denom) { 
            price = QueryPlatformPrice(position.asset.token, position.collateral.token, block.timestamp);
        } else {
            price = LoadPrice(
                PriceQueryInfo({
                    base_asset: position.asset.token,
                    quote_asset: position.collateral.token,
                    base_end_price: asset_usdt_config[position.asset.token]
                        .end_price,
                    quote_end_price: asset_usdt_config[
                        position.collateral.token
                    ]
                        .end_price,
                    block_time: block.timestamp
                })
            );
        }

        uint256 asset_amount = position.asset.amount.add(_asset_amount);

        uint256 asset_value_in_collateral_asset =
            CommonPlatformLib.UintDecimalMul( asset_amount,
                price, PRICE_PRECISION);

        if (position.denom_token == config.platform_denom) {
            require( CommonPlatformLib.UintDecimalMul(
                    asset_value_in_collateral_asset,
                    asset_platform_config[position.asset.token]
                        .min_collateral_ratio,
                    COLLATERAL_RATIO_PRECISION
                ) <= position.collateral.amount,
                "Mint: MintAsset cannot mint asset over than min collateral ratio");
        } else {
            require(
                CommonPlatformLib.UintDecimalMul(
                    asset_value_in_collateral_asset,
                    asset_usdt_config[position.asset.token]
                        .min_collateral_ratio,
                    COLLATERAL_RATIO_PRECISION
                ) <= position.collateral.amount,
                "Mint: MintAsset cannot mint asset over than min collateral ratio"
            );
        }
        position.asset.amount = asset_amount;

        WrappedToken token = WrappedToken(position.asset.token);
        token.mint(msg.sender, _asset_amount);
        emit mint_asset(_position_idx, _asset_amount);
    }

    function Burn(uint256 _position_idx) public {
        require( positions.data[_position_idx].value.idx > 0, "Mint: Burn position_idx error");
        Position storage position = positions.data[_position_idx].value;
        WrappedToken token = WrappedToken(position.asset.token);
        uint256 asset_amount = token.allowance(msg.sender, address(this));
        require(asset_amount > 0, "Mint: Burn wrong asset");
        require(asset_amount <= position.asset.amount,
            "Mint: Burn cannot burn asset more than you mint");
        TransferHelper.safeTransferFrom(position.asset.token, msg.sender, address(this), asset_amount);

        uint256 end_price = 0;
        if (position.denom_token == config.platform_denom) {
            end_price = asset_platform_config[position.asset.token].end_price;
        } else {
            end_price = asset_usdt_config[position.asset.token].end_price;
        }
        if (end_price != 0) {
            // Burn deprecated asset to receive collaterals back
            uint256 refund_collateral =
                CommonPlatformLib.UintDecimalMul(
                    asset_amount,
                    end_price,
                    PRICE_PRECISION
                );
            position.asset.amount = position.asset.amount.sub(asset_amount);
            position.collateral.amount = position.collateral.amount.sub(refund_collateral);

            TransferHelper.safeTransfer(position.collateral.token, msg.sender, refund_collateral);

            if (position.collateral.amount == 0 && position.asset.amount == 0) {
                _itmap_remove(_position_idx);
            }
        } else {
            require(position.owner == msg.sender, "Mint: Burn unauthorized");
            position.asset.amount = position.asset.amount.sub(asset_amount);
        }
        token.burn(asset_amount, msg.sender);

        emit burn(_position_idx, asset_amount);
    }

    function ClosePosition(uint256 _position_idx) public {
        require( positions.data[_position_idx].value.idx > 0, "Mint: ClosePosition position_idx error");
        Position storage position = positions.data[_position_idx].value;
        WrappedToken token = WrappedToken(position.asset.token);
        uint256 asset_amount = token.allowance(msg.sender, address(this));
        require(asset_amount == position.asset.amount, "Mint: ClosePosition wrong asset");
        Burn(_position_idx);
        Withdraw(_position_idx, position.collateral.amount);
    }

    function Auction(uint256 _position_idx) external {
        require( positions.data[_position_idx].value.idx > 0,
            "Mint: Auction position_idx error");
        Position storage position = positions.data[_position_idx].value;
        WrappedToken token = WrappedToken(position.asset.token);
        uint256 asset_amount = token.allowance(msg.sender, address(this));
        require(asset_amount > 0, "Mint: Auction wrong asset");
        require(asset_amount <= position.asset.amount,
            "Mint: Auction cannot liquidate more than the position amount");
        TransferHelper.safeTransferFrom(position.asset.token, msg.sender, address(this), asset_amount);
        uint256 price = 0;
        if (position.collateral.token == config.platform_denom) { 
            price = QueryPlatformPrice(position.asset.token, position.collateral.token, block.timestamp);
        } else {
            price = LoadPrice(
                PriceQueryInfo({
                    base_asset: position.asset.token,
                    quote_asset: position.collateral.token,
                    base_end_price: asset_usdt_config[position.asset.token]
                        .end_price,
                    quote_end_price: asset_usdt_config[
                        position.collateral.token
                    ]
                        .end_price,
                    block_time: block.timestamp
                }));
        }

        // asset_amount * price_to_collateral * auction_threshold > collateral_amount
        uint256 asset_value_in_collateral_asset =
            CommonPlatformLib.UintDecimalMul(position.asset.amount, price, PRICE_PRECISION);

        uint256 discounted_price = 0;
        if (position.denom_token == config.platform_denom) {
            require(
                CommonPlatformLib.UintDecimalMul(
                    asset_value_in_collateral_asset,
                    asset_platform_config[position.asset.token]
                        .min_collateral_ratio,
                    COLLATERAL_RATIO_PRECISION
                ) > position.collateral.amount,
                "Mint: Auction cannot liquidate a safely collateralized position"
            );
            
            discounted_price = (price*(1*10**AUCTION_DISCOUNT_PRECISION)).
                div(1*(10**AUCTION_DISCOUNT_PRECISION).
                    sub(asset_platform_config[position.asset.token].auction_discount));
        } else {
            require(
                CommonPlatformLib.UintDecimalMul(
                    asset_value_in_collateral_asset,
                    asset_usdt_config[position.asset.token]
                        .min_collateral_ratio,
                    COLLATERAL_RATIO_PRECISION
                ) > position.collateral.amount,
                "Mint: Auction cannot liquidate a safely collateralized position");
            
            discounted_price =
                (price * (1 * 10**AUCTION_DISCOUNT_PRECISION)) /
                (1 * (10**AUCTION_DISCOUNT_PRECISION) -
                    asset_usdt_config[position.asset.token].auction_discount);
        }

        asset_value_in_collateral_asset = CommonPlatformLib.UintDecimalMul(
            asset_amount, discounted_price, PRICE_PRECISION);

        uint256 refund_asset_amount = 0;
        uint256 return_collateral_amount = position.collateral.amount;
        if (asset_value_in_collateral_asset > position.collateral.amount) {
            refund_asset_amount = ((asset_value_in_collateral_asset.sub(position.collateral.amount))* 10**PRICE_PRECISION).div(discounted_price);
            TransferHelper.safeTransfer(position.asset.token, msg.sender, refund_asset_amount);
        } else {
            return_collateral_amount = asset_value_in_collateral_asset;
        }
        uint256 liquidated_asset_amount = asset_amount.sub(refund_asset_amount);
        uint256 left_asset_amount = position.asset.amount.sub(liquidated_asset_amount);
        uint256 left_collateral_amount = position.collateral.amount.sub(return_collateral_amount);

        address position_owner = position.owner;
        address collateral_token = position.collateral.token;
        if (left_collateral_amount == 0) {
            _itmap_remove(_position_idx);
        } else if (left_asset_amount == 0) {
            _itmap_remove(_position_idx);

            TransferHelper.safeTransfer(collateral_token, position_owner, left_collateral_amount);

        } else {
            position.collateral.amount = left_collateral_amount;
            position.asset.amount = left_asset_amount;
        }
        token.burn(liquidated_asset_amount, msg.sender);

        uint256 protocol_fee = CommonPlatformLib.UintDecimalMul(
                return_collateral_amount, config.protocol_fee_rate,
                PROTOCOL_FEE_RATE_PRECISION);
        return_collateral_amount = return_collateral_amount.sub(protocol_fee);
        TransferHelper.safeTransfer(collateral_token, msg.sender, return_collateral_amount);
        if (protocol_fee > 0) {
            TransferHelper.safeTransfer(collateral_token, config.collector, protocol_fee);
        }
        emit auction( _position_idx, position_owner, return_collateral_amount,
            liquidated_asset_amount, protocol_fee);
    }

    function LoadPrice(PriceQueryInfo memory info) internal view returns (uint256) {
        if (info.base_end_price != 0 && info.quote_end_price != 0) {
            return
                CommonPlatformLib.UintDecimalDiv(
                    info.base_end_price,
                    info.quote_end_price,
                    PRICE_PRECISION
                );
        } else if (info.base_end_price != 0) {
            uint256 quote_price = 1 * 10**PRICE_PRECISION;
            if (config.usdt_denom != info.quote_asset) {
                quote_price = QueryPrice(config.usdt_denom, info.quote_asset, info.block_time);
            }
            return
                CommonPlatformLib.UintDecimalDiv(
                    info.base_end_price,
                    quote_price,
                    PRICE_PRECISION
                );
        } else if (info.quote_end_price != 0) {
            uint256 base_price = 1 * 10**PRICE_PRECISION;
            if (config.usdt_denom != info.base_asset) {
                base_price = QueryPrice(config.usdt_denom, info.base_asset, info.block_time);
            }
            return
                CommonPlatformLib.UintDecimalDiv(
                    base_price,
                    info.quote_end_price,
                    PRICE_PRECISION
                );
        }
        return QueryPrice(info.base_asset, info.quote_asset, info.block_time);
    }

    function QueryPrice(address base_asset, address quote_asset, uint256 block_time) internal view returns (uint256) {
        Oracle oracleHandler = Oracle(config.oracle);
        Oracle.PriceResponse memory res = oracleHandler.QueryUsdtPrice(base_asset, quote_asset);
        if (block_time > 0) {
            require( res.last_update_base >= (block_time - price_expire_time) &&
                    res.last_update_quote >= (block_time - price_expire_time),
                "Price is too old");
        }
        return res.rate;
    }

    function QueryPlatformPrice(address base_asset, address quote_asset, uint256 block_time) internal view returns (uint256) {
        Oracle oracleHandler = Oracle(config.oracle);
        Oracle.PriceResponse memory res = oracleHandler.QueryPlatformPrice(base_asset, quote_asset);
        if (block_time > 0) {
            require( res.last_update_base >= (block_time - price_expire_time) &&
                    res.last_update_quote >= (block_time - price_expire_time),
                "Price is too old");
        }
        return res.rate;
    }

    function QueryConfig() external view returns (Config memory) {
        return config;
    }

    function QueryPlatformAssetConfig(address _asset_token) external view returns (AssetConfig memory) {
        return asset_platform_config[_asset_token];
    }

    function QueryUsdtAssetConfig(address _asset_token) external view returns (AssetConfig memory) {
        return asset_usdt_config[_asset_token];
    }

    function QueryPosition(uint256 _position_idx) external view returns (Position memory) {
        return positions.data[_position_idx].value;
    }

    function QueryPositions(uint256 _start_after, uint256 _limit, bool _isAsc) external
        view returns (Position[] memory positions_response, uint256 len) {
        if (_limit == 0) {
            return (positions_response , len);
        }
        uint256 limit = _limit;
        if (limit > MAX_LIMIT) {
            limit = MAX_LIMIT;
        }
        positions_response = new Position[](limit);
        len = 0;
        uint256 keyindex = 1; 
        if (_start_after != 0) {
            if (!_itmap_contains(_start_after) ) {
                return (positions_response , len);
            }
            keyindex = _itmap_keyindex(_start_after);
        }
        if (_isAsc) {
            if (_start_after != 0) {
                keyindex++;
            }
            if (keyindex >= position_idx) {
                return (positions_response, len);
            }
            if (_itmap_delete(keyindex)) {
                keyindex = _itmap_iterate_next(keyindex);
            }
            for ( uint256 i = keyindex; _itmap_iterate_valid(i) && (len < limit);
                i = _itmap_iterate_next(i)) {
                positions_response[len++] = _itmap_iterate_get(i);
            }
        } else {
            if (_start_after == 0) {
                keyindex = _itmap_keyindex(position_idx - 1);
            } else {
                if (keyindex <= 1) {
                    return (positions_response, len);
                }
                keyindex--;
            } 
            if (_itmap_delete(keyindex)) {
                keyindex = _itmap_iterate_prev(keyindex);
            }
            for (uint256 i = keyindex; _itmap_iterate_valid(i) && (len < limit);
                i = _itmap_iterate_prev(i)) {
                positions_response[len++] = _itmap_iterate_get(i);
            }
        }
    }

    function QueryUserPositions(address _user, uint256 _start_after, uint256 _limit, bool _isAsc) external
        view returns ( Position[] memory positions_response, uint256 len) {
        if (_limit == 0) {
            return (positions_response , len);
        }
        uint256 limit = _limit;
        if (limit > MAX_LIMIT) {
            limit = MAX_LIMIT;
        }
        positions_response = new Position[](limit);
        len = 0;
        uint256[] storage user_positions = positions.indexUser[_user];
        if (_start_after > 0 && !_itmap_contains(_start_after)) {
            return (positions_response, len);
        }
        uint256 subIndex = _itmap_userKeyindex(_start_after);
        if (_start_after > 0) {
            if (subIndex == 0) {
                return (positions_response, len);
            }
            subIndex--;
        }
        if (_isAsc) {
            if (_start_after != 0) {
                subIndex++;
            }
            for (uint256 i = subIndex; (i < user_positions.length) && (len < limit);
                i++) {
                if (_itmap_delete(_itmap_keyindex(user_positions[i]))) {
                    continue;
                }
                positions_response[len++] = positions.data[user_positions[i]].value;
            }
        } else {
            if (_start_after == 0) {
                subIndex = user_positions.length;
            }
            int256 index = int256(subIndex);
            index--;
            for (int256 i = index; (i >= 0) && (len < limit); i--) {
                if (_itmap_delete(_itmap_keyindex(user_positions[uint256(i)]))) {
                    continue;
                }
                positions_response[len++] = positions.data[user_positions[uint256(i)]].value;
            }
        }
    }

    function QueryAssetPositions(address _asset, uint256 _start_after, uint256 _limit, bool _isAsc)
        external view returns ( Position[] memory positions_response, uint256 len) {
        if (_limit == 0) {
            return (positions_response , len);
        }
        uint256 limit = _limit;
        if (limit > MAX_LIMIT) {
            limit = MAX_LIMIT;
        }
        positions_response = new Position[](limit);
        len = 0;
        uint256[] storage asset_positions = positions.indexAsset[_asset];
        if (_start_after > 0 && !_itmap_contains(_start_after)) {
            return (positions_response, len);
        }
        uint256 subIndex = _itmap_assetKeyindex(_start_after);
        if (_start_after > 0) {
            if (subIndex == 0) { 
                return (positions_response, len);
            }
            subIndex--;
        }
        if (_isAsc) {
            if (_start_after != 0) {
                subIndex++;
            }
            for ( uint256 i = subIndex; (i < asset_positions.length) && (len < limit);
                i++) {
                if (_itmap_delete(_itmap_keyindex(asset_positions[i]))) {
                    continue;
                }
                positions_response[len++] = positions.data[asset_positions[i]].value;
            }
        } else {
            if (_start_after == 0) {
                subIndex = asset_positions.length;
            }
            int256 index = int256(subIndex);
            index--;
            for (int256 i = index; (i >= 0) && (len < limit); i--) {
                if (_itmap_delete(_itmap_keyindex(asset_positions[uint256(i)]))) {
                    continue;
                }
                positions_response[len++] = positions.data[asset_positions[uint256(i)]].value;
            }
        }
   }

    function _itmap_insert_or_update(uint256 key, Position memory value) internal returns (bool) {
        uint256 keyIndex = positions.data[key].keyIndex;
        positions.data[key].value = value;
        if (keyIndex > 0) return false;

        positions.keys.push(KeyFlag({key: key, deleted: false}));
        positions.data[key].keyIndex = positions.keys.length;
        positions.indexAsset[value.asset.token].push(key);
        positions.data[key].assetKeyIndex = positions.indexAsset[value.asset.token].length;
        positions.indexUser[value.owner].push(key);
        positions.data[key].userKeyIndex = positions.indexUser[value.owner].length;
        positions.size++;
        return true;
    }

    function _itmap_remove(uint256 key) internal returns (bool) {
        uint256 keyIndex = positions.data[key].keyIndex;
        require(keyIndex > 0, "_itmap_remove internal error");
        if (positions.keys[keyIndex - 1].deleted) return false;
        delete positions.data[key].value;
        positions.keys[keyIndex - 1].deleted = true;
        positions.size--;
        return true;
    }

    function _itmap_contains(uint256 key) internal view returns (bool) {
        return positions.data[key].keyIndex > 0;
    }

    function _itmap_keyindex(uint256 key) internal view returns (uint256) {
        return positions.data[key].keyIndex;
    }

    function _itmap_userKeyindex(uint256 key) internal view returns (uint256) {
        return positions.data[key].userKeyIndex;
    }

    function _itmap_assetKeyindex(uint256 key) internal view returns (uint256) {
        return positions.data[key].assetKeyIndex;
    }

    function _itmap_delete(uint256 keyIndex) internal view returns (bool) {
        if (keyIndex == 0) {
            return true;
        }
        return positions.keys[keyIndex-1].deleted;
    }

    function _itmap_iterate_valid(uint256 keyIndex) internal view returns (bool) {
        return keyIndex != 0 && keyIndex <= positions.keys.length;
    }

    function _itmap_iterate_next(uint256 keyIndex) internal view returns (uint256) {
        keyIndex++;
        while (
            keyIndex < positions.keys.length && positions.keys[keyIndex-1].deleted
        ) keyIndex++;
        return keyIndex;
    }

    function _itmap_iterate_prev(uint256 keyIndex) internal view returns (uint256) {
        if (keyIndex > positions.keys.length || keyIndex == 0) return positions.keys.length;

        keyIndex--;
        while (keyIndex > 0 && positions.keys[keyIndex-1].deleted) keyIndex--;
        return keyIndex;
    }

    function _itmap_iterate_get(uint256 keyIndex) internal view returns (Position storage value) {
        value = positions.data[positions.keys[keyIndex-1].key].value;
    }
}
