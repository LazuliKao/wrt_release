# Vantage 主题

默认禁用。要为某个目标启用 Vantage 默认主题，在其 `wrt_core/compilecfg/<target>.ini` 中加入或合并以下设置：

```ini
ADD_RECIPES=default_theme_vantage
DISABLE_RECIPES=default_theme_argon
```

如果该目标启用了 `default_theme_fluent`，也要将其加入 `DISABLE_RECIPES`。`default_theme_vantage` 自动依赖 `luci_theme_vantage`，后者导入主题和 dashboard，启用对应软件包，并应用 Bootstrap 配置迁移补丁。其他主题包可以继续安装；迁移仅在 Bootstrap 资源缺失且 Vantage 资源完整时生效。
