# halo-contracts

# bsc main  
# https://bscscan.com/address/0x1f8ffda4d85b9f46e6b05d10fdb1f4e1b814b519#code
# address:0x1f8ffda4d85b9f46e6b05d10fdb1f4e1b814b519


1. Centralization Risk
提审的合约owner已经做多了多签处理，并且上线后会做多签处理，

2. Missing check for condition.costAmount in register()
采纳并加上0值判定

3. Missing zero-address check
官方不会刻意的设置0号地址作为验签地址，没有实际意义

4. Code with no effect
采纳并删除多余代码

5. Unused import
采纳并删除多余代码