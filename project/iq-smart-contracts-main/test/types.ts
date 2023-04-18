export enum Errors { //todo: sync with contracts
  // common errors
  NOT_INITIALIZED = '1',
  ALREADY_INITIALIZED = '2',
  CALLER_NOT_OWNER = '3',
  CALLER_NOT_ENTERPRISE = '4',
  INVALID_ADDRESS = '5',
  UNREGISTERED_POWER_TOKEN = '6',
  INVALID_ARRAY_LENGTH = '7',

  // contract specific errors
  EXP_INVALID_PERIOD = '8',

  ERC20_INVALID_PERIOD = '9',
  ERC20_TRANSFER_AMOUNT_EXCEEDS_ALLOWANCE = '10',
  ERC20_DECREASED_ALLOWANCE_BELOW_ZERO = '11',
  ERC20_TRANSFER_FROM_THE_ZERO_ADDRESS = '12',
  ERC20_TRANSFER_TO_THE_ZERO_ADDRESS = '13',
  ERC20_TRANSFER_AMOUNT_EXCEEDS_BALANCE = '14',
  ERC20_MINT_TO_THE_ZERO_ADDRESS = '15',
  ERC20_BURN_FROM_THE_ZERO_ADDRESS = '16',
  ERC20_BURN_AMOUNT_EXCEEDS_BALANCE = '17',
  ERC20_APPROVE_FROM_THE_ZERO_ADDRESS = '18',
  ERC20_APPROVE_TO_THE_ZERO_ADDRESS = '19',

  ERC721_BALANCE_QUERY_FOR_THE_ZERO_ADDRESS = '20',
  ERC721_OWNER_QUERY_FOR_NONEXISTENT_TOKEN = '21',
  ERC721_APPROVAL_TO_CURRENT_OWNER = '22',
  ERC721_APPROVE_CALLER_IS_NOT_OWNER_NOR_APPROVED_FOR_ALL = '23',
  ERC721_APPROVED_QUERY_FOR_NONEXISTENT_TOKEN = '24',
  ERC721_APPROVE_TO_CALLER = '25',
  ERC721_TRANSFER_CALLER_IS_NOT_OWNER_NOR_APPROVED = '26',
  ERC721_TRANSFER_TO_NON_ERC721RECEIVER_IMPLEMENTER = '27',
  ERC721_OPERATOR_QUERY_FOR_NONEXISTENT_TOKEN = '28',
  ERC721_MINT_TO_THE_ZERO_ADDRESS = '29',
  ERC721_TOKEN_ALREADY_MINTED = '30',
  ERC721_TRANSFER_OF_TOKEN_THAT_IS_NOT_OWN = '31',
  ERC721_TRANSFER_TO_THE_ZERO_ADDRESS = '32',

  ERC721META_URI_QUERY_FOR_NONEXISTENT_TOKEN = '33',

  ERC721ENUM_OWNER_INDEX_OUT_OF_BOUNDS = '34',
  ERC721ENUM_GLOBAL_INDEX_OUT_OF_BOUNDS = '35',

  DC_UNSUPPORTED_PAIR = '36',

  DE_INVALID_ENTERPRISE_ADDRESS = '37',
  DE_LABMDA_NOT_GT_0 = '38',

  E_CALLER_NOT_RENTAL_TOKEN = '39',
  E_INVALID_BASE_TOKEN_ADDRESS = '40',
  E_SERVICE_LIMIT_REACHED = '41',
  E_INVALID_RENTAL_PERIOD_RANGE = '42',
  E_SERVICE_ENERGY_GAP_HALVING_PERIOD_NOT_GT_0 = '43',
  E_UNSUPPORTED_PAYMENT_TOKEN = '44',
  E_RENTAL_PERIOD_OUT_OF_RANGE = '45',
  E_INSUFFICIENT_LIQUIDITY = '46',
  E_RENTAL_PAYMENT_SLIPPAGE = '47',
  E_INVALID_RENTAL_TOKEN_ID = '48',
  E_INVALID_RENTAL_PERIOD = '49',
  E_FLASH_LIQUIDITY_REMOVAL = '50',
  E_SWAPPING_DISABLED = '51',
  E_RENTAL_TRANSFER_NOT_ALLOWED = '52',
  E_INVALID_CALLER_WITHIN_RENTER_ONLY_RETURN_PERIOD = '53',
  E_INVALID_CALLER_WITHIN_ENTERPRISE_ONLY_COLLECTION_PERIOD = '54',

  EF_INVALID_ENTERPRISE_IMPLEMENTATION_ADDRESS = '55',
  EF_INVALID_POWER_TOKEN_IMPLEMENTATION_ADDRESS = '56',
  EF_INVALID_STAKE_TOKEN_IMPLEMENTATION_ADDRESS = '57',
  EF_INVALID_RENTAL_TOKEN_IMPLEMENTATION_ADDRESS = '58',

  EO_INVALID_ENTERPRISE_ADDRESS = '59',

  ES_INVALID_ESTIMATOR_ADDRESS = '60',
  ES_INVALID_COLLECTOR_ADDRESS = '61',
  ES_INVALID_WALLET_ADDRESS = '62',
  ES_INVALID_CONVERTER_ADDRESS = '63',
  ES_INVALID_RENTER_ONLY_RETURN_PERIOD = '64',
  ES_INVALID_ENTERPRISE_ONLY_COLLECTION_PERIOD = '65',
  ES_STREAMING_RESERVE_HALVING_PERIOD_NOT_GT_0 = '66',
  ES_MAX_SERVICE_FEE_PERCENT_EXCEEDED = '67',
  ES_INVALID_BASE_TOKEN_ADDRESS = '68',
  ES_INVALID_RENTAL_PERIOD_RANGE = '69',
  ES_SWAPPING_ALREADY_ENABLED = '70',
  ES_INVALID_PAYMENT_TOKEN_ADDRESS = '71',
  ES_UNREGISTERED_PAYMENT_TOKEN = '72',

  IO_INVALID_OWNER_ADDRESS = '73',

  PT_INSUFFICIENT_AVAILABLE_BALANCE = '74',

  E_ENTERPRISE_SHUTDOWN = '75',
  E_INVALID_RENTAL_AMOUNT = '76',
  ES_INVALID_BONDING_POLE = '77',
  ES_INVALID_BONDING_SLOPE = '78',
  ES_TRANSFER_ALREADY_ENABLED = '79',
  PT_TRANSFER_DISABLED = '80',
  E_INVALID_ENTERPRISE_NAME = '81',
  PT_INVALID_MAX_RENTAL_PERIOD = '82',
  E_INVALID_ENTERPRISE_FACTORY_ADDRESS = '83',
}

export enum StakeOperation {
  Reward,
  Stake,
  Unstake,
  Increase,
  Decrease,
}