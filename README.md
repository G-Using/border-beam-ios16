# BorderBeam for iOS 15 / 16

作者：**G-Using**
基于 [ismnoiet/border-beam-ios](https://github.com/ismnoiet/border-beam-ios)（MIT）移植。

原库用 SwiftUI `colorEffect` + Metal shader，最低 iOS 17。这里把它拆成两层：

- `Sources/BorderBeam/` — UIKit + Metal Compute（`MTKView`）渲染核心，SwiftUI 侧只剩一层 `UIViewRepresentable` 包装。给需要 GPU 那套效果的 App / 组件用。
- `Sources/BorderBeamTweak/` — 越狱插件，纯 CoreAnimation（`CAGradientLayer` + 描边 mask），不依赖 Metal、不读 bundle 资源。装上去之后，任何 App 里点中输入框，边框就有一圈流动的七彩光带。

## 产物

| 文件 | 说明 |
|---|---|
| `BorderBeamTweak_1.1.0_iphoneos-arm64.deb` | 插件，无根（Dopamine / palera1n rootless） |
| `BorderBeamTweak_1.1.0_iphoneos-arm64e.deb` | 插件，隐根（RootHide / roothide） |
| `BorderBeamDemo_1.1.0_iphoneos-arm64.deb` | 示例 App，20 多种流光样式，用来对照看效果 |

两个插件包 payload 完全一致，只有 `control` 里的 `Architecture` 标签不同。插件 dylib 同时投放到两个 loader 目录：

```
var/jb/Library/MobileSubstrate/DynamicLibraries/   # ElleKit（rootless）
var/jb/usr/lib/TweakInject/                        # roothide bootstrap
```

## 安装

1. Sileo / Zebra 装 deb（Filza 也行）
2. `respring`（注入型插件，不 respring 已运行的进程里没有）
3. 打开备忘录，点一下输入框

## 排查

看不到光带时，按顺序确认：

1. **插件到底加载没有**：`log stream --predicate 'eventMessage CONTAINS "BorderBeam"'`，或看 Cr4shed / 系统日志里有没有 `[BorderBeam] dylib loaded`。
   - 没有这行 → 注入没发生（loader 目录不对 / 没 respring / 包架构标签不匹配），换另一个架构包试。
   - 有这行但没有 `[BorderBeam] attach ...` → hook 没被调用，看 `hook ... become=1` 的日志。
2. **输入框自己 `clipsToBounds`** 时，光环外扩部分会被裁掉，只剩贴着边缘的亮线 —— 这是正常的，不是没生效。
3. 部分自绘输入框（完全不用 `UITextField` / `UITextView`）不在覆盖范围内。

## 构建

GitHub Actions（`.github/workflows/build.yml`）：`xcodegen` 生成工程 → `xcodebuild` 出 App 和 dylib → `ldid` 签名 → `tools/pack_deb.py` 手工打 deb（不需要 dpkg）。每次 push 自动出包并把源码打成 zip 一起上传。

本地只要 Python 3 就能打 deb：

```sh
python3 tools/pack_deb.py --payload stage-tweak --arch iphoneos-arm64 \
  --package com.borderbeam.tweak --name BorderBeam --version 1.1.0 \
  --section Tweaks --out out/BorderBeamTweak.deb
```

## License

MIT，见 `LICENSE`。原始版权归 ismnoiet。
