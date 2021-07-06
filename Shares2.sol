// SPDX-License-Identifier: MIT
pragma solidity ^0.5.13;

contract Staking {

	constructor(address _stakingToken) public {
		erc20 = TOKEN(address(_stakingToken));
		admin = msg.sender;
		
		stakeOption[0] = StakeOption(1 minutes, 50);
		stakeOption[1] = StakeOption(2 minutes, 125);
		stakeOption[2] = StakeOption(3 minutes, 238);
	}

	using SafeMath for uint256;

	TOKEN erc20;
	address payable admin;
	uint256 public sTokenTotal;
	mapping(address => Provider) public provider;
	mapping(address => Stake[]) public stakes;
	mapping(uint8 => StakeOption) public stakeOption;

	modifier isAdmin() {
		require(admin == msg.sender, "Admin only function");
		_;
	}
	
	modifier stakeIsReady(uint256 _stakeId) {
	    Stake storage stake = stakes[msg.sender][_stakeId];
	    require(stake.unlockDate <= now, "Stake is not ready");
	    _;
	}
	
	event Deposit(address _user, uint256 _amount, uint256 _timestamp);
	event Withdraw(address _user, uint256 _amount, uint256 _timestamp);
	event ExtendedStake(address _user, uint256 _amount, uint8 _stakeOption, uint256 _timestamp);
	event StakeEndWithBonus(address _user, uint256 _bonus, uint256 _timestamp);
	event StakeEndWithPenalty(address _user, uint256 _amount, uint256 _timestamp);
	event Airdrop(address _sender, uint256 _amount, uint256 _timestamp);

	struct Stake {
		uint256 amount;
		uint32 unlockDate;
		uint8 stakeBonus;
	}
	
	struct StakeOption {
		uint32 duration;
		uint8 bonusPercent;
	}
	
	struct Provider {
		uint256 commitAmount;
		uint256 balance;
		uint256 sToken;
	}

	function depositIntoPool(uint256 _depositAmount) public {
        uint256 balanceToAdd = SafeMath.sub(_depositAmount, SafeMath.div(_depositAmount, 20));
        uint256 poolBalance = erc20.balanceOf(address(this));
		uint256 mint_sToken;
		
		if(sTokenTotal == 0 || poolBalance == 0) {
			mint_sToken = SafeMath.mul(balanceToAdd, 100000);
		} else {
            mint_sToken = SafeMath.div(SafeMath.mul(balanceToAdd, sTokenTotal), poolBalance);
        }
        
        require(erc20.transferFrom(msg.sender, address(this), _depositAmount) == true, "Transfer did not succeed, are we approved?");
        
        Provider storage user = provider[msg.sender];
        
		user.balance = SafeMath.add(user.balance, balanceToAdd);
		user.sToken = SafeMath.add(mint_sToken, user.sToken);
		
		sTokenTotal = SafeMath.add(mint_sToken, sTokenTotal);
		
		emit Deposit(msg.sender, _depositAmount, now);
	}
	
	function withdrawFromPool(uint256 _amount) public {
		Provider storage user = provider[msg.sender];
        
		uint256 availableBalance = SafeMath.sub(user.balance, user.commitAmount);
		
		require(_amount <= availableBalance, "Amount withdrawn exceeds available balance");

		uint256 amountToWithdraw = SafeMath.div(SafeMath.mul(_amount, 19), 20);
		uint256 poolBalance = erc20.balanceOf(address(this));
		uint256 amountToSend = SafeMath.div(SafeMath.mul(amountToWithdraw, SafeMath.mul(user.sToken, poolBalance)) , SafeMath.mul(user.balance, sTokenTotal));
		uint256 sTokenToRemove = SafeMath.div(SafeMath.mul(_amount, user.sToken), user.balance);

		user.sToken = SafeMath.sub(user.sToken, sTokenToRemove);
		user.balance = user.balance - _amount;
		
		sTokenTotal = SafeMath.sub(sTokenTotal, sTokenToRemove);
		
		erc20.transfer(msg.sender, amountToSend);
		
		emit Withdraw(msg.sender, _amount, now);
	}

	function extendedStake(uint256 _amount, uint8 _stakeOption) public {
		require(_stakeOption <= 2, "Invalid staking option");
		
		Provider storage user = provider[msg.sender];
		
		uint256 availableBalance = SafeMath.sub(user.balance, user.commitAmount);
		require(_amount <= availableBalance, "Stake amount exceeds available balance");
		
		uint32 unlockDate = uint32(now) + stakeOption[_stakeOption].duration;
		uint8 stakeBonus = stakeOption[_stakeOption].bonusPercent;
		
		user.commitAmount = SafeMath.add(user.commitAmount, _amount);
		stakes[msg.sender].push(Stake(_amount, unlockDate, stakeBonus));
		
		emit ExtendedStake(msg.sender, _amount, _stakeOption, now);		
	}

	function claimStake(uint256 _stakeId) public stakeIsReady(_stakeId) {
		uint256 playerStakeCount = stakes[msg.sender].length;
		require(_stakeId < playerStakeCount, "Stake Does Not Exist");
		
		Stake storage stake = stakes[msg.sender][_stakeId];
		require(stake.amount > 0, "Invalid stake amount");
		Provider storage user = provider[msg.sender];

	    // (stake.amount * (user.sToken * stake.stakeBonus)) / (100 * user.balance)
		uint256 sTokenToAdd = SafeMath.div(SafeMath.mul(stake.amount, SafeMath.mul(user.sToken, stake.stakeBonus)), SafeMath.mul(100, user.balance));
		
		// stake.amount * stake.stakeBonus / 100 
		uint256 balanceToAdd = SafeMath.div(SafeMath.mul(stake.amount, stake.stakeBonus), 100);
		
		sTokenTotal = SafeMath.add(sTokenTotal, sTokenToAdd);
		user.sToken = SafeMath.add(user.sToken, sTokenToAdd);
		user.balance = SafeMath.add(user.balance, balanceToAdd);
		user.commitAmount = SafeMath.sub(user.commitAmount, stake.amount);
		
		emit StakeEndWithBonus(msg.sender, balanceToAdd, now);

		if (playerStakeCount > 1) {
			stakes[msg.sender][_stakeId] = stakes[msg.sender][playerStakeCount - 1];
		}
		delete stakes[msg.sender][playerStakeCount - 1];
	}

	function airdrop(uint256 _amount) external {
		require(erc20.transferFrom(msg.sender, address(this), _amount) == true, "transferFrom did not succeed. Are we approved?");
		emit Airdrop(msg.sender, _amount, now);
	}

	function withdrawETH() external isAdmin {
		admin.transfer(address(this).balance);
	}

	function transferAdmin(address _newAdmin) external isAdmin {
		admin = address(uint160(_newAdmin));
	}

	function withdrawERC20(TOKEN token) public isAdmin {
		require(address(token) != address(0), "Invalid address");
		require(address(token) != address(erc20), "Cannot withdraw the staking token");
		uint256 balance = token.balanceOf(address(this));
		token.transfer(admin, balance);
	}
	
    function userBalance(address _user) public view returns(uint256) {
        Provider storage user = provider[_user];
        // user.sToken x poolBalance / sTokenTotal (where poolBalance = contract balance - dripPool)
		if(user.sToken == 0 || sTokenTotal == 0) {
			return 0;
		} else {
	        return SafeMath.div(SafeMath.mul(user.sToken, erc20.balanceOf(address(this))), sTokenTotal);
		}
    }

	function stakesOf(address _user) public view returns (uint256[3][] memory) {
		uint256 userStakeCount = stakes[_user].length;
		uint256[3][] memory data = new uint256[3][](userStakeCount);
		for (uint256 i = 0; i < userStakeCount; i++) {
			Stake memory stake = stakes[_user][i];
			data[i][0] = stake.amount;
			data[i][1] = stake.unlockDate;
			data[i][2] = stake.stakeBonus;
		}
		return (data);
	}

}

contract TOKEN {
	function balanceOf(address account) external view returns (uint256);

	function transfer(address recipient, uint256 amount) external returns (bool);

	function transferFrom(
		address sender,
		address recipient,
		uint256 amount
	) external returns (bool);
}

library SafeMath {
	function mul(uint256 a, uint256 b) internal pure returns (uint256 c) {
		if (a == 0) {
			return 0;
		}
		c = a * b;
		assert(c / a == b);
		return c;
	}

	function div(uint256 a, uint256 b) internal pure returns (uint256) {
		return a / b;
	}

	function sub(uint256 a, uint256 b) internal pure returns (uint256) {
		assert(b <= a);
		return a - b;
	}

	function add(uint256 a, uint256 b) internal pure returns (uint256 c) {
		c = a + b;
		assert(c >= a);
		return c;
	}
}