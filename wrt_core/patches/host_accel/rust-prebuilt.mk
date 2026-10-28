# Keep source download metadata and all original methods available for fallback.
# DUMP/download parsing must not require a built C toolchain or change package metadata.
ifeq ($(DUMP)$(filter download refresh,$(MAKECMDGOALS)),)
  WRT_RUST_VERIFIED := $(shell PATH="$(if $(TARGET_PATH_PKG),$(TARGET_PATH_PKG),$(PATH))" bash "$(WRT_ACCEL_SCRIPT)" rust-probe "$(WRT_RUST_ROOT)" "$(RUSTC_TARGET_ARCH)" "$(TARGET_CC_NOCACHE)" "$(CARGO_RUSTFLAGS)" && echo y)
  ifeq ($(WRT_RUST_VERIFIED),y)
    $(info [host-accel] Rust: target link verified; using $(WRT_RUST_ROOT))

    define Host/Prepare
    endef

    define Host/Configure
    endef

    define Host/Compile
	"$(WRT_RUST_ROOT)/bin/rustc" --version
    endef

    define Host/Install
	$(INSTALL_DIR) $(STAGING_DIR)/host/bin
	$(foreach tool,cargo rustc rustdoc,ln -sfn "$(WRT_RUST_ROOT)/bin/$(tool)" "$(STAGING_DIR)/host/bin/$(tool)";)
    endef

    define Host/Uninstall
	$(foreach tool,cargo rustc rustdoc,if [ "$$$$(readlink "$(STAGING_DIR)/host/bin/$(tool)")" = "$(WRT_RUST_ROOT)/bin/$(tool)" ]; then rm -f "$(STAGING_DIR)/host/bin/$(tool)"; fi;)
    endef
  else
    $(info [host-accel] Rust: prebuilt target validation unavailable/failed; using original source rules)
    WRT_RUST_FALLBACK := $(shell bash "$(WRT_ACCEL_SCRIPT)" rust-source "$(TOPDIR)" >&2)
  endif
endif
