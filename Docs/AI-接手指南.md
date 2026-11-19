# Susu Desktop：AI 接手指南

这是一份给后续 AI/开发者的快速地图。目标是先读代码和素材，再做小范围验证；不要为了“确认能跑”而先启动完整桌面应用。本文与 **2.11** 的实现对应，可直接按任务定位入口与验证命令。

## 先看什么

1. `Sources/main.swift`：AppKit 入口、桌面宠物、原生菜单、动画/走动调度、UserDefaults 偏好和 smoke test。
2. `Sources/CompanionStore.swift`、`Sources/StudioState.swift`：持久化、迁移、校验；成长数据和造型数据都在同一份存档中。
3. `SpriteFrames.character`（`Sources/main.swift`）、`Sources/SeasonArtwork.swift`、`Sources/SeasonDressing.swift`：统一角色帧入口、完整基础姿态和共享穿戴。
4. `Sources/ScarfRenderer.swift`、`Sources/StudioRoom.swift`：旧版配饰包导入/导出、造型选择和渲染。
5. `Assets/seasons/`、`Assets/layers/`、`Assets/frames/`：运行时素材；`Assets/seasons/visibility.json` 是边缘可见区域数据。
6. `Tests/` 和 `Docs/Susu-2.x-交付与验收.md`：已有验证入口与版本决策。README/使用说明适合了解用户功能，但不是唯一事实来源。

## 架构和不变量

- 这是原生 macOS AppKit 应用，不是网页或 Swift Package；菜单是 `NSMenu`/状态栏菜单，入口和菜单分组集中在 `Sources/main.swift`。新增功能应接入现有原生菜单层级，不另造网页控制面板。
- 待机身体固定，只有尾巴帧变化；不要把季节配饰绘制逻辑混进待机身体层而破坏“身体固定”不变量。左右散步沿起始高度水平移动，左右方向由宿主镜像；跑步等专用动作另有素材和路径。
- 季节外观（春/夏/秋/冬）是每帧已经画好接触关系的完整角色姿态，由 `SeasonArtwork` 加载；用于待机与左右散步。其余动作使用原始动作帧、共享姿态锚点和服饰部件合成，绘制和命中检测都取同一帧。
- `CompanionStore` 默认目录为 `~/Library/Application Support/SusuDesktop`，主存档是 `save.json`，任务事件在其下 `tasks/`。`CompanionSave.version` 当前为 3；迁移时保留现有备份策略，先验证再原子写入，失败不得覆盖原存档。
- `UserDefaults.standard` 保存窗口位置、大小、自由活动、安静模式、工作模式/地盘/屏幕和喝水间隔等偏好；这些不是 `save.json` 的替代品。具体 key 见 `Sources/main.swift` 与 `Sources/StudioRoom.swift`。
- `StudioState` 当前包含 `season`（由 `scarf` 字符串兼容映射）、旧内置围巾 ID、自制 `packs`、已保存 `looks`、聊天状态。改变季节第一次保存时会创建 `save-before-seasons-backup.json`。

## 按功能导航

| 需要修改 | 主要文件 | 先验证什么 |
| --- | --- | --- |
| 菜单、状态栏、显示/隐藏、退出 | `Sources/main.swift`, `Sources/DesktopControls.swift` | 检查右键、状态栏和固定面板调用同一组 action，菜单跟踪期间保留条目，关闭后更新勾选状态 |
| 待机/走动/边界 | `Sources/main.swift`, `DesktopBounds.swift` | 待机身体不变；散步不改变高度；边缘仍保留可见身体 |
| 季节完整外观 | `SeasonArtwork.swift`, `Assets/seasons/` | 6/8 帧、192×208、透明度、`visibility.json` |
| 内置四季穿戴 | `SeasonDressing.swift`, `Assets/seasons/*-pose-anchors.json`, `Assets/seasons/parts/` | 颈线和肩胯对齐，脸、前爪、毯子正确遮挡配饰 |
| 自制配饰包 | `ScarfRenderer.swift`, `StudioState.swift`, `StudioRoom.swift` | 清单 v1、待机 6 帧、散步 8 帧、路径不越界、四角透明 |
| 房屋/毯子/休息 | `NestScene.swift`, `StudioRoom.swift`, `Assets/home/` | 房屋位置与大小 UserDefaults；动作结束后释放宠物 |
| 成长、互动、学习、信件 | `CompanionStore.swift`, `CompanionActivities.swift`, `Playground.swift`, `ActivitiesRoom.swift` | 数据校验、幂等事件、旧版本迁移 |
| 聊天 | `ChatSupport.swift`, `ChatRoom.swift`, `StudioState.swift` | 接口校验、SSE 分片、停止与存档；拉伸窗口时检查转写区尺寸 |
| 构建/打包 | `build.sh` | 版本字符串、资源复制、签名校验、release 包名 |

## 动作与四季穿戴

`SpriteFrames.character(pose, frame: index, season: season)` 返回 `CharacterFrame`，内含用于显示的 `NSImage` 与用于透明点击判定的 `NSBitmapImageRep`。宠物、近看、小窝、明信片和活动角色图统一调用它。`season` 由 `StudioState.season` 解析。`nil` 取原始动作帧，自制配饰仍按原清单走 `ScarfRenderer`。

| `CharacterPose` | 帧数 | 画布 | 生效位置 |
| --- | ---: | --- | --- |
| `idle` / `walk` | 6 / 8 | 192×208 | 桌面、回窝空嘴慢走、预览；读取现有完整季节帧 |
| `run` / `stretch` / `play` | 8 / 6 / 6 | 192×208 | 桌面跑步、伸懒腰、玩耍；后两者也用于暗号或小游戏 |
| `closeup` | 3 | 192×208 | 左耳、右耳、尾纹完成三种反应 |
| `carry` / `blanket` | 8 / 6 | 256×240 | 双向叼毯；放下、铺开、趴卧以及逆序收毯 |

`Assets/seasons/desktop-pose-anchors.json` 管理 `run`、`stretch`、`play`、`closeup`，`home-pose-anchors.json` 管理 `carry`、`blanket`。每条数组按 `00.png` 开始的实际文件顺序，一帧一项。坐标均为原画布像素，左上为原点，y 向下。字段含义如下：

- `back` / `throat` 是靠后和靠前的可见颈线端点。正视时代表领口两侧。衣领与围巾绕这两个点变形，点应位于下巴和毛领下面。
- `shoulder` / `flank` 是肩侧和挎包在躯干上的中心。背带沿这两个部位走，前肢压住包时适当调整遮挡。
- `view` 接受 `side`、`front`、`prone`。`front` 将领饰移到正面中央，`prone` 压缩配饰高度。
- `occluders` 是零到多个多边形，每个为 `[x1,y1,x2,y2,x3,y3,...]`。它们让前景脸颊、爪和布料挡住服饰。角色透明轮廓也裁切服饰；逆向收毯复用同一组姿态。左右方向在画完整帧时镜像，输入判定也跟着镜像。

`Assets/seasons/parts/` 中的花、木扣、枫叶包和围巾末端供所有动作复用。`SeasonDressing` 生成贴合颈线的领口和肩带，缓存合成结果。`Art/2.6/prompts.md` 记录来源。继续加动作时，先把原始透明 PNG 放入对应资源目录，登记 `CharacterPose`、原始帧数组及帧数，按顺序给该动作标一次颈、肩、胯和遮挡，再把调度入口接到 `character`。预览四季，重点复核低头、抬爪和接触道具的帧。出现局部穿插时先改该帧的锚点或遮挡范围。改动待机需复核身体 RGBA 差分为零。

## 窗口和聊天

`CompanionRoom`、`ActivitiesRoom` 和 `StudioRoom` 是桌面内容提供者。旧分页壳已移除，交互入口把对应视图交给 `DesktopActions`。小窝保留自己的桌面窗口。普通右键和爪印菜单使用 `PetController.makeMenu`。`PinnedControls` 按需将同一组 `NSMenuItem` 变成可固定的操作面板，关闭时释放。`SpeechBubbleStyle` 绘制气泡，颜色和字号保存在 UserDefaults。`WorkTerritory.width` 在工作地盘内为气泡预留高度。

`PetController.showChat` 从菜单和双击入口打开 `DesktopChat` 无边框气泡，锚定狐狸或小窝。选择「完整聊天」才创建可缩放窗口。两种界面由 `ChatRoom` 共用发送、草稿、存档和流式状态。`ChatTranscript` 负责气泡和可选中的历史文字。没启用有效的模型配置时，`ChatRoom` 通过 `LocalChat` 在同一次存档中写入用户消息和本地回复。启用模型后先保存用户消息，请求失败时补写本地简答。`ChatMessage.source` 区分两种新回复，兼容旧存档。`ChatClient` 用 OpenAI 兼容的 `stream: true` 请求，`ChatTransport` 按字节收齐 SSE 行后解码，整段普通 JSON 响应仍可读取。当前等待数据限时 120 秒，整次请求最多 600 秒。流式中间文本只显示在窗口，终止信号后才写入存档。网络行为通过 mock 检查，不需要 API Key。

```sh
swiftc -swift-version 5 -module-cache-path /tmp/susu-desktop-module-cache \
  -framework Security Sources/ChatSupport.swift Tests/Chat/main.swift -o /tmp/susu-chat-tests
/tmp/susu-chat-tests
```

## 状态、路径与备份

- 源码资源进入 app 的路径由 `build.sh` 的 `cp -R` 决定，运行时从 app bundle 的 `Contents/Resources` 读取；普通构建不调用图像生成脚本。
- `save.json` 是可迁移的成长、活动和造型存档。读取或校验失败会先创建 `save-recovered-*.json` 原样备份，再重建空白存档。较新格式完整保留并提示更换版本。`save-2.0-backup.json`、`save-2.1-backup.json` 和 `save-before-seasons-backup.json` 是已有迁移保护文件，处理升级时不要删除或覆盖。
- 应用产物为项目根目录的 `溯溯.app`；历史安装包统一留在 `release/`，新版本不要覆盖旧版本。

## 任务队列与时间基准

桌面道具和桌面聊天通过 `DesktopBubble.armIdleDismissal` 接入单独的闲置计时。只处理这个面板上的输入事件，系统时间变更不影响倒计时。需要保留状态的控制器持有自己的草稿，自动收起仅关闭桌面面板。

`TaskBoard` 提供任务理解、预览确认和本机项目动作授权。`TaskLanguage` 先解析常见中文句式，配置模型时可使用独立的结构化请求。模型结果只能选取已授权动作的 ID，实际目录、程序和参数来自本机预设。`PlannedTask` 持久化在兼容旧版的可缺省存档字段中。提醒先写入投递状态，再用既有桌面气泡报信。

`TaskTool.executable` 通过 app bundle 查找随包发布的 `susu`，交办命令和原生验收使用同一入口。CLI 将 watcher 的 PID 和系统启动时间写入 `tasks/<id>.json`，退出前原子替换为最终结果。`pollTaskEvents()` 批量保存完成任务后才删除对应文件，`CompanionSave.lastTask` 保存最近结果。怀疑 watcher 已退出时先检查目录的 advisory lock 并重读事件。已有 CLI 事件缺少启动时间时，使用进程启动时间与事件开始时间作兼容校验。

桌面动作、喝水间隔与聊天耗时使用 `systemUptime`。隐藏、休眠和恢复时调整动画计时和提醒。探险和信件的 `Date` 是写入存档的实际到期时间，应用未运行时仍会经过，到期结算应当幂等。改动其中一类功能时请沿用相应时间基准。

`AlphaHitMask` 缓存透明度字节。宠物隐藏时停用动画计时，只继续检查任务结果和到期事件。近看和小窝只在可见时做命中检查。季节合成缓存最多 96 帧。

## 聚焦验证（无需先启动完整 App）

先检查素材数量、尺寸、透明通道、JSON schema 和源码编译影响范围。已有边界测试命令见 README：

```sh
swiftc -swift-version 5 -module-cache-path /tmp/susu-desktop-module-cache \
  -framework AppKit Sources/DesktopBounds.swift Tests/main.swift \
  -o /tmp/susu-boundary-tests
/tmp/susu-boundary-tests
```

只检查服饰和动作时，构建后导出离屏帧。这个入口在窗口和存档初始化前运行，输出目录按季节/动作分层，包含当前 204 帧。可只打开所改动作的连续帧检查咬毯、前爪和颈线遮挡。

```sh
zsh build.sh
./溯溯.app/Contents/MacOS/SusuDesktop --outfit-preview --preview-dir /tmp/susu-outfits
```

改动桌面调度、工作地盘、菜单或存档迁移时，再按范围运行已有 smoke test 和 `Tests/` 下相应检查。完整运行测试可在打包前执行，接手初期从阅读和聚焦验证开始。

```sh
./溯溯.app/Contents/MacOS/SusuDesktop --smoke-test --preview-dir /tmp/susu-previews
```

## 构建、发布与版本纪律

`build.sh` 用 Swift 构建本机架构的 macOS 13+ AppKit 应用和 `susu` CLI，复制资源、签名并输出 zip。2.11 的 `CFBundleVersion` 为 19。构建后保留历史 `release/` 包。README 介绍当前功能与使用方式，具体变更写在提交说明。软件源码与素材在仓库，`.app` 和本地安装 zip 由构建生成。
