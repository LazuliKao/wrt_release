#!/usr/bin/env python3
"""Validate the complete archive contract, including U-Boot header/data CRCs."""
import gzip
import pathlib
import struct
import sys
import tarfile
import zlib

bundle = pathlib.Path(sys.argv[1])
release = (bundle / 'kernel-release').read_text().strip()
with tarfile.open(bundle / f'boot-{release}.tar.gz') as archive:
    files = {m.name.removeprefix('./'): archive.extractfile(m).read()
             for m in archive.getmembers() if m.isfile()}
for name in ('vmlinuz', 'config', 'System.map', 'initrd.img', 'uInitrd'):
    assert files[f'{name}-{release}'], f'Missing boot file: {name}'
image = files[f'vmlinuz-{release}']
assert image[56:60] == b'ARM\x64', 'Image is not a raw ARM64 kernel'
data = files[f'uInitrd-{release}']
magic, hcrc, _, size, _, _, dcrc = struct.unpack('>7I', data[:28])
assert magic == 0x27051956 and len(data) == size + 64
header = data[:4] + b'\0' * 4 + data[8:64]
assert zlib.crc32(header) == hcrc, 'uInitrd header CRC mismatch'
assert zlib.crc32(data[64:]) == dcrc, 'uInitrd data CRC mismatch'
assert data[29:32] == bytes((22, 3, 1)), 'Expected ARM64 ramdisk with gzip compression'
assert data[64:] == files[f'initrd.img-{release}']
cpio = gzip.decompress(data[64:])
assert cpio[:6] == b'070701'
# Parse newc instead of accepting filenames found in incidental binary data.
offset = 0
entries = {}
while offset < len(cpio):
    assert cpio[offset:offset + 6] == b'070701'
    header = [int(cpio[offset + 6 + i * 8:offset + 14 + i * 8], 16) for i in range(13)]
    length, namesize = header[6], header[11]
    name = cpio[offset + 110:offset + 110 + namesize - 1].decode().removeprefix('./')
    start = (offset + 110 + namesize + 3) & ~3
    entries[name] = cpio[start:start + length]
    offset = (start + length + 3) & ~3
    if name == 'TRAILER!!!':
        break
assert entries['init'].startswith(b'#!/bin/sh')
assert entries['bin/busybox'][:4] == b'\x7fELF'
with tarfile.open(bundle / f'dtb-rockchip-{release}.tar.gz') as archive:
    dtb = archive.extractfile('./rk3588-bdy-g98.dtb').read()
    assert dtb[:4] == b'\xd0\x0d\xfe\xed' and b'bdy,bdy-g98\0' in dtb
with tarfile.open(bundle / f'modules-{release}.tar.gz') as archive:
    modules = [m for m in archive.getmembers() if m.isfile() and m.name.endswith('.ko')]
    assert modules
    for member in modules:
        assert member.name.startswith(f'{release}/kernel/openwrt/')
        content = archive.extractfile(member).read()
        assert b'vermagic=' + release.encode() + b' ' in content
        assert entries['lib/modules/' + member.name] == content
print(f'Validated complete local kernel bundle: {release}')
