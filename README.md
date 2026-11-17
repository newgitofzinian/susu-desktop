# 溯溯 Susu Desktop

一只住在 macOS 桌面上的墨蓝小狐狸。奶白脸、琥珀眼，尾尖有三颗相连的琥珀纹样。

当前版本：**1.2**。本地运行，无需账号、网络服务或 API Key。

![身体固定，只有尾巴动](Previews/1.2/溯溯-身体固定只摇尾巴.gif)

## 功能

- 待机时身体固定，只有尾巴轻轻摆动。
- 点击显示回应，拖动可自由摆放。
- 散步与跑步使用不同动画、帧率和移动速度。
- 桌面自由活动，可部分移出屏幕，始终保留一块可见身体。
- 透明区域点击穿透；菜单栏爪印可找回、隐藏、调整大小或退出。
- 安静模式；记住窗口位置和偏好。

这是二维桌面版。真正的三维模型和 AR 将作为后续独立升级。

## 下载与使用

在本仓库的 **Releases** 下载 `溯溯桌面版-1.2.zip`，解压后打开 `溯溯.app`。

已在 Apple Silicon Mac 上验证。当前构建脚本按本机 CPU 架构编译，部署目标为 macOS 13 或更新版本；尚未完成其他硬件与系统版本的兼容验证。发布包使用本地临时签名，未进行 Apple 公证；macOS 可能需要在“系统设置 → 隐私与安全性”允许打开。

| 操作 | 效果 |
| --- | --- |
| 单击 | 显示回应气泡，身体不弹跳 |
| 拖动 | 改变位置，可部分离屏 |
| 右键 / 菜单栏爪印 | 打开控制菜单 |
| 散步一会儿 / 跑一圈 | 分别启动慢走或跑步 |
| 自由活动 | 自动活动，以慢走为主；默认开启 |
| 安静模式 | 停止动画与走动 |
| 回到主屏幕 | 找回溯溯 |

## 从源码构建

需要 macOS、Swift 和 Apple Command Line Tools；不依赖第三方 Swift 包。

```sh
git clone https://github.com/newgitofzinian/susu-desktop.git
cd susu-desktop
zsh build.sh
open 溯溯.app
```

`build.sh` 生成本机架构的 `.app` 与压缩包。应用与安装包属于构建产物，源码仓库保留运行所需的完整素材，二进制安装包通过 Release 分发。

## 验证

```sh
swiftc -framework AppKit Sources/DesktopBounds.swift Tests/main.swift -o /tmp/susu-boundary-tests
/tmp/susu-boundary-tests

./溯溯.app/Contents/MacOS/SusuDesktop --smoke-test --preview-dir /tmp/susu-previews
```

已完成：1,836 个边界位置回归检查；本机窗口在四个角部分离屏时保留可见身体；22 帧素材加载和双向慢走、跑步绘制；透明区域鼠标判定。

1.2 的六帧待机动画共锁定 **16,623 个身体像素**，逐帧身体 RGBA 差分为 **0**。验证记录在 [body-stability.json](Art/1.2/body-stability.json) 与 [本机验证记录](Previews/1.2/验证记录.json)。多显示器的真实硬件组合仍需实际设备验证。

## 项目结构

```text
Sources/       原生窗口、互动、菜单与边界逻辑
Assets/        运行帧、分层素材和图标
Tests/         边界行为回归检查
Previews/      动画预览与验证记录
Art/           选定的生成素材、制作说明和像素验证
Versions/      1.0、1.1 的源码记录
build.sh       本地编译与打包
```

`Art/1.2/assemble_idle.py` 是原制作流程记录，需要 Pillow、NumPy 与制作环境中的 Pets 素材处理脚本。普通构建和运行不调用它；仓库已经包含最终素材。

## 版本记录

- **1.0**：初始桌面版，点击回应、拖动、菜单栏入口与散步。
- **1.1**：自由活动、部分离屏、独立慢走与跑步素材、摇尾巴。
- **1.2**：身体与尾巴分层，修复摇尾巴时身体晃动，取消整只弹跳。

详细操作见 [使用说明](使用说明.md)。

角色与动画图像通过 AI 图像生成制作，运行时不调用生成服务。仓库暂未指定开源许可证。
