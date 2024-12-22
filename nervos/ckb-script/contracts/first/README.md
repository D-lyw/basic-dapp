
```bash
Devnet/Testnet test account: // from offckb cli generated account
- "#": 0
address: ckt1qzda0cr08m85hc8jlnfp3zer7xulejywt49kt2rr0vthywaa50xwsqvwg2cen8extgq8s5puft8vf40px3f599cytcyd8
privkey: 0x6109170b275a09ad54877b82f7d9930f88cab5717d484fb4741ae9d1dd078cd6
pubkey: 0x02025fa7b61b2365aa459807b84df065f1949d58c0ae590ff22dd2595157bffefa
lock_arg: 0x8e42b1999f265a0078503c4acec4d5e134534297
lockScript:
    codeHash: 0x9bd7e06f3ecf4be0f2fcd2188b23f1b9fcc88e5d4b65a8637b17723bbda3cce8
    hashType: type
    args: 0x8e42b1999f265a0078503c4acec4d5e134534297
```

deploy first contract to testnet

```bash
offckb deploy --target ./build/release/first --privkey 0x6109170b275a09ad54877b82f7d9930f88cab5717d484fb4741ae9d1dd078cd6 --network testnet
```

```toml
// deployment.toml
[[cells]]
name = "first"
enable_type_id = false

[cells.location]
file = "/Users/d-lyw/D-lyw/basic-dapp/nervos/ckb-script/build/release/first"

[lock]
code_hash = "0x9bd7e06f3ecf4be0f2fcd2188b23f1b9fcc88e5d4b65a8637b17723bbda3cce8"
args = "0x8e42b1999f265a0078503c4acec4d5e134534297"
hash_type = "type"
```