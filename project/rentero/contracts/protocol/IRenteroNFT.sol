interface IRenteroNFT {

    /**
    *更新租借者事件，如果borrower 为空则为不继续租借回归到出租人手里
    */
    event UpdateBorrow(uint256 indexed tokenId, address indexed borrower);

    /**
    * 设置租借者
    */
    function setBorrower(uint256 tokenId, address borrower) external ;

    /**
    * 查询nft的对应租借者
    */
    function borrowerOf(uint256 tokenId) external view returns(address);

    /**
    * 查询租借者所有的nft
    */
    function tokenListOf(address  borrower) external view returns(uint256[] memory);
}