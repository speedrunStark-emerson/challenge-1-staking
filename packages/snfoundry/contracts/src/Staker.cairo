use openzeppelin_token::erc20::interface::{IERC20CamelDispatcher, IERC20CamelDispatcherTrait};
use starknet::ContractAddress;

#[starknet::interface]
pub trait IStaker<T> {
    fn execute(ref self: T);
    fn stake(ref self: T, amount: u256);
    fn withdraw(ref self: T);
    fn balances(self: @T, account: ContractAddress) -> u256;
    fn completed(self: @T) -> bool;
    fn deadline(self: @T) -> u64;
    fn example_external_contract(self: @T) -> ContractAddress;
    fn open_for_withdraw(self: @T) -> bool;
    fn eth_token_dispatcher(self: @T) -> IERC20CamelDispatcher;
    fn threshold(self: @T) -> u256;
    fn total_balance(self: @T) -> u256;
    fn time_left(self: @T) -> u64;
}

#[starknet::contract]
pub mod Staker {
    use contracts::ExampleExternalContract::{
        IExampleExternalContractDispatcher, IExampleExternalContractDispatcherTrait
    };
    use starknet::storage::Map;
    use starknet::{get_block_timestamp, get_caller_address, get_contract_address};

    use super::{ContractAddress, IStaker, IERC20CamelDispatcher, IERC20CamelDispatcherTrait};

    const THRESHOLD: u256 = 1000000000000000000;

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Stake: Stake,
    }

    #[derive(Drop, starknet::Event)]
    struct Stake {
        #[key]
        sender: ContractAddress,
        amount: u256,
    }

    #[storage]
    struct Storage {
        eth_token_dispatcher: IERC20CamelDispatcher,
        balances: Map<ContractAddress, u256>,
        deadline: u64,
        open_for_withdraw: bool,
        external_contract_address: ContractAddress,
        completed: bool,
    }

    #[constructor]
    pub fn constructor(
        ref self: ContractState,
        eth_contract: ContractAddress,
        external_contract_address: ContractAddress
    ) {
        self.eth_token_dispatcher.write(IERC20CamelDispatcher {
            contract_address: eth_contract
        });
        self.external_contract_address.write(external_contract_address);
        self.deadline.write(get_block_timestamp() + 140);
    }

    #[abi(embed_v0)]
    impl StakerImpl of IStaker<ContractState> {
        fn stake(ref self: ContractState, amount: u256) {
            self.not_completed();
            let current_time = get_block_timestamp();
            let deadline = self.deadline.read();
            assert(current_time < deadline, 9);

            let sender: ContractAddress = get_caller_address();

            self.eth_token_dispatcher
                .read()
                .transferFrom(sender, get_contract_address(), amount);

            let current_balance = self.balances.read(sender);

            self.balances.write(sender, current_balance + amount);

            self.emit(Stake { sender, amount });
        }

        fn execute(ref self: ContractState) {
            self.not_completed();

            let current_time = get_block_timestamp();
            let deadline = self.deadline.read();
            assert(current_time >= deadline, 1);

            let is_completed = self.completed.read();
            assert(!is_completed, 2);

            let staked_amount = self
                .eth_token_dispatcher
                .read()
                .balanceOf(get_contract_address());

            if staked_amount >= THRESHOLD {
                self.complete_transfer(staked_amount);
                self.completed.write(true);
            } else {
                self.open_for_withdraw.write(true);
            }
        }

        fn withdraw(ref self: ContractState) {
            self.not_completed();

            let is_withdraw_open = self.open_for_withdraw.read();
            assert(is_withdraw_open, 3);

            let sender = get_caller_address();
            let balance = self.balances.read(sender);
            assert(balance > 0, 4);

            self.balances.write(sender, 0);

            self.eth_token_dispatcher.read().transfer(sender, balance);
        }

        fn balances(self: @ContractState, account: ContractAddress) -> u256 {
            self.balances.read(account)
        }

        fn total_balance(self: @ContractState) -> u256 {
            self.eth_token_dispatcher.read().balanceOf(get_contract_address())
        }

        fn deadline(self: @ContractState) -> u64 {
            self.deadline.read()
        }

        fn threshold(self: @ContractState) -> u256 {
            THRESHOLD
        }

        fn eth_token_dispatcher(self: @ContractState) -> IERC20CamelDispatcher {
            self.eth_token_dispatcher.read()
        }

        fn open_for_withdraw(self: @ContractState) -> bool {
            self.open_for_withdraw.read()
        }

        fn example_external_contract(self: @ContractState) -> ContractAddress {
            self.external_contract_address.read()
        }

        fn completed(self: @ContractState) -> bool {
            self.completed.read()
        }

        fn time_left(self: @ContractState) -> u64 {
            let current_time = get_block_timestamp();
            let deadline = self.deadline.read();

            if current_time >= deadline {
                0
            } else {
                deadline - current_time
            }
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn complete_transfer(ref self: ContractState, amount: u256) {
            let external_contract = self.external_contract_address.read();

            self.eth_token_dispatcher
                .read()
                .approve(external_contract, amount);

            let external_dispatcher = IExampleExternalContractDispatcher {
                contract_address: external_contract
            };
            external_dispatcher.complete();
        }

        fn not_completed(ref self: ContractState) {
            let is_completed = self.completed.read();
            assert(!is_completed, 99);
        }
    }
}