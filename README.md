# OpenWrt 编译脚本

- ## 本分支的差异：
  - 内置更多好用的软件包。
  - 使用 nginx，默认端口 80，不生成证书。
  - 终端使用 zsh，主题使用[`ohmyzsh`](https://ohmyz.sh/)。
  - 预装[`nbtverify`](https://github.com/nbtca/luci-app-nbtverify)（某校园网认证）。
  - 使用`docker(compose)`+[`immortalwrt sdk`](https://hub.docker.com/r/immortalwrt/sdk)一键编译，本地编译 99%无障碍。
  - 固件内置 docker 和 docker compose。

---

# Compile Using Docker 
- (docker compose)

```bash
docker compose up
```
- (docker command) 

```bash
docker run --rm -it \
  -v "$(pwd)":/build \
  -w /build \
  immortalwrt/sdk:mediatek-filogic-openwrt-24.10 \
  bash build.sh cudy_tr3000
docker run --rm -it \
  -v "$(pwd)":/build \
  -w /build \
  immortalwrt/sdk:mediatek-filogic-openwrt-24.10 \
  bash build.sh cudy_tr3000-5.4
```
# Compile Using Windows HyperV (ubuntu 22.04):

create vm use https://github.com/nbtca/hyperv-ubuntu-provisioning

创建参考：

```ps1
.\New-HyperVCloudImageVM.ps1 -VMProcessorCount 16 -VMMemoryStartupBytes 6GB -VMMinimumBytes 6GB -VMMaximumBytes 16GB -VHDSizeBytes 128GB -VMName "openwrt-development-1" -ImageVersion "22.04" -VMGeneration 2 -KeyboardLayout en -GuestAdminUsername lk -GuestAdminPassword lk233 -VMDynamicMemoryEnabled $true -VirtualSwitchName WAN -Verbose -ImageTypeAzure $true -VMMachine_StoragePath "F:\hyper-v" -ShowSerialConsoleWindow
```

## 然后参考[这里](#原编译过程)进行编译。

# 编译过程

首先安装 Linux 系统，推荐 Ubuntu LTS

安装编译依赖  
sudo apt -y update  
sudo apt -y full-upgrade  
sudo apt install -y dos2unix libfuse-dev  
sudo bash -c 'bash <(curl -sL https://build-scripts.immortalwrt.org/init_build_environment.sh)'

使用步骤：  
git clone https://github.com/ZqinKing/wrt_release.git  
cd wrt_relese

编译京东云雅典娜(02)、亚瑟(01)、太乙(07)、AX5(JDC 版):  
./build.sh jdcloud_ipq60xx_immwrt  
./build.sh jdcloud_ipq60xx_libwrt

编译京东云百里:  
./build.sh jdcloud_ax6000_immwrt

编译阿里云 AP8220:  
./build.sh aliyun_ap8220_immwrt

编译红米 AX5:  
./build.sh redmi_ax5_immwrt

编译红米 AX6:  
./build.sh redmi_ax6_immwrt

编译红米 AX6000:  
./build.sh redmi_ax6000_immwrt21

编译 CMCC RAX3000M:  
./build.sh cmcc_rax3000m_immwrt

编译 N1:  
./build.sh n1_immwrt

编译 X64:  
./build.sh x64_immwrt

编译兆能 M2:  
./build.sh zn_m2_immwrt  
./build.sh zn_m2_libwrt

三方插件源自：https://github.com/kenzok8/small-package.git
以及：https://github.com/sirpdboy/sirpdboy-package

使用 OAF（应用过滤）功能前，需先完成以下操作：

1. 打开系统设置 → 启动项 → 定位到「appfilter」
2. 将「appfilter」当前状态**从已禁用更改为已启用**
3. 完成配置后，点击**启动**按钮激活服务
