# BorderBeam for iOS 15 / 16

作者：**G-Using**
基于 [ismnoiet/border-beam-ios](https://github.com/ismnoiet/border-beam-ios)（MIT）移植。

原库用 SwiftUI `colorEffect` + Metal shader，最低 iOS 17。这里把它拆成两层：

- `Sources/BorderBeam/` — UIKit + Metal Compute（`MTKView`）渲染核心，SwiftUI 侧只剩一层 `UIViewRepresentable` 包装。给需要 GPU 那套效果的 App / 组件用。
- `Sources/BorderBeamTweak/` — 越狱插件，纯 CoreAnimation（`CAGradientLayer` + 描边 mask），不依赖 Metal、不读 bundle 资源。装上去之后，任何 App 里点中输入框，边框就有一圈流动的七彩光带。

## 产物

| 文件 | 说明 |
|---|---|
| `BorderBeamTweak_1.1.1_iphoneos-arm64.deb` | 插件，无根（Dopamine / palera1n rootless） |
| `BorderBeamTweak_1.1.1_iphoneos-arm64e.deb` | 插件，隐根（RootHide / roothide） |
| `BorderBeamDemo_1.1.1_iphoneos-arm64.deb` | 示例 App，20 多种流光样式，用来对照看效果 |

两个插件包 payload 完全一致，只有 `control` 里的 `Architecture` 标签不同。安装位置只有一个：

```
var/jb/Library/MobileSubstrate/DynamicLibraries/
```

> v1.1.0 曾同时投放到 `var/jb/usr/lib/TweakInject/`，在 roothide 上因该目录不存在导致
> dpkg 解包失败（`unable to open .../xxx.dylib.dpkg-new`）。v1.1.1 已回退，只装标准路径。

## 安装

1. Sileo / Zebra 装 deb（Filza 也行）
2. `respring`（注入型插件，不 respring 已运行的进程里没有）
3. 打开备忘录，点一下输入框

从旧版升级时如果 dpkg 报错中断过，先清理：

```sh
dpkg -P com.borderbeam.tweak
```

## 排查

看不到光带时，按顺序确认：

1. **插件到底加载没有**：`log stream --predicate 'eventMessage CONTAINS "BorderBeam"'`，或看 Cr4shed / 系统日志。
   - 没有 `[BorderBeam] dylib loaded` → 注入没发生（loader 目录不对 / 没 respring / 包架构标签不匹配）。
   - 有 `dylib loaded` 但没有 `[BorderBeam] attach ...` → hook 没被调用，看 `hook ... become=1` 那几行。
   - 有 `attach` 但屏幕上没有 → 输入框自己 `clipsToBounds` 把光环裁了。
2. **输入框自己 `clipsToBounds`** 时光环外扩部分会被裁掉，只剩贴着边缘的亮线——这是正常的。
3. 完全自绘输入框（不用 `UITextField` / `UITextView`）不在覆盖范围内。

## 构建

GitHub Actions（`.github/workflows/build.yml`）：`xcodegen` 生成工程 → `xcodebuild` 出 App 和 dylib → `ldid` 签名 → `tools/pack_deb.py` 手工打 deb（不需要 dpkg）。每次 push 自动出包并把源码打成 zip 一起上传。

构建期会断言：dylib 是 arm64、`_borderBeam_init` 存在、**入口构造器存在**（没入口 = 加载了也什么都不做）、不依赖 Metal/MetalKit。

本地只要 Python 3 就能打 deb：

```sh
python3 tools/pack_deb.py --payload stage-tweak --arch iphoneos-arm64 \
  --package com.borderbeam.tweak --name BorderBeam --version 1.1.1 \
  --section Tweaks --out out/BorderBeamTweak.deb
```

## License

MIT，见 `LICENSE`。原始版权归 ismnoiet。
