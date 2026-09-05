# JDCloud RE-CS-02 QCN9074 board data

This recipe runs only for `lk_ipq60xx_libwrt`,
`lk_ipq60xx_libwrt_mini`, and `lk_ipq60xx_libwrt_docker_only`.

It downloads the API2 BDF from OpenWrt's `firmware_qca-wireless` commit
`e20f4c6ff197823762319e4b7e31af01816503cf`, verifies its SHA-256, extracts
bytes 104 through 131175 as the raw API1 `board.bin`, then verifies the
result before `make defconfig` discovers the package.

Source BDF SHA-256:

```
c5d006900011acbd5444d160e72485b3be037e1359dadf8c536e038db7100455
```

Installed `board.bin` SHA-256:

```
717a0b2f45812261fd43ffa71285cb3cae40cdd1973b6f2df4d2687e623f5373
```
