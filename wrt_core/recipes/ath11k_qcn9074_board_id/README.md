# QCN9074 undefined board ID fix

LiBwrt commit `4cc0b3ddaee4f87cec051b83aea964d384d906ae` postdates the
v25.12.1 source baseline. This recipe forward-ports its ath11k patch without
updating the source baseline.

The patch converts the QCN9074 firmware 2.15.x undefined board-ID sentinel
from `0xffffffff` to `0xff`. This lets ath11k match the RE-CS-02 API2 BDF
entry with `qmi-board-id=255` instead of incorrectly looking up
`qmi-board-id=-1`.

The recipe only runs for `lk_ipq60xx_libwrt`, `lk_ipq60xx_libwrt_mini`, and
`lk_ipq60xx_libwrt_docker_only`.
