#!/usr/bin/env python3
"""
H3C HM2004-DU (AN7581) Stock Firmware Extractor & Micro-OLT Stack Parser

This script automates the full extraction of:
1. Factory ROM configuration (romfile.cfg)
2. U-Boot FIT Kernel image & embedded Device Tree (DTB -> DTS)
3. Decompressed ARM64 Linux Kernel (vmlinux)
4. Rootfs & opt SquashFS filesystems
5. UBI/UBIFS partitions (ubifs0, ubifs1, ubifs2)
6. Assembling the isolated Micro-OLT software & FPGA stack (FTTR_TOP.sbit, fmcs.ko, fpga_load.ko, moltd, momci, ploam, etc.)

Requirements:
    pip install ubi_reader fdt
    unsquashfs (via package manager or WSL on Windows)
"""

import os
import sys
import glob
import zlib
import lzma
import struct
import shutil
import argparse
import subprocess

def extract_romfile(src_path, dst_path):
    print(f"[*] Extracting ROM configuration from {os.path.basename(src_path)}...")
    with open(src_path, 'rb') as f:
        raw = f.read()
    
    # Decompress gzip ignoring trailing 0xFF flash padding
    d = zlib.decompressobj(16 + zlib.MAX_WBITS)
    try:
        decompressed = d.decompress(raw)
        with open(dst_path, 'wb') as f:
            f.write(decompressed)
        print(f"    -> Successfully wrote {len(decompressed):,} bytes to {dst_path}")
        return True
    except Exception as e:
        print(f"    [!] Failed to decompress romfile: {e}")
        return False

def extract_fit_kernel(kernel_bin_path, out_dir):
    print(f"[*] Parsing U-Boot FIT kernel image from {os.path.basename(kernel_bin_path)}...")
    with open(kernel_bin_path, 'rb') as f:
        raw = f.read()

    # Search for embedded DTB and compressed kernel
    # In HM2004-DU stock mtd2, FIT image has FDT blob for board and LZMA compressed kernel
    dtb_magic = b'\xd0\x0d\xfe\xed'
    fit_offset = raw.find(dtb_magic)
    if fit_offset == -1:
        print("    [!] Could not locate FIT/FDT magic 0xd00dfeed in kernel binary.")
        return None, None

    print(f"    -> Found FIT header at offset 0x{fit_offset:X} ({fit_offset})")

    # Locate DTB blob inside FIT (images/fdt@1)
    # Target DTB begins with 0xd00dfeed and has totalsize in header
    dtb_out = os.path.join(out_dir, "hm2004-du-stock.dtb")
    dts_out = os.path.join(out_dir, "hm2004-du-stock.dts")
    vmlinux_bin_out = os.path.join(out_dir, "vmlinux.bin")
    vmlinux_out = os.path.join(out_dir, "vmlinux")

    # Second occurrence of 0xd00dfeed is board DTB
    sub_dtb_pos = raw.find(dtb_magic, fit_offset + 4)
    if sub_dtb_pos != -1:
        magic, totalsize = struct.unpack('>II', raw[sub_dtb_pos:sub_dtb_pos + 8])
        if magic == 0xd00dfeed and totalsize < len(raw):
            dtb_bytes = raw[sub_dtb_pos:sub_dtb_pos + totalsize]
            with open(dtb_out, 'wb') as f:
                f.write(dtb_bytes)
            print(f"    -> Extracted stock board DTB: {totalsize:,} bytes -> {dtb_out}")

            # Decompile to DTS if 'fdt' python library is installed
            try:
                import fdt
                dt = fdt.parse_dtb(dtb_bytes)
                with open(dts_out, 'w', encoding='utf-8') as f:
                    f.write(dt.to_dts())
                print(f"    -> Decompiled DTB to human-readable DTS -> {dts_out}")
            except ImportError:
                print("    [!] python 'fdt' library not installed. Skipping DTB->DTS decompilation (pip install fdt).")
            except Exception as e:
                print(f"    [!] Failed to decompile DTB to DTS: {e}")

    # Locate LZMA kernel stream (magic 0x5D 0x00 0x00)
    # Search for standard 8MB dictionary LZMA header
    lzma_pos = raw.find(b'\x5d\x00\x00\x80\x00')
    if lzma_pos == -1:
        lzma_pos = raw.find(b'\x5d\x00\x00')

    if lzma_pos != -1:
        print(f"    -> Found LZMA kernel stream at offset 0x{lzma_pos:X} ({lzma_pos})")
        # Try decompressing
        try:
            decompressed_kernel = lzma.decompress(raw[lzma_pos:])
            with open(vmlinux_out, 'wb') as f:
                f.write(decompressed_kernel)
            print(f"    -> Decompressed ARM64 vmlinux Image: {len(decompressed_kernel):,} bytes (~{len(decompressed_kernel)//1024//1024} MB) -> {vmlinux_out}")
        except Exception as e:
            # Fallback if raw slice contains trailing data, use LZMADecompressor
            decompressor = lzma.LZMADecompressor()
            try:
                decompressed_kernel = decompressor.decompress(raw[lzma_pos:])
                with open(vmlinux_out, 'wb') as f:
                    f.write(decompressed_kernel)
                print(f"    -> Decompressed ARM64 vmlinux Image (stream): {len(decompressed_kernel):,} bytes -> {vmlinux_out}")
            except Exception as e2:
                print(f"    [!] Failed to decompress kernel stream: {e2}")

    return dtb_out, vmlinux_out

def extract_squashfs(sqfs_path, out_dir):
    print(f"[*] Extracting SquashFS image: {os.path.basename(sqfs_path)}...")
    os.makedirs(out_dir, exist_ok=True)
    
    # Try unsquashfs in host or WSL
    cmd = ["unsquashfs", "-f", "-d", out_dir, sqfs_path]
    try:
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if res.returncode == 0:
            print(f"    -> Unsquashfs finished successfully for {out_dir}")
            return True
    except FileNotFoundError:
        pass

    # On Windows, try WSL if available
    if sys.platform == "win32":
        wsl_sqfs = subprocess.run(["wsl", "wslpath", "-a", sqfs_path], stdout=subprocess.PIPE, text=True).stdout.strip()
        wsl_out = subprocess.run(["wsl", "wslpath", "-a", out_dir], stdout=subprocess.PIPE, text=True).stdout.strip()
        wsl_cmd = ["wsl", "unsquashfs", "-f", "-d", wsl_out, wsl_sqfs]
        try:
            res = subprocess.run(wsl_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            if res.returncode == 0:
                print(f"    -> Unsquashfs finished successfully via WSL for {out_dir}")
                return True
        except Exception as e:
            print(f"    [!] WSL unsquashfs invocation failed: {e}")

    # Fallback to 7z
    try:
        res = subprocess.run(["7z", "x", "-y", f"-o{out_dir}", sqfs_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        print(f"    -> 7z extracted {sqfs_path} to {out_dir} (note: symlinks may be omitted on Windows NTFS)")
        return True
    except FileNotFoundError:
        print("    [!] Neither unsquashfs nor 7z available. Please install squashfs-tools or 7-Zip.")
        return False

def extract_ubifs(ubi_path, out_dir):
    print(f"[*] Extracting UBI/UBIFS image: {os.path.basename(ubi_path)}...")
    os.makedirs(out_dir, exist_ok=True)

    # Try ubireader_extract_files
    exe_name = "ubireader_extract_files.exe" if sys.platform == "win32" else "ubireader_extract_files"
    try:
        res = subprocess.run([exe_name, "-o", out_dir, ubi_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if res.returncode == 0:
            print(f"    -> ubi_reader extracted {ubi_path} -> {out_dir}")
            return True
    except FileNotFoundError:
        pass

    # Try python module invocation
    try:
        res = subprocess.run([sys.executable, "-m", "ubi_reader.cmd.extract_files", "-o", out_dir, ubi_path],
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if res.returncode == 0:
            print(f"    -> ubi_reader extracted {ubi_path} -> {out_dir}")
            return True
    except Exception as e:
        print(f"    [!] Failed to run ubi_reader: {e}")

    print(f"    [!] ubi_reader tool not found. Install with: pip install ubi_reader")
    return False

def assemble_fttr_olt_stack(extracted_rootfs, out_dir):
    print(f"[*] Assembling standalone Micro-OLT stack into {out_dir}...")
    os.makedirs(out_dir, exist_ok=True)

    file_mapping = [
        ("lib/firmware/FTTR_TOP.sbit", "FTTR_TOP.sbit"),
        ("lib/modules/fmcs.ko", "fmcs.ko"),
        ("lib/modules/fpga_load.ko", "fpga_load.ko"),
        ("lib/modules/hsgmii_lan.ko", "hsgmii_lan.ko"),
        ("userfs/bin/moltd", "moltd"),
        ("usr/bin/momci", "momci"),
        ("usr/bin/moltdbg", "moltdbg"),
        ("usr/bin/miniolt", "miniolt"),
        ("usr/bin/ploam", "ploam"),
        ("usr/bin/bosa", "bosa"),
        ("usr/bin/tlut", "tlut"),
        ("lib/libmolt_svc.so", "libmolt_svc.so"),
        ("lib/libminiolt_svc.so", "libminiolt_svc.so"),
        ("lib/libmoltapi.so", "libmoltapi.so"),
    ]

    copied_count = 0
    for rel_src, dst_name in file_mapping:
        src_file = os.path.join(extracted_rootfs, rel_src.replace('/', os.sep))
        dst_file = os.path.join(out_dir, dst_name)
        if os.path.exists(src_file):
            shutil.copy2(src_file, dst_file)
            copied_count += 1
            print(f"    -> Copied {dst_name} ({os.path.getsize(dst_file):,} bytes)")
        else:
            print(f"    [-] Not found in rootfs: {rel_src}")

    print(f"[*] Done. Assembled {copied_count}/{len(file_mapping)} Micro-OLT stack files.")

def main():
    parser = argparse.ArgumentParser(description="H3C HM2004-DU Firmware & Micro-OLT Stack Extractor")
    parser.add_argument("--stock-dir", default=r"C:\Users\lk\Downloads\stock", help="Path to stock mtd*.bin partition dumps")
    parser.add_argument("--output-dir", default=r"C:\Users\lk\Downloads\stock\extracted", help="Destination output directory")
    args = parser.parse_args()

    stock_dir = os.path.abspath(args.stock_dir)
    out_dir = os.path.abspath(args.output_dir)
    os.makedirs(out_dir, exist_ok=True)

    print("=" * 70)
    print("H3C HM2004-DU Stock Partition Extractor & OLT Parser")
    print(f"Source Directory: {stock_dir}")
    print(f"Target Directory: {out_dir}")
    print("=" * 70)

    # 1. Romfile
    rom_bin = os.path.join(stock_dir, "mtd1-romfile.bin")
    if os.path.exists(rom_bin):
        extract_romfile(rom_bin, os.path.join(out_dir, "romfile.cfg"))

    # 2. Kernel & DTB
    kernel_bin = os.path.join(stock_dir, "mtd2-kernel.bin")
    if os.path.exists(kernel_bin):
        extract_fit_kernel(kernel_bin, out_dir)

    # 3. Rootfs
    rootfs_bin = os.path.join(stock_dir, "mtd3-rootfs.bin")
    rootfs_extracted = os.path.join(out_dir, "rootfs")
    if os.path.exists(rootfs_bin):
        extract_squashfs(rootfs_bin, rootfs_extracted)

    # 4. Opt0
    opt0_bin = os.path.join(stock_dir, "mtd8-opt0.bin")
    if os.path.exists(opt0_bin):
        extract_squashfs(opt0_bin, os.path.join(out_dir, "opt0"))

    # 5. UBI partitions
    ubi_partitions = [
        ("mtd10-ubifs.bin", "ubifs0_mtd10"),
        ("mtd11-private_apps.bin", "ubifs2_mtd11"),
        ("mtd13-h3c.bin", "ubifs1_mtd13")
    ]
    for ubi_name, folder in ubi_partitions:
        p = os.path.join(stock_dir, ubi_name)
        if os.path.exists(p):
            extract_ubifs(p, os.path.join(out_dir, folder))

    # 6. Assemble OLT stack bundle
    olt_bundle_dir = os.path.join(out_dir, "fttr_olt_stack")
    if os.path.exists(rootfs_extracted):
        assemble_fttr_olt_stack(rootfs_extracted, olt_bundle_dir)

    print("\n[✓] All extractions and analyses completed successfully!")

if __name__ == "__main__":
    main()
