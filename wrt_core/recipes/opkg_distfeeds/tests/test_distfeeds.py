#!/usr/bin/env python3
"""Behavior checks for repository generation; requires Bash and GNU make."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


RECIPE = Path(__file__).resolve().parents[1]
ROOT = RECIPE.parents[2]
HASH_A = "a" * 32
HASH_B = "b" * 32
HASH_C = "c" * 32
NJU = "https://mirror.nju.edu.cn/immortalwrt"


class DistfeedsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="distfeeds-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.build = self.base / "source"
        self.ini = self.base / "target.ini"
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.write(".config", 'CONFIG_TARGET_BOARD="airoha"\n'
                   'CONFIG_TARGET_SUBTARGET="an7581"\n'
                   'CONFIG_TARGET_ARCH_PACKAGES="aarch64_cortex-a53"\n'
                   'CONFIG_USE_APK=y\n')
        # Small native Makefile fixture: the query must evaluate overrides,
        # rather than scrape KERNEL_PATCHVER or inspect old build directories.
        self.write("rules.mk", 'INCLUDE_DIR := $(TOPDIR)/include\n'
                   'include $(TOPDIR)/.config\n'
                   'BOARD := $(subst ",,$(CONFIG_TARGET_BOARD))\n'
                   'SUBTARGET := $(subst ",,$(CONFIG_TARGET_SUBTARGET))\n')
        self.write("include/kernel.mk", 'include $(TOPDIR)/target/linux/$(BOARD)/Makefile\n'
                   '-include $(TOPDIR)/target/linux/$(BOARD)/$(SUBTARGET)/target.mk\n'
                   'ifdef CONFIG_TESTING_KERNEL\n'
                   'KERNEL_PATCHVER := $(KERNEL_TESTING_PATCHVER)\nendif\n'
                   'include $(TOPDIR)/target/linux/generic/kernel-$(KERNEL_PATCHVER)\n'
                   'LINUX_VERSION := $(KERNEL_PATCHVER)$(LINUX_VERSION-$(KERNEL_PATCHVER))\n')
        self.write("target/linux/airoha/Makefile", "KERNEL_PATCHVER := 6.12\n")
        self.write("target/linux/generic/kernel-6.12", "LINUX_VERSION-6.12 = .77\n")
        self.write("target/linux/generic/kernel-6.18", "LINUX_VERSION-6.18 = .55\n")
        self.write("include/kernel-defaults.mk", "\tgrep '=[ym]' $(LINUX_DIR)/.config.set | "
                   "LC_ALL=C sort | $(MKHASH) md5 > $(LINUX_DIR)/.vermagic\n")
        self.write("package/kernel/linux/Makefile", "  STAMP_BUILT:=$(STAMP_BUILT)_$(shell hash-config)\n")
        self.write("package/emortal/default-settings/Makefile",
                   "define Package/default-settings/install\nendef\n")
        self.write("package/emortal/default-settings/files/99-default-settings", "#!/bin/sh\nexit 0\n")
        self.write("package/base-files/files/etc/uci-defaults/99-kmod-distfeeds.sh", "old opkg hook\n")
        self.listing = self.base / "listing.html"
        self.links(f"6.12.77-1-{HASH_A}")
        curl = self.bin / "curl"
        curl.write_text('#!/usr/bin/env bash\n'
                        'printf "%s\\n" "${@: -1}" >> "$DISTFEEDS_TEST_BASE/fetches"\n'
                        '[ "${DISTFEEDS_FETCH_FAIL:-0}" != 1 ] || exit 22\n'
                        'cat "$DISTFEEDS_TEST_BASE/listing.html"\n')
        curl.chmod(0o755)
        self.env = dict(os.environ, BUILD_DIR=str(self.build), TARGET_INI=str(self.ini),
                        RECIPE_DIR=str(RECIPE), BASE_PATH=str(ROOT / "wrt_core"),
                        DISTFEEDS_TEST_BASE=str(self.base),
                        NETWORK_RETRY_MAX="1",
                        PATH=str(self.bin) + os.pathsep + os.environ["PATH"])
        self.settings(OPKG_DISTFEEDS_CHANNEL="snapshots")

    def write(self, relative, text):
        path = self.build / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def settings(self, **kwargs):
        self.ini.write_text("".join(f"{key}={value}\n" for key, value in kwargs.items()))

    def links(self, *directories):
        self.listing.write_text(" ".join(f'<a href="{d}/">{d}</a>' for d in directories))

    def run_bash(self, script, check=True):
        result = subprocess.run(["bash", "-euo", "pipefail", "-c", script], env=self.env,
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if check:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def apply(self, check=True):
        return self.run_bash('bash "$RECIPE_DIR/apply.sh"', check=check)

    def content(self, apk=True):
        name = "99-distfeeds.list" if apk else "99-distfeeds.conf"
        return (self.build / "package/emortal/default-settings/files" / name).read_text()

    def assert_hash(self, expected):
        for name in ("include/kernel-defaults.mk", "package/kernel/linux/Makefile"):
            self.assertIn(expected, (self.build / name).read_text())

    def test_both_ponwrt_configs_use_snapshot_and_one_abi(self):
        for target in ("lk_an7581_ponwrt_mini", "lk_h3c_hm2004_du"):
            with self.subTest(target=target):
                self.env["TARGET_INI"] = str(ROOT / "wrt_core/compilecfg" / f"{target}.ini")
                self.apply()
                lines = self.content().splitlines()
                self.assertEqual(len(lines), 7)
                prefix = NJU + "/snapshots"
                self.assertEqual(lines[0], prefix + "/targets/airoha/an7581/packages/packages.adb")
                self.assertEqual(lines[1], prefix + f"/targets/airoha/an7581/kmods/6.12.77-1-{HASH_A}/packages.adb")
                self.assertEqual(lines[2:], [prefix + f"/packages/aarch64_cortex-a53/{feed}/packages.adb"
                                           for feed in ("base", "luci", "packages", "routing", "telephony")])
                self.assert_hash(HASH_A)
                self.assertFalse((self.build / "package/base-files/files/etc/uci-defaults/99-kmod-distfeeds.sh").exists())
        self.assertEqual(len((self.base / "fetches").read_text().splitlines()), 2)
        startup = (self.build / "package/emortal/default-settings/files/99-default-settings").read_text()
        self.assertEqual(startup.count("/etc/apk/repositories.d/distfeeds.list"), 1)

    def test_exact_version_and_numeric_highest_revision(self):
        self.links(f"6.18.55-99-{HASH_C}", f"6.12.77-2-{HASH_A}",
                   f"6.12.77-10-{HASH_B}", f"6.12.770-100-{HASH_C}")
        self.apply()
        self.assert_hash(HASH_B)
        self.assertIn(f"6.12.77-10-{HASH_B}/packages.adb", self.content())
        self.assertNotIn(HASH_A, self.content())
        self.assertNotIn(HASH_C, self.content())

    def test_ambiguous_highest_revision_is_skipped(self):
        self.links(f"6.12.77-2-{HASH_A}", f"6.12.77-10-{HASH_B}", f"6.12.77-10-{HASH_C}")
        self.apply()
        self.assertEqual(len(self.content().splitlines()), 6)
        self.assertNotIn("/kmods/", self.content())
        self.assertNotIn("echo ", (self.build / "include/kernel-defaults.mk").read_text())

    def test_no_matching_version_is_skipped(self):
        self.links(f"6.12.80-1-{HASH_A}", f"6.18.55-1-{HASH_B}")
        self.apply()
        self.assertNotIn("/kmods/", self.content())
        self.assertNotIn(HASH_A, (self.build / "include/kernel-defaults.mk").read_text())

    def test_unknown_full_version_and_network_failure_are_skipped(self):
        self.write("include/kernel.mk", "LINUX_VERSION := 6.12\n")
        self.apply()
        self.assertFalse((self.base / "fetches").exists())
        self.assertNotIn("/kmods/", self.content())
        self.write("include/kernel.mk", "LINUX_VERSION := 6.12.77\n")
        self.env["DISTFEEDS_FETCH_FAIL"] = "1"
        self.apply()
        self.assertNotIn("/kmods/", self.content())

    def test_subtarget_and_testing_kernel_are_evaluated(self):
        for extra in ("", "CONFIG_TESTING_KERNEL=y\n"):
            with self.subTest(testing=bool(extra)):
                self.write("target/linux/airoha/an7581/target.mk",
                           "KERNEL_PATCHVER := 6.18\n" if not extra else
                           "KERNEL_PATCHVER := 6.12\nKERNEL_TESTING_PATCHVER := 6.18\n")
                config = self.build / ".config"
                config.write_text(config.read_text() + extra)
                self.links(f"6.12.77-10-{HASH_A}", f"6.18.55-1-{HASH_B}")
                self.apply()
                self.assert_hash(HASH_B)

    def test_target_symbols_without_string_metadata(self):
        config = self.build / ".config"
        config.write_text('CONFIG_TARGET_airoha=y\nCONFIG_TARGET_airoha_an7581=y\n'
                          'CONFIG_TARGET_airoha_an7581_DEVICE_h3c_hm2004=y\nCONFIG_USE_APK=y\n')
        self.apply()
        self.assertIn("/targets/airoha/an7581/kmods/6.12.77-1-", self.content())
        self.assert_hash(HASH_A)

    def test_explicit_release_and_custom_mirror_cover_all_feeds(self):
        self.settings(OPKG_DISTFEEDS_VERSION="25.12.2", OPKG_DISTFEEDS_MIRROR="https://mirror.test/immortalwrt/")
        self.apply()
        for line in self.content().splitlines():
            self.assertTrue(line.startswith("https://mirror.test/immortalwrt/releases/25.12.2/"))

    def test_release_compatibility(self):
        for branch, version in (("v25.12.2", "25.12.2"), ("25.12", "25.12.2"),
                                ("25.12-nss", "25.12.2"), ("openwrt-24.10-6.6", "24.10.6"),
                                ("main", "25.12.2"), ("openwrt-21.02", "21.02")):
            with self.subTest(branch=branch):
                self.settings(REPO_BRANCH=branch)
                self.apply()
                self.assertIn(f"/releases/{version}/", self.content())

    def test_mirror_presets(self):
        for preset, mirror in (("official", "https://downloads.immortalwrt.org"),
                               ("ustc", "https://mirrors.ustc.edu.cn/immortalwrt"), ("nju", NJU)):
            with self.subTest(preset=preset):
                self.settings(OPKG_DISTFEEDS=preset, OPKG_DISTFEEDS_CHANNEL="snapshots")
                self.apply()
                self.assertTrue(all(line.startswith(mirror + "/snapshots/") for line in self.content().splitlines()))

    def test_opkg_contains_kmod_in_same_file_and_no_legacy_hook(self):
        config = self.build / ".config"
        config.write_text(config.read_text().replace("CONFIG_USE_APK=y\n", ""))
        self.settings(REPO_BRANCH="openwrt-24.10-6.6")
        self.apply()
        self.assertIn(f"src/gz kmod {NJU}/releases/24.10.6/targets/airoha/an7581/kmods/6.12.77-1-{HASH_A}", self.content(apk=False))
        self.assertNotIn("packages.adb", self.content(apk=False))
        self.assert_hash(HASH_A)

    def test_manual_hash_filters_discovery(self):
        self.settings(KERNEL_VERMAGIC=HASH_A)
        self.links(f"6.12.77-1-{HASH_A}", f"6.12.77-10-{HASH_B}")
        self.apply()
        self.assert_hash(HASH_A)
        self.assertIn(f"6.12.77-1-{HASH_A}", self.content())

    def test_manual_hash_without_match_remains_authoritative(self):
        self.settings(KERNEL_VERMAGIC=HASH_B)
        self.apply()
        self.assert_hash(HASH_B)
        self.assertNotIn("/kmods/", self.content())

    def test_explicit_modules_and_conflicting_hash(self):
        url = f"https://downloads.immortalwrt.org/snapshots/targets/airoha/an7581/kmods/6.12.77-2-{HASH_B}/packages.adb"
        self.settings(KERNEL_MODULES=url, OPKG_DISTFEEDS="official")
        self.apply()
        self.assert_hash(HASH_B)
        self.assertIn(url, self.content())
        self.assertFalse((self.base / "fetches").exists())
        self.settings(KERNEL_MODULES=url, KERNEL_VERMAGIC=HASH_C)
        self.assertNotEqual(self.apply(check=False).returncode, 0)

    def test_raw_custom_feeds(self):
        self.settings(OPKG_DISTFEEDS="src/gz custom https://packages.test/custom,https://packages.test/second/packages.adb")
        self.apply()
        self.assertIn("https://packages.test/custom/packages.adb\n", self.content())
        self.assertIn("https://packages.test/second/packages.adb\n", self.content())
        self.assertNotIn("packages.adb/packages.adb", self.content())

    def test_invalid_channel_fails(self):
        self.settings(OPKG_DISTFEEDS_CHANNEL="snapshot-typo")
        self.assertNotEqual(self.apply(check=False).returncode, 0)

    def test_recipe_sets_and_schema_have_no_removed_recipe(self):
        sets = ROOT / "wrt_core/recipe_sets"
        for name in ("mini", "full", "barebone", "docker_only"):
            recipes = json.loads((sets / f"{name}.json").read_text())["recipes"]
            self.assertEqual(recipes.count("opkg_distfeeds"), 1)
            self.assertNotIn("fix_kernel_magic", recipes)
        schema = (sets / "recipe_set.schema.json").read_text()
        json.loads(schema)
        self.assertNotIn('"fix_kernel_magic"', schema)
        recipe = json.loads((RECIPE / "recipe.json").read_text())
        self.assertEqual(recipe["phase"], "post_defconfig")
        self.assertEqual(recipe["depends"], [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
