# LocalMind

LocalMind 是面向单个 macOS 用户的本地个人活动记忆 MVP。服务只监听 `127.0.0.1:8787`，数据与 Ollama 请求均留在本机。项目不含遥测、账号、云同步或远程模型调用。

## 当前实现

- 从 ActivityWatch 本地 API 导入应用窗口、浏览器和 AFK 事件，并用指纹去重。
- 单个 Python 标准库服务提供 API、静态界面、后台采集循环、启动时最多回填 8 天活动、每日 23:30 报告和遗漏日报补生成。
- 原生 macOS 启动器提供单击入口：自动启动本机 Ollama 与 LocalMind 后，在独立 Mac 窗口内打开界面，不需要手动开终端或浏览器。
- 小型 Swift 辅助程序通过 macOS ScreenCaptureKit 截取当前前台窗口，并使用 Apple Vision 本地识别中英文。
- 截图默认每 30 秒一次；应用/域名过滤在截图前执行；同图哈希去重；JPEG 保存；按默认 7 天清理原图。
- 可选视觉记忆以 3 秒间隔读取前台窗口并运行本机 Apple Vision OCR；仅保留有变化的文字观察，默认每 5 分钟挑一张代表性画面交给本机 `qwen3-vl:4b-instruct` 描述。模型处理后的临时图立即删除；每小时由 `qwen3.5:4b` 归纳，并写入 `data/memories/YYYY-MM-DD.md`，最多保留 30 天。
- SQLite 保存活动、截图 OCR、设置和有证据 ID 的日报；时间统计由程序按区间并集计算。
- 通过 Ollama 本机 API 按连续活动时段归纳日报，合并重复结论并检查引用 ID；日报先显示结论，时间线明细默认折叠。
- 本机活动聊天支持工作 / 生活分类、最多 31 天的日期范围、可追溯活动引用和按证据生成本周工作周报。普通问题直接流式回答；活动查询先显示检索状态，再逐段显示模型回答与等待时间。聊天内容保存在本机 SQLite。
- 首页、活动时间线、日报/历史、证据查看、Markdown 导出、设置、暂停截图、删除指定日期数据。
- 时间线支持按开始/结束时间过滤；点击时间后滚动选择小时和分钟。详情将关联截图与 OCR 合并到一个入口。设置页提供全局深色 / 浅色主题，外观选择会立即应用到导航、表单、卡片、图表和证据查看。
- macOS 应用使用 LocalMind 记忆卡片图标；图标源文件位于 `assets/LocalMind.png`，`scripts/make-icon.swift` 可重新生成应用使用的多尺寸 ICNS 文件。
- 安装脚本可编译 Swift 工具并创建用户级 launchd LaunchAgent；不会使用 sudo 或写系统级配置。

## 技术选择和组件调查（2026-10-15）

- [ActivityWatch](https://github.com/ActivityWatch/activitywatch)：MPL-2.0；当前官方最新稳定版 v0.14.1。官方 macOS Apple Silicon DMG 和 Homebrew cask 均可安装，本机已安装至 `~/Applications/ActivityWatch.app`。服务默认端口 5600。LocalMind 只读官方 HTTP API，不改其数据库；该 API 文档注明接口仍可能变化。
- [aw-watcher-web](https://github.com/ActivityWatch/aw-watcher-web)：MPL-2.0；官方浏览器扩展，当前发行版 v0.6.0，Chrome Web Store / Firefox Add-ons 安装。可记录标签标题、URL、无痕状态；未安装时只显示窗口级信息。
- [OpenRecall](https://github.com/openrecall/openrecall)：仓库版本标记 0.8，AGPL-3.0；上游安装方式为从 Git 仓库 pip 安装、再运行 `python3 -m openrecall.app`，需要 Python 3.11、PyTorch/torchvision、sentence-transformers 等重量级依赖。MVP 只需要定时截图和 OCR，采用 macOS 原生 API，避免重复引入重型框架。
- [Screenpipe](https://github.com/screenpipe/screenpipe)：当前发行版 v2.7.84，可从官方 Releases 下载桌面应用；上游当前代码采用商业许可，个人非商业使用允许，商业使用/集成另需许可。它提供完整的采集应用，本项目不引入其整套运行时。
- ActivityWatch 官方文档建议 macOS 用户按 Apple Silicon/Intel 架构选官方发行包；当前这台机器通过 Homebrew cask 安装 v0.14.1 到用户 Applications 目录，没有使用 sudo。扩展、系统权限和 ActivityWatch 登录自启动仍需用户设置。

## 环境

- macOS 14+（ScreenCaptureKit 单窗口截图）和 Apple Silicon/Intel Mac；当前机器已确认 Apple M4、16GB、Python 3.14、Node 26、Swift 6.2。
- Ollama 用于生成每日总结，默认模型 `qwen3.5:4b`，地址固定为 `http://127.0.0.1:11434`；模型已安装在本机。
- ActivityWatch 可选但推荐。活动 API 不可用时服务仍可运行并清楚显示未连接。
- Python 标准库服务不需要 pip 依赖。Swift 工具首次安装时本机编译。

## 启动

开发/前台运行（首次启动会在项目的 `build/` 编译 Swift helper）：

```sh
cd "/Users/orlando/Documents/工作/其他工具/localmind"
./scripts/run.sh
```

打开 <http://127.0.0.1:8787>。ActivityWatch 已安装并已启动；还需在 macOS 系统设置 → 通用 → 登录项中添加 `~/Applications/ActivityWatch.app`，并在 Chrome/Firefox/Safari 的官方扩展商店安装 ActivityWatch Web Watcher。不要启用“允许在无痕模式中运行”。

### 原生单击启动

在项目目录执行一次：

```sh
./scripts/build-app.sh
./scripts/install-app.sh
```

之后在 Finder → 应用程序 → LocalMind 双击即可。启动器会检查 Ollama 和 LocalMind 服务；Ollama 未运行时自动执行 `ollama serve`，LocalMind 未响应时会重启已安装的 LaunchAgent，然后在 LocalMind 原生窗口中打开界面。`qwen3.5:4b` 已安装。模型文件由 Ollama 管理，默认在 `~/.ollama/models`；截图、活动、OCR 和日报集中保存在项目 `data/` 目录。退出应用窗口不会停止 Ollama 服务；下次打开时会复用正在运行的服务。

安装登录自启动：

```sh
./scripts/install.sh
```

安装脚本把个人数据集中在项目目录的 `data/` 文件夹，并把编译后的 Swift 工具放在 `~/Library/Application Support/LocalMind`；登录启动项位于 `~/Library/LaunchAgents/com.localmind.agent.plist`。首次更新会把旧的 SQLite 数据库和截图迁移到 `data/`，并保留历史记录。移除可运行 `./scripts/uninstall.sh`；卸载脚本默认保留数据，手动运行 `./scripts/uninstall.sh --delete-data` 才会删除数据和运行时工具。

## macOS 权限

截图需要 macOS 的屏幕录制授权。若系统没有自动弹出请求或截图不可用：系统设置 → 隐私与安全性 → 屏幕与系统录音（旧版本可能称“屏幕录制”）→ 为 LocalMind 实际运行的截图 helper 开启权限，然后重新启动 LocalMind。当前 helper 位于 `~/Library/Application Support/LocalMind/bin/localmind-capture`。macOS 按应用分别管理屏幕访问；LocalMind 不需要“完全磁盘访问”，也不调用辅助功能 API。应用不显示重复的授权说明，也不绕过系统权限。

权限以实际运行的二进制为准。安装为 launchd 后需单独验证屏幕录制授权是否对该后台 helper 生效；终端内成功不代表 LaunchAgent 一定成功。macOS 在隐私与安全性设置中允许用户按应用查看和开关屏幕录制访问，不能由 LocalMind 静默授予或替用户更改。

## 配置和隐私

默认数据目录：项目文件夹下的 `data/`（本机路径为 `~/Documents/工作/其他工具/localmind/data`）。设置页显示完整路径，并可点击“在 Finder 中打开数据目录”。前台运行时可用 `LOCALMIND_DATA_DIR` 指定其他位置。设置页可修改采集间隔、截图保留期、排除应用/域名及 Ollama 模型。

数据文件按用途放在同一目录中：

- `data/localmind.sqlite3`：ActivityWatch 导入的活动、OCR 文本、应用设置和日报结构化数据。
- 同一 SQLite 文件也保存工作 / 生活聊天会话和对话消息；消息会记录检索日期和引用的活动 ID。
- `data/screenshots/`：压缩后的本地截图；默认保留 7 天。
- `data/reports/YYYY-MM-DD.md`：每次成功生成/重新生成的日报 Markdown，可用文本编辑器直接查看或备份。
- `data/memories/YYYY-MM-DD.md`：每小时生成的当日记忆 Markdown。处理中间的 OCR 观察暂存在 SQLite；小时归纳成功后删除该小时原始观察，仅保留小时记忆和既有 30 秒截图。
- `data/vision-tmp/`：视觉模型正在处理的短暂截图；完成、失败或服务重启清理时删除。此目录不是归档。
- `data/logs/localmind.log`：运行和错误日志。

README 就在项目根目录，也可从应用“设置”页面的“打开中文 README”链接查看。主题选择保存在当前 Mac 的应用偏好中，重启后仍会生效。ActivityWatch 自己的原始数据库由 ActivityWatch 管理，不属于 LocalMind 的数据目录。

默认排除密码管理器、银行/金融和系统身份验证应用。浏览器扩展报告无痕时跳过；浏览器 URL 缺失或未知时默认不截图。域名支持精确匹配或子域匹配。ActivityWatch 仍然独立记录自己的活动：暂停按钮仅暂停 LocalMind 截图，首页分别展示 ActivityWatch 和截图状态，不会误报为全部暂停。

活动窗口/截图/OCR 只进入本机 SQLite 和本地目录。日报文本只发给 loopback 的 Ollama。请求不允许非本机 Ollama 地址。LocalMind 服务器只绑定回环地址。原始图片按保留时间清理，OCR 活动文本保留至用户删除对应日期。

ActivityWatch 是独立采集进程，需自行保持运行。macOS 登录项用于启动 ActivityWatch；LocalMind 的 `install.sh` 单独创建自己的 launchd 登录服务。浏览器扩展会自动连接本机 ActivityWatch 服务；不要在浏览器中授予其无痕模式访问权限。

## 数据与命令

- 时间线：`GET /api/timeline?date=YYYY-MM-DD`
- 状态：`GET /api/status`
- 日报：`POST /api/reports/{date}/generate`；浏览 `GET /api/reports/{date}`
- 导出 Markdown：`GET /api/reports/{date}/markdown`
- 删除某日活动/截图/日报及其 Markdown 文件：设置页或 `DELETE /api/days/{date}`
- 开机自启动状态：设置页显示 LaunchAgent plist 是否存在。
- 性能日志：`data/logs/localmind.log`；记录循环耗时、API 状态、OCR/模型时间和异常，不写入截图图像内容。

## 验证状态与限制

已执行 10 项 Python 单元/数据处理测试、Python 编译、前端 JavaScript 语法检查、Swift helper 编译；本地服务 `/api/status`、`/api/timeline` 和首页 HTTP 冒烟检查通过。ActivityWatch v0.14.1 的本机 API 已确认可连并导入真实应用窗口事件；日报时间并集与时间线也通过真实事件检查。LaunchAgent 已安装并在当前登录会话运行，但尚未注销/重新登录验证。Ollama 自动启动入口已加入；Ollama 模型首次下载、浏览器扩展、屏幕录制授权、真实截图/OCR 和真实模型总结需本机验证。

### 本机性能与空间估算（2026-10-15）

本机为 Apple M4、16 GB 统一内存。磁盘估算按当前本地采集样本外推；内存和 CPU 是运行时进程快照。截图内容、活动量、模型提示长度和同时打开的其他应用都会造成变化。

- 当前 `data/` 目录约 11 MB，其中 SQLite 约 232 KB、截图约 6.4 MB；共有 51 张 JPEG，平均约 132 KB/张。样本跨度约 46.5 分钟，期间平均每 55 秒保存一张。按这个样本频率外推，7 天约 1.46 GB 截图；按 30 秒间隔且每次都产生不同截图的保守上限，约 20,160 张、2.66 GB。为避免 macOS 文件提供器导致查看图片时报 `Resource deadlock avoided`，截图同时保留一份可靠的本机缓存于 `~/Library/Application Support/LocalMind/image-cache/`；因此常见情况约为 1.46 GB 数据目录截图 + 1.46 GB 缓存，合计约 2.9 GB/7 天，保守上限约 5.3 GB。过期清理会同时删除归档和缓存副本。重复画面、无文字画面、敏感应用/页面排除都会降低实际占用。空间按十进制 GB 估算，APFS 的实际分配量会有差异。
- 活动条目和 OCR 文本保存在 SQLite，当前数据库约 232 KB；日志和日报是文本文件，现阶段远小于截图。项目数据与模型文件分开：模型不占用项目 `data/` 目录。
- `qwen3.5:4b` 已下载。`ollama list` 报告模型磁盘大小约 3.3 GB；`~/.ollama` 当前约 3.1 GB。两者统计口径不同。
- 模型加载后，`ollama ps` 显示约 3.1 GB 模型、上下文 8,192，并报告 100% GPU 放置。M4 没有独立显存，CPU 与 GPU 共用 16 GB 统一内存；模型进程的 RSS 约 3.3 GiB，额外上下文缓存及 Metal 缓冲区会随输入长度变化。`100% GPU` 表示模型放置在 GPU，不表示 GPU 使用率恒为 100%；Ollama 没有在该命令中提供 GPU 实际利用率数值。
- 空闲/采集时进程快照：LocalMind 原生进程约 18–24 MB RSS，CPU 接近 0%；Ollama 守护进程约 5–15 MB RSS，CPU 通常低于 1%。日报推理时曾采到 llama-server 约 3.3 GiB RSS、CPU 33.2%（macOS 单次采样，约三分之一逻辑 CPU 核心）；它不是整段推理的峰值。Ollama 短提示速度约 21 tokens/s，日报分块曾达到约 16 tokens/s。采集循环自身每轮通常低于数秒；模型生成期间 CPU/GPU 占用随提示长度和机器负载变化。

以上是实测和外推，不是 7 天连续压力测试，也不代表全机可用内存。实用规划可按截图归档与本机缓存合计约 3 GB/7 天（30 秒全量不同图的上限约 5.3 GB）、模型磁盘约 3.3 GB、模型加载时约 3.3 GiB 统一内存映射，再为 macOS、上下文缓存、Metal 和其他应用留出空间。将截图间隔改为 60 秒时，截图文件与缓存的合计保守上限约 2.66 GB/7 天。

### 视觉记忆试跑（2026-10-16）

本机已安装 Ollama 模型 `qwen3-vl:4b-instruct`（模型文件约 3.3 GB）。合成桌面样本用于避免把真实用户屏幕内容拿去测试：Apple Vision OCR 捕获了全部预期文字；Qwen3-VL 在图中正确识别了项目主题、2/3 完成状态、两项已完成内容、一项待检查内容和下一步安排（关键事实 5/5）。这只是单张合成样本的定性核验，不代表所有应用、缩放比例、中文小字或受保护窗口都有同等识别率。

- 同一张合成图限制最长边为 1,280 像素时，视觉理解耗时约 47.2 秒、输入约 4,046 tokens；缩至 960 像素后两次测试耗时分别约 18.9 秒和 15.1 秒，输入约 1,112 tokens，均识别上述关键事实（关键事实 5/5）。输入 token 约减少 73%。因此服务默认把送给视觉模型的临时图缩到最长边 960 像素；原始 OCR 仍由 Apple Vision 单独完成。模型速度和冷启动会随机器状态变化。
- 视觉理解默认每 300 秒一次，按样本延迟估算约占每 5 分钟 19 秒，即视觉模型活跃时间约 6.3%；不是连续视频推理。小时记忆只在整点后对上一个小时批量调用 Qwen3.5。两模型通过串行锁和 `keep_alive: 0` 依次运行，避免同时常驻 GPU 内存。
- M4 使用统一内存而非独立显存。视觉模型磁盘约 3.3 GB；运行时预计约 3.3 GiB 模型映射，另有上下文/Metal 缓冲区。其内存级别与既有 4B 文本模型相近，分时运行，不应把两者的占用相加。每 3 秒 ScreenCaptureKit/OCR 的真实持续采集 CPU/能耗尚未做全天压力测试，实际开销取决于屏幕变化、显示器分辨率和被排除窗口。
- 本次模型运行时 RSS 采样未捕获 Ollama 的短命推理子进程；既有历史快照曾测到文本模型 llama-server 约 3.3 GiB RSS，但不把它冒充为这次视觉模型的峰值。测试环境无法无密码调用 macOS `powermetrics`（需要管理员认证），因此没有伪造瓦数或焦耳数字。视觉推理延迟和周期占比是本次实测/计算；CPU、能耗及全天续航应在用户机器的真实工作负载下进一步观察。`data/logs/localmind.log` 会记录采集与模型耗时，不写入屏幕内容。

视觉记忆默认开启，但遵守截图总开关、应用/域名排除规则和屏幕录制授权。它只截取 ActivityWatch 确认的前台窗口；权限缺失时无法采集。关闭视觉记忆或暂停截图即可停止 3 秒观察。启用后，前三秒采样频率会高于传统 30 秒截图流程；如重视续航，可在设置里关闭或把视觉分析间隔调长。

屏幕截图依赖 macOS TCC 权限和可见前台窗口。ScreenCaptureKit 可能无法获取受保护内容、最小化窗口或某些系统窗口。窗口标题/浏览器 URL 是否完整取决于 ActivityWatch watcher 和浏览器扩展。此版本不控制 ActivityWatch 的启停，不做跨设备同步，不在服务端持续运行大模型。日报是证据约束的本地模型归纳，仍应点击证据核对。

卸载后删除全部个人数据：先停止 LocalMind，然后执行 `./scripts/uninstall.sh --delete-data`。ActivityWatch 自己的数据库不在 LocalMind 目录中，需通过 ActivityWatch 自己的设置/文档处理。

### 2026-10-26 准确性与性能优化

- 网页活动仅补充到浏览器窗口，避免网页标题污染编辑器、聊天等应用的记录。
- 聊天中的连续会话仅合并间隔不超过 2 秒的同名窗口，避免把两分钟空档算作连续活动。
- 时间线按活动 ID 预分组截图，避免每个窗口重新扫描全部截图。
- 交互聊天模型在回复后保留 60 秒，减少连续提问的重复加载；这段时间仍占用模型内存，超时由 Ollama 卸载。简短回答使用 4096 上下文，检索回答保留 8192。
- 流式消息写入间隔至少 350 毫秒；隐藏或离开聊天页面时轮询降到每 3 秒。删除对话后下一次流式写入会中止生成。
- 无变化的屏幕观察不再逐条写日志。截图与 OCR 的采样频率保持原设置。

以上为实现层面的改进，不代表实测延迟或整机能耗降幅；模型冷启动、连续问答和屏幕观察需分别采样评估。
