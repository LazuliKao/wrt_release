#!/usr/bin/env python3
"""Port the pinned LEDE G98 board description to mainline 6.12 bindings."""
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_text()

def remove_node(marker):
    global text
    start = text.index(marker)
    opening = text.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    assert text[end] == ';'
    text = text[:start] + text[end + 1:]

# LEDE's HDMI nodes use downstream/newer labels and endpoint bindings.
# This NAS description deliberately leaves display disabled on 6.12.
for marker in ('hdmi0-con {', '&hdptxphy0 {', '&hdmi0 {', '&hdmi0_out {',
               '&i2s5_8ch {', '&vop_mmu {', '&vop {'):
    remove_node(marker)
# Mainline's USBDP PHY is one provider with PHY_TYPE_USB3 arguments,
# already referenced by the inherited USB controller nodes.
for _ in range(2):
    remove_node('u3-port {')
text += '\n&uart2 {\n\tpinctrl-0 = <&uart2m0_xfer>;\n\tpinctrl-names = "default";\n\tstatus = "okay";\n};\n'
pathlib.Path(sys.argv[2]).write_text(text)
