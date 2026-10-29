#!/usr/bin/env python3
"""Fail closed on unknown Full Cone implementations in the installed build tree."""
import hashlib
import json
import os
from pathlib import Path
import re
import sys


# Explicit legacy integration paths. Their contents vary across source branches;
# only these paths are replaceable, never arbitrary Full Cone filename matches.
LEGACY_PATCHES = (
    "package/network/config/firewall4/patches/001-firewall4-add-support-for-fullcone-nat.patch",
    "package/network/config/firewall/patches/fullconenat.patch",
    "package/libs/libnftnl/patches/001-libnftnl-add-fullcone-expression-support.patch",
    "package/network/utils/nftables/patches/002-nftables-add-fullcone-expression-support.patch",
)
# Known providers (ponwrt and kenzok8/small-package). Keep the source available;
# disable its outputs instead of deleting whole feed/package directories.
LEGACY_PROVIDERS = {
    "d5760441fd792264bfab59211250f8a315bb456d24a67ad270cbb41face2a051":
        {"kmod-ipt-fullconenat", "iptables-mod-fullconenat", "ip6tables-mod-fullconenat"},
    "d73a977915db8fff9b6635b33e648675fb078dea46e8bd5021eb2ff5484d4588":
        {"kmod-ipt-fullconenat", "iptables-mod-fullconenat", "ip6tables-mod-fullconenat"},
    "a6a53ab39130be53b3492e85d87c6519dbe1467c4ce982d4abe893728ae13b37":
        {"kmod-nft-fullcone"},
}
# Reviewed MTK plugin: writes nf_conntrack_nat_mode at startup and pulls the old
# xt_FULLCONENAT module. Disable the management plugin, not HNAT kernel drivers.
MTK_PROVIDER = "78b181dd79326000eb7080e69ad045a2664d9b290214fe453b8b2eb57b65d7b4"
OLD_OUTPUTS = {"kmod-ipt-fullconenat", "iptables-mod-fullconenat",
               "ip6tables-mod-fullconenat", "kmod-nft-fullcone"}
MTK_OUTPUTS = {"luci-app-turboacc-mtk", "luci-i18n-turboacc-mtk-zh-cn"}
# qwe-qaq/luci-app natmode 0.1.6 loads nft_fullcone and controls the old global
# firewall switches. Disable this reviewed manager rather than porting its UI.
LEGACY_MANAGERS = {
    MTK_PROVIDER: MTK_OUTPUTS,
    "323c663e869e1854aae53842fda66941f2fb92511ecfbf2d55709af1f1890aa7":
        {"luci-app-natmode"},
}
FULLCONE = re.compile(r"full[\s_-]*cone|nf_conntrack_nat_mode", re.I)
STATE = ".sonic-fullcone-state.json"


def fail(message):
    raise RuntimeError(message)


def log(message):
    print("sonic_fullcone: " + message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def text(path):
    return path.read_text(errors="replace")


def files(directory):
    # Follow installed package/feeds links, but deduplicate real directories.
    # Uninstalled feeds are not part of this scan.
    seen = set()
    for base, dirs, names in os.walk(directory, followlinks=True):
        real = Path(base).resolve()
        if real in seen:
            dirs[:] = []
            continue
        seen.add(real)
        dirs[:] = sorted(d for d in dirs if d not in {".git", ".svn"})
        for name in sorted(names):
            yield Path(base) / name


def selected(root):
    config = root / ".config"
    if not config.is_file():
        fail("缺少 .config，不能检查实际选包")
    return set(re.findall(r"^CONFIG_PACKAGE_(.+)=[ym]$", text(config), re.M))


def package_names(makefile):
    contents = text(makefile)
    names = {("kmod-" if kind == "KernelPackage" else "") + name
             for kind, name in re.findall(
                 r"^define\s+(Package|KernelPackage)/([\w.+-]+)\s*$", contents, re.M)}
    if "luci.mk" in contents:
        names.add(makefile.parent.name)
    return names


def makefile_conflict(content):
    # Descriptions, titles and comments mentioning Full Cone are not evidence
    # of an implementation. Inspect actual dependency and build/install fields.
    content = "\n".join(line.split("#", 1)[0] for line in content.splitlines())
    content = re.sub(r"\\\n\s*", " ", content)
    for field in re.findall(
        r"^\s*(?:LUCI_DEPENDS|DEPENDS|PKG_BUILD_DEPENDS|PKG_BUILD_DEPENDS_HOST)\s*[:+?]?=(.*)$",
        content, re.M,
    ):
        for token in re.findall(r"[\w.+/-]+", field):
            name = token.lstrip("+").removesuffix("/host")
            if (name in OLD_OUTPUTS or name in {"fullconenat", "fullconenat-nft"}
                    or name.startswith(("kmod-", "iptables-mod-", "ip6tables-mod-"))
                    and FULLCONE.search(name)):
                return "旧 Full Cone 依赖: " + name
    for line in content.splitlines():
        if re.match(r"\s*(?:FILES|AUTOLOAD|KCONFIG|PKG_SOURCE_URL)\s*[:+?]?=", line) or re.match(r"\t", line):
            if re.search(r"(?:xt_FULLCONENAT|nft_fullcone|libip[6t]*_FULLCONENAT|netfilter-full-cone-nat|nft-fullcone\.git)", line):
                return "旧 Full Cone 模块/安装逻辑: " + line.strip()
    return None


def package_scan(root, active):
    providers = {}
    installed = list(files(root / "package"))
    for path in installed:
        if path.name != "Makefile":
            continue
        names = package_names(path)
        content = text(path)
        # These two exact dependency edges belong to the reviewed fw3/fw4
        # integration. Other Full Cone dependencies remain an error.
        for rel, dependency in (
            ("package/network/config/firewall4/Makefile", "kmod-nft-fullcone"),
            ("package/network/config/firewall/Makefile", "iptables-mod-fullconenat"),
        ):
            if path == root / rel:
                content = re.sub(r"\+" + re.escape(dependency) + r"(?=\s|$)", "", content)
        sha = digest(path)
        known = LEGACY_PROVIDERS.get(sha)
        manager = LEGACY_MANAGERS.get(sha)
        if manager and path.parent.name in manager:
            known = manager
        if known:
            providers[path.parent] = known
            log(f"已识别旧实现包: {path.relative_to(root)}")
        elif names & OLD_OUTPUTS:
            fail(f"未识别的 Full Cone 包/依赖: {path.relative_to(root)} (sha256={sha})")
        elif names & active:
            conflict = makefile_conflict(content)
            if conflict:
                fail(f"未识别的 Full Cone 包/依赖: {path.relative_to(root)}: {conflict} (sha256={sha})")
    for path in installed:
        if path.name == "Makefile" or "patches" in path.parts or not path.is_file():
            continue
        parents = [p for p in path.parents if (p / "Makefile").is_file()]
        if not parents or parents[0] in providers:
            continue
        makefile = parents[0] / "Makefile"
        if not package_names(makefile) & active:
            continue
        # Old module loaders and Broadcom/MTK NAT mode writers may live outside
        # package Makefiles. Translation strings and help text are not loaders.
        if path.suffix in {".po", ".pot", ".md", ".patch", ".diff"}:
            continue
        runtime = "\n".join(line for line in text(path).splitlines()
                            if not line.lstrip().startswith(("#", "//")))
        if re.search(
            r"(?:>|\btee\s+)[^\n;&|]*nf_conntrack_nat_mode"
            r"|\bsysctl\b[^\n;&|]*nf_conntrack_nat_mode\s*="
            r"|(?:modprobe|insmod)[^\n;&|]*?(?:xt_FULLCONENAT|nft_fullcone)"
            r"|-j\s+FULLCONENAT", runtime,
        ):
            fail(f"选中的包包含旧 Full Cone 运行时逻辑: {path.relative_to(root)}")
    return installed, providers


def upstream_outputs(root):
    paths = []
    versions = list((root / "include").glob("kernel-[0-9]*"))
    if not versions:
        versions = list((root / "target/linux/generic").glob("kernel-[0-9]*"))
    for version in versions:
        directory = root / "target/linux/generic" / ("hack-" + version.name[len("kernel-"):])
        if directory.is_dir():
            paths.extend(directory / name for name in (
                "984-add-sonic-fullcone-support.patch", "985-add-sonic-fullcone-to-ipt.patch",
                "986-add-sonic-fullcone-to-nft.patch"))
    if not paths:
        fail("没有可安装 SONiC 补丁的内核 hack 目录")
    for package, patch in (
        ("package/network/config/firewall4", "001-sonic-fullcone.patch"),
        ("package/network/config/firewall", "001-sonic-fullcone.patch"),
        ("package/network/utils/iptables", "901-sonic-fullcone.patch"),
        ("package/libs/libnftnl", "001-libnftnl-add-fullcone-expression-support.patch"),
        ("package/network/utils/nftables", "002-nftables-add-fullcone-expression-support.patch"),
        ("feeds/luci/applications/luci-app-firewall", "001-add-fullcone-options.patch"),
    ):
        if (root / package).is_dir():
            paths.append(root / package / "patches" / patch)
    return paths


def patch_conflict(contents):
    # Inspect the resulting code in each hunk, marking which lines are added.
    # Removed text, patch descriptions and filenames do not implement anything.
    chunks = []
    lines = []
    added = []
    filename = ""
    in_hunk = False

    def flush():
        if lines:
            chunks.append((filename, "\n".join(lines), added[:]))
            lines.clear()
            added.clear()

    for line in contents.splitlines():
        if line.startswith("+++ "):
            flush()
            filename = line[4:].split("\t", 1)[0]
            in_hunk = False
        elif line.startswith("@@ "):
            flush()
            in_hunk = True
        elif in_hunk and line[:1] in {" ", "+"}:
            lines.append(line[1:])
            added.append(line.startswith("+"))
        elif in_hunk and not line.startswith(("-", "\\")):
            flush()
            in_hunk = False
    flush()
    # Keep newline positions while removing literals/comments so a log message
    # mentioning full-cone cannot masquerade as a kernel/module implementation.
    literals = re.compile(r'/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'', re.S)
    for filename, code, additions in chunks:
        name = Path(filename).name
        if (Path(filename).suffix.lower() in {".md", ".rst", ".txt", ".po", ".pot"}
                or name.startswith(("README", "INSTALL", "CHANGELOG", "COPYING"))):
            continue
        blank = lambda m: re.sub(r"[^\n]", " ", m.group())
        cleaned = literals.sub(blank, code)
        uncommented = literals.sub(
            lambda m: blank(m) if m.group().startswith(("/*", "//")) else m.group(), code)
        for raw, stripped, command, is_added in zip(
            code.split("\n"), cleaned.split("\n"), uncommented.split("\n"), additions,
        ):
            if not is_added or re.match(r"\s*(?://|\*(?:\s|/))", raw):
                continue
            if raw.lstrip().startswith("#") and not re.match(
                r"\s*#\s*(?:define|if|ifdef|ifndef|elif|include|undef|error|pragma)\b", raw,
            ):
                continue
            # Module loaders and nft expression registration use string literals
            # as operational arguments; these remain concrete conflict evidence.
            operational = re.search(
                r"(?:^|[;&|])\s*(?:modprobe|insmod)\s+['\"]?(?:xt_FULLCONENAT|nft_fullcone)\b"
                r"|\.name\s*=\s*\"fullcone\"", command)
            if FULLCONE.search(stripped) or operational:
                return f"{filename}: {raw.strip()}"
    return None


def patch_scan(root, installed, active, trusted, allow_legacy):
    core = {root / p for p in (
        "package/network/config/firewall", "package/network/config/firewall4",
        "package/network/utils/iptables", "package/network/utils/nftables",
        "package/libs/libnftnl")}
    # All kernel patches of generic + the selected board, not unrelated boards.
    config = text(root / ".config")
    boards = [root / "target/linux/generic"]
    for board in (root / "target/linux").glob("*"):
        if (f"CONFIG_TARGET_{board.name.replace('-', '_')}=y" in config
                or f'CONFIG_TARGET_BOARD="{board.name}"' in config):
            boards.append(board)
    paths = [p for board in boards for p in files(board)]
    for path in installed:
        if "patches" not in path.parts:
            continue
        parents = [p for p in path.parents if (p / "Makefile").is_file()]
        if parents and digest(parents[0] / "Makefile") in {*LEGACY_PROVIDERS, *LEGACY_MANAGERS}:
            # All outputs of these providers are disabled, so their private
            # kernel-compatibility patches will not participate in the build.
            continue
        names = package_names(parents[0] / "Makefile") if parents else set()
        if parents and (parents[0] in core or names & active):
            paths.append(path)
    # Upstream patches LuCI's feed directly; its installed link may be absent.
    paths.extend(files(root / "feeds/luci/applications/luci-app-firewall/patches"))
    for path in paths:
        if not path.is_file() or path.suffix not in {".patch", ".diff"}:
            continue
        rel = path.relative_to(root).as_posix()
        sha = digest(path)
        # Resolve package/feeds aliases when checking the installer manifest.
        expected = trusted.get(str(path.resolve()))
        if expected == sha:
            continue
        if allow_legacy and rel in LEGACY_PATCHES:
            continue
        conflict = patch_conflict(text(path))
        if conflict:
            fail(f"未识别或已改动的 Full Cone 补丁: {rel}: {conflict} (sha256={sha})")


def load_state(root):
    path = root / STATE
    return json.loads(text(path)) if path.is_file() else {"patches": {}}


def trusted_patches(root, state):
    return {str((root / rel).resolve()): sha for rel, sha in state["patches"].items()}


def preflight(root):
    upstream_outputs(root)
    active = selected(root)
    installed, _ = package_scan(root, active)
    patch_scan(root, installed, active, trusted_patches(root, load_state(root)), True)
    log("安装前检查通过")


def replace(root):
    # Require replacements before removing the two reviewed firewall patches.
    for rel in LEGACY_PATCHES[:2]:
        path = root / rel
        if not path.exists():
            continue
        replacement = path.with_name("001-sonic-fullcone.patch")
        if not replacement.is_file() or not replacement.stat().st_size:
            fail(f"缺少替代补丁，保留旧文件: {rel}")
        path.unlink()
        log(f"已替换旧补丁: {rel}")
    for rel, dependency in (
        ("package/network/config/firewall4", "kmod-nft-fullcone"),
        ("package/network/config/firewall", "iptables-mod-fullconenat"),
    ):
        makefile = root / rel / "Makefile"
        if makefile.is_file():
            replacement = makefile.parent / "patches/001-sonic-fullcone.patch"
            if not replacement.is_file() or not replacement.stat().st_size:
                fail(f"缺少替代补丁: {replacement.relative_to(root)}")
            content = text(makefile)
            content = re.sub(r"\+" + re.escape(dependency) + r"(?=\s|$)", "", content)
            makefile.write_text(content)
    active = selected(root)
    _, providers = package_scan(root, active)
    disabled = set(OLD_OUTPUTS)
    for outputs in providers.values():
        if outputs in LEGACY_MANAGERS.values():
            disabled.update(outputs)
            # LuCI translation packages can be generated for multiple languages.
            for name in outputs:
                if name.startswith("luci-app-"):
                    prefix = "luci-i18n-" + name[len("luci-app-"):] + "-"
                    disabled.update(p for p in active if p.startswith(prefix))
    config = root / ".config"
    lines = text(config).splitlines()
    lines = [line for line in lines if not any(
        line.startswith(f"CONFIG_PACKAGE_{p}=") or line == f"# CONFIG_PACKAGE_{p} is not set"
        for p in disabled)]
    lines.extend(f"# CONFIG_PACKAGE_{p} is not set" for p in sorted(disabled))
    config.write_text("\n".join(lines) + "\n")
    log("关闭旧选包: " + ", ".join(sorted(disabled)))
    # Trust only exact upstream output paths written by the one-click installer.
    patches = {}
    for path in upstream_outputs(root):
        rel = path.relative_to(root).as_posix()
        if not path.is_file() or not path.stat().st_size:
            fail(f"上游缺少必须安装的替代补丁: {rel}")
        sha = digest(path)
        patches[rel] = sha
    state = {"patches": patches}
    (root / STATE).write_text(json.dumps(state, indent=2) + "\n")
    # Catch remaining unknown patches after removal, including in selected packages.
    installed, _ = package_scan(root, selected(root))
    patch_scan(root, installed, selected(root), trusted_patches(root, state), False)


if __name__ == "__main__":
    try:
        mode, directory = sys.argv[1:]
        {"preflight": preflight, "replace": replace}[mode](Path(directory).resolve())
    except (RuntimeError, OSError, ValueError, KeyError) as error:
        print(f"sonic_fullcone: ERROR: {error}", file=sys.stderr)
        sys.exit(1)
