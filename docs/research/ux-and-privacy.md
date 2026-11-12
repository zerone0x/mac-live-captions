# 调研：刘海浮层、字幕可读性、补进度信任与隐私规范

状态：调研稿 · 2026-11-12 · 对应 issue #3 · 配合 [PRD.md](../../PRD.md) 阅读

## 说明

- **范围**：PRD「产品范围与交互」和「结束／隐私」涉及的四个问题：(1) 刘海/浮层窗口的技术做法；(2) 字幕可读性；(3) 会中补进度与摘要可信；(4) 不录音转写的同意规则与竞品披露方式。
- **方法**：直接读一手来源，包括 Apple 开发者文档（JSON 接口）、开源项目源码与 issue、字幕规范原文、论文摘要或全文、法条原文、法院文书，以及竞品的帮助文档。所有来源都在文末「来源」列出，访问日期均为 **2026-11-12**，正文用 `[S#]` 引用。
- **局限**：
  - Bing、DuckDuckGo 对脚本请求返回无关结果或验证码，所以没能做通用搜索。来源主要通过 GitHub 搜索、OpenAlex、arXiv、Crossref 和已知站点找到。
  - Apple 开发者论坛、w3.org、Justia 和 leginfo.ca.gov 有反爬验证，无法直接读取。凡是只经二手转述的内容都标了 **未核实**。
  - 本机没有 PDF 工具，部分论文只看了标题或摘要，已注明。
  - 法律部分不是法律意见，只说明了条文与判例的事实。

## 结论速览

1. **屏幕共享时隐藏字幕无法承诺。** Apple 当前文档把 `NSWindow.SharingType.none` 称为「macOS 已不再使用的遗留常量」，并明确说「不要用它来隐藏内容」[S1]。Electron 维护者认为 ScreenCaptureKit 忽略该设置是 Apple 的有意改动 [S3]。但有人在 macOS 26.5 实测，SCK、Zoom 和 Meet 的整屏共享都排除了 `.none` 窗口 [S5]。另有用户报告 Zoom 桌面端是否生效取决于 Zoom 的「屏幕捕获模式」设置 [S6]。结论是证据互相矛盾，行为随系统版本、会议工具和设置变化。PRD 把它放进「暂不做」是对的。
2. **浮层的通行做法已经稳定。** 三个刘海库和 Audicap 都用无边框窗口，并设置 `collectionBehavior` 为 `.canJoinAllSpaces` + `.stationary`（多数还加 `.fullScreenAuxiliary`），层级在 `.statusBar` 到 `.screenSaver` 之间 [S10–S13]。要做到「不抢焦点」，组合是 `NSPanel` + `.nonactivatingPanel` + `canBecomeKey = false`；要做到「不挡点击」，再加 `ignoresMouseEvents` [S14–S15]。
3. **字幕版式有明确基线。** 横屏最多两行 [S31][S32]。中文每行 ≤16 字，成人阅读速度上限 9 字/秒；英文每行 ≤42 字符，上限 20 字符/秒 [S32][S34]。BBC 的直播字幕要求左对齐、逐词出现、两行滚动，并避免已有文字横向移动 [S31]。直播语音经常超过这些速度，所以刘海只适合「扫一眼」，完整阅读要交给回看面板。
4. **临时字幕的跳动会实际增加负担。** Google 的研究发现，字幕闪动指标与用户的 NASA-TLX 负荷评分显著相关 [S39]。BBC 也指出，过多的修正反而让字幕更难读 [S31]。Apple 的 `volatileResults` 本来就会对同一段音频多次给出修订结果 [S29]。因此确认后的文字必须不可变，只允许尾部的临时部分变化。
5. **有引用不等于可信。** 实验发现，即使引用是随机的，用户的信任也会上升；用户真去核对引用后，信任会下降 [S50]。对生成式搜索的审计显示，只有 51.5% 的句子被引用完全支持，74.5% 的引用支持其所在句子 [S49]。所以引用必须由程序校验，并且要让核对的成本很低。
6. **「提议写成决定」和「编造负责人」都有研究证据。** LLM 对话摘要常出现「间接推断」（circumstantial inference）：内容看似合理，但原话里没有直接证据 [S48]。各种规模的模型在对话摘要中都有大量事实错误 [S47]。另一项研究发现，模型改写时常丢掉原文的限定语，结论会变得更肯定 [S51]。这三点正对应 PRD 验收里「不得把提议写成决定，不得编造负责人或日期」。
7. **法律上，「不录音」不等于免责。** 美国联邦法律采用一方同意 [S53]，但加州等约 11 个州要求所有人同意 [S54]。加州 PC 631 管的是在传输中「读取或了解内容」[S56]，并不限于录音。2026-08-13，Otter.ai 案的驳回动议被部分驳回：法院认定，如果工具厂商独立收集、留存或使用对话，可能构成第三方窃听者；如果工具只是用户的延伸，则不构成 [S58]。中国 PIPL 第 72 条排除了「个人或家庭事务」[S62]；GDPR 也有类似的家庭豁免，但工作会议难以适用 [S59][S60]。
8. **竞品分两类。** 平台方（Teams 转写、Meet 记笔记、iPhone 通话录音）会通知所有参会者，Apple 甚至播放语音提示 [S63–S66]。本地或无机器人工具（Otter 桌面版、Granola、Audicap）则把取得同意的责任交给用户，同时提供提醒或可发送的告知文案 [S13][S68][S69]。Teams 的个人实时字幕不保存，也不通知他人 [S65]，这是本产品最接近的先例。

---

## 1. 刘海与浮层窗口

### 1.1 现有实现对比

| 项目 | 窗口类型 | 层级 | collectionBehavior | 能否成为 key | 其他 |
|---|---|---|---|---|---|
| DynamicNotchKit [S10] | `NSPanel`，`[.borderless, .nonactivatingPanel]` | `.screenSaver` | `.canJoinAllSpaces, .stationary` | 可以 | 用 `auxiliaryTopLeftArea/RightArea` 判断是否有刘海，刘海高度取 `safeAreaInsets.top`；没有刘海时退化为 300pt 宽、菜单栏高度的区域，或改成浮动样式 |
| boring.notch [S11] | `NSPanel`，`isFloatingPanel = true` | `.mainMenu + 3` | `.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle` | 不可以 | 有「对屏幕录制隐藏」开关（切换 `.none` / `.readWrite`）；另用私有 SkyLight API（`dlopen` + `SLSRemoveWindowsFromSpaces`） |
| NotchDrop [S12] | `NSWindow` | `.statusBar + 8` | 同上（四项） | 可以 | 没有刘海时使用 150×28 的默认区域 |
| Audicap [S13] | 无边框 `NSWindow` | `.statusBar` | `.canJoinAllSpaces, .stationary, .fullScreenAuxiliary` | 未覆写 | 放在 `NSScreen.main` 底部；首次启动弹窗提醒同意（见 §4.4） |

结论：
- 「出现在所有桌面和全屏 Space 上」靠 `.canJoinAllSpaces` + `.fullScreenAuxiliary` + `.stationary` 实现。按文档，`.fullScreenAuxiliary` 的含义是「与全屏窗口显示在同一个 Space」[S18]，`.canJoinAllSpaces` 表示「可出现在所有 Space」[S19]，`.stationary` 表示「不受 Mission Control 影响」[S20]。
- 层级没有统一做法。层级高的窗口总会盖住层级低的窗口 [S21]。用 `.screenSaver` 可能盖住系统 UI，例如通知和菜单。**未核实**：在 macOS 26 上，`.statusBar` 是否足以压过全屏的 Zoom、Keynote 演示和全屏视频，需要原型实测。
- boring.notch 用到的私有 SkyLight API 不应采用，因为它有上架风险，系统升级后也可能失效。

### 1.2 不抢焦点、不挡点击（US5）

- `.nonactivatingPanel`：点击面板不会激活所属应用 [S14]。再覆写 `canBecomeKey = false`，字幕条就完全拿不到键盘焦点（boring.notch 的做法 [S11]）。
- `ignoresMouseEvents = true`：窗口对鼠标透明 [S15]。字幕条在只显示、不交互时应开启它，这样就不会挡住会议工具顶部的按钮。
- 回看面板需要滚动和点击时间戳，所以不能完全点击穿透。可以设 `becomesKeyOnlyIfNeeded`，只在需要键盘输入时成为 key [S16]。Apple 建议浮动面板满足「小、不遮挡、以鼠标操作为主」这些条件 [S17]。
- 建议**拆成两个窗口**：
  - **字幕条**：点击穿透，永远不成为 key。
  - **回看面板**：非激活面板，可以接收鼠标；按 Esc 或再按一次快捷键关闭，焦点回到原应用。

### 1.3 刘海检测与多显示器（US3、US4）

- 刘海判断：`auxiliaryTopLeftArea` 和 `auxiliaryTopRightArea` 都存在，就视为有刘海，刘海高度等于 `safeAreaInsets.top` [S10][S22]。外接屏没有刘海，应该自动改用「独立浮层」样式（DynamicNotchKit 就有 `.notch` 和 `.floating` 两种样式 [S10]）。
- 选屏有两个容易踩的坑：
  - `NSScreen.main` 是**当前键盘焦点窗口所在的屏幕**，不是菜单栏所在的屏幕；菜单栏屏幕永远是 `screens[0]` [S23]。Audicap 用 `NSScreen.main` 定位 [S13]，所以浮层会出现在当时焦点所在的屏幕上，之后不会跟随。
  - 显示器插拔、改分辨率时会收到 `didChangeScreenParametersNotification` [S24]，这时要重新计算位置。DynamicNotchKit 也是这样做的 [S10]。
- 如果「显示器具有单独的空间」被关掉（`screensHaveSeparateSpaces == false`），全屏行为会不同 [S25]。这一项要放进验收矩阵。
- 字幕条的展开和收起动画要遵守「减少动态效果」设置 [S26]。

### 1.4 屏幕共享时隐藏：证据矩阵（PRD「暂不做」）

| 来源 | 结论 | 可信度 |
|---|---|---|
| Apple 文档 `SharingType.none` [S1][S2] | 「macOS 已不再使用的遗留常量……不要用它来隐藏或排除被捕获的内容」，建议改用 FairPlay | 一手，现行文档 |
| Electron #48258，维护者 2025-09-09 [S3] | 「新的 ScreenCaptureKit API 会绕过这个设置，这是 Apple 有意为之」；Chromium 改用了未公开 API；issue 以「预期行为」关闭 | 一手，维护者判断 |
| Tauri #14200 [S4] | macOS 15+ 的 SCK 忽略 `.none`，并称 Apple 在论坛确认过 | 二手；论坛原帖 **未核实** |
| Skia #3，在 macOS 26.5（25F71）实测 [S5] | `.none` 窗口在 SCK `SCScreenshotManager`、旧 CG、Meet 整屏共享、Zoom 整屏共享中**都被排除**，由第二台设备验证；同时引用 Apple DTS 2025-07 的说法「目前没有防截屏的公开 API」（论坛 792152，**未核实**），以及 FB21115847「重建捕获过滤器后排除会失效」 | 一手实测，但只有单机 |
| Natively #140 [S6] | 2026-03：Zoom 桌面端看得到窗口，浏览器版看不到；26.3.1 上有人说可以；26.4 上把 Zoom 设置改成「Advanced capture with window filtering」后可以 | 用户报告，**未核实** |
| sokki #116 [S7] | 同类日文字幕浮层项目把它当成「无法用代码保证」的功能，计划在检测到共享时自动隐藏 | 同类项目的判断 |
| Murmo [S27] | 营销页宣称「Stealth mode：屏幕共享时对他人不可见」 | 竞品宣称，**未核实** |

补充：
- 即使像素被排除，窗口本身仍然会出现在 `SCShareableContent` 和 `CGWindowListCopyWindowInfo` 中，其他应用能读到它的 `sharingState` [S5]。这项设置只能隐藏像素，不能隐藏窗口的存在。
- macOS 没有「检测当前正在被捕获」的公开 API [S5]（**未核实**：iOS 有 `UIScreen.isCaptured`，macOS 没有对应接口）。所以 sokki 设想的「检测到共享就自动隐藏」没有可靠的公开实现方式。
- 捕获方可以选择「只捕获某个窗口」[S8]，也可以「排除指定窗口」[S9]。所以对用户最可靠的建议是：**共享单个窗口，而不是整个屏幕**。这样浮层天然不会进入画面，而且不依赖 `.none`。

**建议**：
- 首版不承诺。
- 如果之后提供开关，文案写成「尽量对屏幕共享隐藏（不保证，取决于会议工具与系统版本）」，并在设置页附「共享单个窗口」的提示。
- 每次 macOS 大版本升级，都用类似 Skia 的工具重测一次（SCK、Zoom、Meet、Teams、腾讯会议、飞书）。

---

## 2. 字幕可读性（US3、US4、US6、US9、US11）

### 2.1 规范基线

| 规范 | 行数 | 每行长度 | 速度 | 其他要点 |
|---|---|---|---|---|
| BBC 字幕指南 [S31] | 横屏最多 2 行 | 广播 37 字符；在线为视频宽度的 68% | 直播 160–180 wpm（从 130–150 上调），每词至少约 0.3 秒 | 直播字幕**左对齐**、逐词从左到右出现、两行滚动；避免让整行随新词横向移动；换说话人时换颜色；纠错用 `--`，但「纠错太多或不及时反而更难读」 |
| Netflix 简体中文 [S32] / 繁体中文 [S33] | 最多 2 行，能一行就一行 | 16 字 | 成人 9 字/秒，儿童 7 字/秒 | 多行时用「下宽上窄」的金字塔形 |
| Netflix 英文（美国）[S34] | 最多 2 行 | 42 字符 | 成人 20 字符/秒 | 同上 |
| DCMP 字幕要点 [S35][S36] | — | — | 教育媒体分别为 130、140、160 wpm | 质量四要素与 FCC 2014 一致 |
| FCC 47 CFR 79.1(j)(2) [S37] | — | — | 「以观众能读完的速度显示」 | 准确、同步、完整、不遮挡重要内容；字号要足以辨认 |
| Apple 实时字幕（macOS）[S28] | 可调窗口 | 可调字体、字号、颜色、背景 | — | 没有音频时自动隐藏；有「保持在屏幕上」和「恢复默认位置」；可在电脑音频和麦克风之间切换；声明「准确度可能不一，不应在高风险场合依赖」 |
| WCAG 1.2.4 实时字幕 [S38] | — | — | — | 该条款**不要求**双向通话应用为用户提供字幕，因此对本产品不构成合规要求，只作参考 |

### 2.2 推导给本产品的版式

- **刘海字幕条**：最多 2 行，左对齐，按行滚动。不要居中，否则每来一个新词，整行都会横向移动 [S31]。
- **行宽按像素算，不按字数算**：
  - 中英混排（US11）时，固定字数没有意义。建议以「一行约 16 个汉字的宽度」作为上限：中文接近 Netflix 的 16 字，英文约能放 30–40 个字符（**估算，未实测**）。
  - 刘海本身的宽度通常放不下，所以字幕条要从刘海下方「挂」出来，宽度需要实测。
- **速度**：会议语速可能长时间超过 9 字/秒（**未核实**，没有找到中文会议语速的一手数据）。刘海不做删减改写，超出部分直接滚走。PRD 的「回看面板」本来就承担补读的功能，所以不需要在刘海里追求读完。
- **外接屏和大字（US4）**：独立浮层要能调字号、颜色、背景和位置，并能一键恢复默认，参照 Apple 实时字幕的选项 [S28]。默认放在屏幕底部，但要避开会议工具底部的控制栏（FCC 的「不遮挡」要求 [S37]）。
- **闲置时收起**：与 Apple 实时字幕「没有音频时自动隐藏」一致 [S28]。

### 2.3 临时文字稳定化（US6）

- Apple `SpeechTranscriber` 开启 `.volatileResults` 后，会对同一段音频返回多次修订结果，最后给出定稿 [S29][S30]。Audicap 已经开启了 `volatileResults` 和 `transcriptionConfidence` [S13]。
- Liu 等（CHI EA 2023）提出了基于亮度对比和 DFT 的字幕「闪动」指标，并发现它与 NASA-TLX 负荷显著相关 [S39]。实时翻译领域长期在「重译」策略的低延迟和文字擦除（闪动）之间做取舍 [S40][S41]。MeetDot 的做法是平滑滚动并减少闪动 [S42]。
- 建议规则（具体阈值待原型确定）：
  1. **已确认的片段不可变**：不重排，也不改字，只能被滚出视野。
  2. **临时文字只出现在末尾**：用较低的不透明度或不同字重显示。临时文字变化时，不能导致已确认部分换行或移动。
  3. **节流更新**：临时文字刷新不宜过快，例如每 200–300ms 合并一次（**估算**），以减少闪动。
  4. **只在确认边界换行**：避免一个词在两行之间来回跳。
  5. **低置信度标记要谨慎**：Berke 等（CHI EA 2019）研究了深聋或听障用户对 ASR 字幕外观的偏好 [S43]，但本次**只看了标题，具体结论未核实**。首版不建议给低置信度词做特殊样式，先保持简单。
- **回看时不被拉回底部（US9）**：用户手动滚动后，新内容只在底部显示「有 N 条新字幕」，不自动跳转。PRD 已经写了「用户可主动回到最新字幕」，与此一致。

---

## 3. 会中补进度与摘要可信（US7、US8、US10、US14）

### 3.1 研究证据

| 研究 | 发现 | 对本产品的含义 |
|---|---|---|
| EngageSync，VR 会议，arXiv 2025 [S45] | 实时转写加 LLM 摘要的界面，比只显示当下字幕、看不到之前内容的界面**显著缩短重新跟上的时间、提高信息回忆**（p<.05） | 支持「按一次键看摘要」的核心假设（不过场景是 VR） |
| Minuteman，arXiv 2023 [S46] | ASR 常把人名等实体识别错，摘要模型会幻觉和误读；实时可编辑的摘要帮助走神或缺席的人补进度 | 名字、数字要能回到原话核对（US8） |
| Asthana 等，PACM HCI/CSCW 2025 [S44] | 「要点」和「层级纪要」各有用处；用户认为错误的行动项「可能误导」；章节标题偶尔不准；把长对话分块处理可以减少幻觉 | 默认 2–4 条要点是对的；行动项出错的代价最高 |
| TofuEval，arXiv 2024 [S47] | 各种规模的 LLM 在对话摘要中都有大量事实错误；拿 LLM 当事实判别器效果差 | 不能只靠「再问一次模型」来校验 |
| Ramprasad 等，arXiv 2024 [S48] | 提出「间接推断」类错误：结论在语境上说得通，但原话里没有直接证据；自动检测器很难发现 | 这正是「编造负责人或日期」的来源 |
| Epistemic Erosion，AACL 2026 [S51] | 模型改写时最常见的失真是丢掉限定语（66%）；保留下来的论断也会变得更肯定 | 正是「提议被写成决定」的机制（US10） |
| Liu、Zhang、Liang，Findings of EMNLP 2023 [S49] | 生成式搜索只有 51.5% 的句子被引用完全支持，74.5% 的引用支持其所在句子；作者称之为「可信的外表」 | 引用要校验，不能只是摆出来 |
| Ding 等，arXiv 2025 [S50] | 有引用时信任显著上升，**即使引用是随机的**；用户核对引用后信任下降 | 引用本身会让人过度信任，所以必须降低核对成本 |
| Fernández 等，SIGdial 2008 [S52] | 把多方对话中的「决定」作为可建模、可检测的结构来研究（**只看了标题和元数据**） | 「决定」应有明确的语言证据，而不是摘要模型的概括 |

### 3.2 建议

1. **用结构化输出代替自由文本。** 每条要点包含：`类型 ∈ {讨论, 提议, 决定, 行动, 待定问题}`、一句话内容、`证据片段 ID 列表`，以及一小段原话摘录（≤ 1 行）。
2. **由程序校验，不交给模型自评**（依据 [S47]）：
   - 证据 ID 必须落在冻结的时间范围内（PRD 已有这一条）。
   - **负责人和期限**这两个字段，要能在所引片段的原文里逐字找到（允许简单的规范化，例如「周五」「Friday」）；找不到就删除该字段，但保留这条要点。这直接对应「间接推断」[S48]。
   - 「决定」类要点所引的片段里，应该有明确表态的话（例如「就这么定」「同意」「我们决定」），或者有人的明确确认。否则降级为「提议」，并标出「未见明确确认」。
3. **保留原话的语气**（依据 [S51]）：原话是「可能」「建议」「要不要」，摘要不能写成肯定句。提示词里要写明这一点，并在标注集中专门检查语气是否被加强。
4. **降低核对成本**（依据 [S50]）：每条要点旁直接显示原话摘录，悬停可以预览上下文，点击就跳转并高亮（US8）。不要只给一个时间戳。
5. **把实际覆盖的时间范围和音源写在摘要顶部**，例如「10:02–10:05，仅系统音频」（US7、US12）。范围应对齐到已确认片段的边界，避免从半句话处截断。
6. **空状态和失败状态要说实话**：
   - 没有明确决定时，直接写「这段时间没有明确的决定」，不要硬凑。
   - 摘要失败时，回看面板仍显示这段时间的原文（US14）。
7. **刷新时保留旧摘要**：新摘要生成好之前，旧的那份不要消失（PRD 已有）。旧摘要上标出「生成于 10:05」，并提示「之后又有 N 条新字幕」。
8. **验收标注集**里，至少分开统计这几类错误：「提议被升级为决定」「否决被漏掉」「负责人或日期不在原话中」「引用不支持所在要点」。依据是 [S49] 提出的引用精确率和召回率概念。

---

## 4. 隐私与法律（US1、US12、US13、US15）

> 以下不是法律意见。本产品的特点是：本地转写、不录音、默认不落盘、会话结束即丢弃，可能还有可选的云端摘要。这几点与现有判例中的情形（例如 Otter：机器人入会、云端存储、用于训练）差别很大，适用性需要律师判断。

### 4.1 美国

- **联邦**：参与方本人截取通信，或者一方事先同意，就不违法，除非目的是犯罪或侵权（18 U.S.C. §2511(2)(d)）[S53]。
- **全体同意州**：加州、康涅狄格、佛罗里达、伊利诺伊、马里兰、马萨诸塞、蒙大拿、新罕布什尔、宾夕法尼亚、华盛顿等州要求所有人同意 [S54]。DMLP 原文写的是「十一个州」，但只列出了十个，并注明伊利诺伊的旧法 2014 年被判违宪、马萨诸塞禁止的是「秘密」录音。该页面较旧，**现行状态未逐州核实**。跨州通话时，建议按全体同意处理 [S54]。
- **加州 PC 632**：未经所有人同意，用「电子放大或录音设备」**窃听或录制**保密通信，即属违法。但「被所有人知晓正在旁听或录制的个人」不在此列 [S55]。实时转写而不保存音频算不算「录制」或「窃听」，**没有找到直接判例，未核实**。另外，本产品会在会话期间保留文字，并允许复制，这本身就形成了记录。
- **加州 PC 631**：管的是未经全体同意、在传输中「读取，或试图读取、了解其内容或含义」[S56]，范围不限于录音。
- **In re Otter.ai Privacy Litigation**，N.D. Cal. 5:25-cv-06911，2025-08-15 立案 [S57]。2026-08-13 法院部分准予、部分驳回驳回动议 [S58]：
  - ECPA 诉求保留，理由是商业目的与侵权并不互斥。
  - CIPA 631：法院援引 *Graham v. Noom*，认为「通信一方可以录制（这不算窃听）」，而只作为用户延伸的软件供应商不算第三方。但原告称 Otter **独立收集、留存并为自身商业目的使用**通信，因此可能构成第三方窃听者。
  - CIPA 632：其中一名原告与医疗专业人员的通话，被认为可能属于保密通信。
- **对本产品的启示（推论，未经律师确认）**：
  - 「本地处理、厂商收不到任何内容、不留存、不训练」能让本产品更接近「用户的工具」，而不是「第三方」。这是隐私承诺中最值得守住、也最值得说清楚的一点。
  - 用户本人在全体同意州是否需要先告知，仍然是开放问题，所以产品应该提醒用户，并帮用户方便地告知他人。

### 4.2 欧盟与德国

- GDPR 不适用于自然人「纯个人或家庭活动」中的处理（第 2(2)(c) 条）[S59]。序言第 18 条说明，这类活动「与职业或商业活动无关」，但 GDPR **仍适用于为这类活动提供处理手段的控制者或处理者** [S60]。
  - 因此，工作会议中的转写**很可能不适用**家庭豁免。用户（或其雇主）可能是控制者。
  - 开发者如果从头到尾接触不到数据，是否构成处理者，**未核实**。
- 德国刑法 §201：未经授权把他人非公开的话**录到录音载体上**，或者用窃听设备收听**不是说给自己听的**话，都要处罚；公开传播原话或主要内容也可能受罚 [S61]。
  - 参会者本来就是听众，只转文字、不录音，与「录到录音载体上」字面不同。但会议参与方能否被视为「授权」，以及转写稿属于什么性质，**未核实**。
- 一个信号：Apple 的 iPhone 通话录音**不在欧盟提供** [S63]。

### 4.3 中国

- PIPL 第 4 条：个人信息是以电子或其他方式记录的、与已识别或可识别的自然人有关的各种信息；处理包括收集、存储、使用、加工、传输等 [S62]。会议转写稿中有他人的发言，通常属于个人信息。
- 第 13 条：处理需要满足同意等合法性基础。第 17 条：处理前要以显著方式、清晰易懂的语言告知处理者、目的、方式、种类和保存期限 [S62]。
- 第 72 条：「自然人因个人或者家庭事务处理个人信息的，不适用本法」[S62]。工作会议是否属于「个人事务」，**未核实**。
- 敏感个人信息（第 28、29 条）需要单独同意 [S62]。本产品不保存声纹，但会议内容本身可能涉及医疗、金融等敏感信息。
- **将来如果做云端摘要**：
  - 把转写稿交给其他处理者，需要告知接收方并取得单独同意（第 23 条）。
  - 发往境外，需要满足第 38 条的条件，并按第 39 条告知、取得单独同意 [S62]。
  - 这与 PRD「默认关闭，启用前明确显示提供方与发送范围」的方向一致，但还需要补上**接收方名称、所在地**。
- 《民法典》第 1032、1033 条（隐私权，禁止窃听他人私密活动）：本次**未能获取原文，未核实**。

### 4.4 竞品披露方式

| 产品 | 谁来告知 | 怎么告知 |
|---|---|---|
| iPhone 通话录音 [S63] | 系统 | 双方都会听到语音提示「通话正在录音」；欧盟等地区不提供；提醒用户「确认对方愿意被录音」，并且「依赖转写前请核对准确性」 |
| Microsoft Teams 转写 [S64] | 平台 | 所有参会者都会看到「会议正在转写」的通知；参会者可以在字幕和转写中隐藏身份 |
| Microsoft Teams 实时字幕 [S65] | 无 | 「Teams 不保存字幕」，会议结束后字幕数据永久删除；页面没有提到要通知他人（**未核实**是否完全不提示） |
| Google Meet「帮我记笔记」[S66] | 平台 | 告知所有参会者，并在所有人屏幕上显示铅笔图标；同组织的参会者可以随时停止 |
| Otter Notetaker [S67] | 产品与用户 | 会前邮件、会中可见信号；企业版可以在入会前要求每个人确认同意；建议跨地区团队「统一按全体同意处理」 |
| Otter 桌面版（无机器人）[S68] | 用户 | 只在文档中提醒「录制前通知参会者并取得法律要求的同意」 |
| Granola [S69] | 用户（产品协助） | 「转写完成后删除音频，包括第三方服务处的音频」；macOS 上可以开启「Let others know you're using Granola」，在会议开始时发送可自定义的告知消息 |
| Murmo [S27] | 未见 | 「实时字幕 100% 本地运行」；请求 AI 摘要时「只把必要的转写文字发给 AI 服务商」；同时宣称有「隐身模式」 |
| Audicap [S13] | 用户 | 首次启动弹窗：会转写 Mac 播放的所有声音，包括通话中他人的声音；很多地方需要所有人同意，由你确认并取得 |
| AirTranslate | — | 官网无法访问，**未核实** |

### 4.5 建议的应用内披露

1. **首次启动说明**（一屏，不用长篇条款），回答 US13 和 US15：
   - 应用在听什么：默认只听系统音频，麦克风需要单独开启。
   - 在哪里处理：转写在本机；摘要在本机（如果做了云端，就写清楚是谁）。
   - 留下什么：不录音，默认不写入任何文件；文字只保存在内存里，清空、退出或开始新会话后即消失。
   - 你的责任：一句中性提醒。可以参考 Audicap 的措辞，例如「在部分地区，转写他人发言需要事先告知或取得同意」。
2. **菜单栏图标始终显示状态**：监听中、等待权限、暂停、出错（PRD 已有）。监听中的图标要能在全屏下一眼看出来。
3. **「告知他人」的可复制文案**：参考 Granola。提供中英双语模板，一键复制，例如「我在用本地实时字幕辅助听会，不录音、不保存音频」。应用不自动往会议聊天里发消息。
4. **开启麦克风时（US12）**再提醒一次：现在会同时收录你自己的发言，摘要也会涵盖。
5. **云端摘要（如果以后做）**：
   - 每次发送前，显示提供方名称和所在地、发送的时间范围和字数。
   - 只发文字，绝不发音频。
   - 写明对方是否留存、是否用于训练。
6. **不要做的事**：
   - 不要宣称「对屏幕共享不可见」（见 §1.4）。
   - 不要把披露写成法律意见。
   - 不要把「我们不保存数据」这类承诺写进营销文案，除非验收能覆盖崩溃日志、交换分区、剪贴板历史等旁路（见开放问题）。

---

## 5. 建议与用户故事对照

| 用户故事 | 建议 | 依据 |
|---|---|---|
| 1 直接转录 Mac 声音 | 首次启动说明加「告知他人」文案；在说明中强调本地处理、厂商收不到数据 | [S54][S58][S68][S69] |
| 2 知道在听什么、缺什么权限 | 菜单栏有持续可见的状态；首次启动说明列出音源 | [S28][S13] |
| 3 刘海处扫一眼 | 用 `NSPanel` 非激活、点击穿透；按 `auxiliaryTop*Area` 判断有无刘海；字幕条从刘海下方挂出，最多 2 行、左对齐 | [S10][S14][S15][S31] |
| 4 外接屏和大字 | 没有刘海的屏幕自动改用浮层；监听屏幕参数变化；可调字体、颜色、背景和位置，能恢复默认 | [S22][S23][S24][S28] |
| 5 不抢焦点、不挡点击 | 字幕条 `canBecomeKey = false` 且 `ignoresMouseEvents`；回看面板 `becomesKeyOnlyIfNeeded`，单独成窗 | [S11][S14–S17] |
| 6 确认后的文字稳定 | 已确认片段不可变；临时文字只在末尾、样式弱化、节流刷新；只在确认边界换行 | [S29][S31][S39] |
| 7 一键看要点 | 顶部标出实际时间范围和音源；范围对齐片段边界；如实显示空状态 | [S44][S45] |
| 8 时间戳定位原话 | 每条要点直接带原话摘录，悬停预览，点击高亮 | [S46][S49][S50] |
| 9 回看时继续收字幕 | 用户滚动后不自动跳转，显示「N 条新字幕」 | [S31] |
| 10 区分讨论、决定、行动 | 输出结构化的类型字段；「决定」要有明确表态的原话，否则降级；保留原话语气 | [S48][S51][S52] |
| 11 中英切换 | 行宽按像素算，不按字数算（中文 16 字、英文 42 字符可作参考） | [S32][S34] |
| 12 是否收录自己 | 开启麦克风时再提醒一次；摘要标明「仅系统音频」或「含我」 | [S28][S63] |
| 13 摘要在哪生成 | 首次启动说明与设置中写明；云端选项显示提供方、所在地和发送范围 | [S62][S27] |
| 14 摘要失败仍能看原话 | 失败时回看面板直接显示这段时间的原文 | PRD 已有 |
| 15 停止后如何处理 | 首次启动说明写清「清空、退出或新会话后消失」；复制是用户的主动行为 | [S65][S69] |

## 6. 开放问题

1. 在 CIPA 632 或 StGB §201 下，「只转写、不录音、会话结束丢弃」算不算「录制或窃听」？允许用户复制全文，会不会改变结论？需要律师意见。
2. PIPL 第 72 条的「个人事务」能否覆盖「我自己听会时用的辅助工具」？
3. macOS 26/27 上，`.none` 在 Zoom、Meet、Teams、腾讯会议、飞书中的实际表现如何？FB21115847 能否复现？建议自建测试工具，每次系统大版本升级后重测。
4. `.statusBar` 层级在全屏 Zoom、Keynote 演示者视图、全屏视频上是否可见？会不会与系统通知横幅冲突？
5. 合盖外接屏，或者主屏不是带刘海的内建屏时，默认显示在哪个屏幕？跟随菜单栏、跟随鼠标，还是跟随会议窗口？
6. 刘海只有 1–2 行时，要不要显示临时文字？还是只显示已确认文字、牺牲约 1 秒延迟换取稳定？需要和 Murmo、AirTranslate 对照实测。
7. 端侧模型能否稳定输出带证据 ID 的结构化结果？如果不能，校验降级（删字段、降为「提议」）的比例会有多高？
8. 「默认不落盘」如何验收？崩溃报告、系统日志、交换分区、剪贴板历史工具是否会留下转写文字？

## 7. 建议的 PRD 修改（只是建议，本 PR 不改 PRD.md）

- **产品范围 · 看字幕**：在「刘海附近显示一两行」后补充「左对齐、按行滚动；已确认文字不再变化，临时文字只出现在末尾并弱化显示；行宽按像素计算，中英混排都适用」。
- **产品范围 · 摘要内容**：补充「负责人、期限必须能在所引原话中找到，否则省略该字段；『决定』必须有明确表态的原话，否则写成『提议』；不得把原话中的不确定语气改成肯定」。
- **产品范围 · 结束／隐私**：补充「首次启动说明音源、处理位置、保留期限，并提醒部分地区需要告知他人；提供可复制的告知文案；开启麦克风时再次提示」。
- **实现决策**：补充「字幕条和回看面板分成两个非激活面板：字幕条点击穿透、永不成为 key；无刘海的屏幕自动改用浮层；监听屏幕变化」。
- **验收 · 字幕可读**：在「检查全屏和外接屏」后补充「显示器热插拔、『显示器具有单独的空间』开或关、减少动态效果」。
- **验收 · 摘要可信**：补充「抽查引用是否**支持**所在要点，而不只是存在；分别统计『提议被升级为决定』『负责人或日期不在原话中』」。
- **暂不做**：在屏幕共享隐藏一句后补充「如果以后提供，标注为『尽量隐藏、不保证』；对外不宣称不可见；建议用户共享单个窗口」。
- **后续决策**：增加「全体同意地区（加州、德国等）是否需要更强的应用内告知，待法律意见」。

---

## 来源

全部访问于 2026-11-12。

**窗口、浮层与屏幕共享**
- [S1] Apple, `NSWindow.SharingType.none`：https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum/none
- [S2] Apple, `NSWindow.sharingType`：https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.property
- [S3] electron/electron #48258：https://github.com/electron/electron/issues/48258
- [S4] tauri-apps/tauri #14200：https://github.com/tauri-apps/tauri/issues/14200
- [S5] ApoorvDixitt/Skia #3（macOS 26.5 实测）：https://github.com/ApoorvDixitt/Skia/issues/3
- [S6] Natively-AI-assistant/natively-cluely-ai-assistant #140：https://github.com/Natively-AI-assistant/natively-cluely-ai-assistant/issues/140
- [S7] YosukeIida/sokki #116：https://github.com/YosukeIida/sokki/issues/116
- [S8] Apple, `SCContentFilter.init(desktopIndependentWindow:)`：https://developer.apple.com/documentation/screencapturekit/sccontentfilter/init(desktopindependentwindow:)
- [S9] Apple, `SCContentFilter.init(display:excludingWindows:)`：https://developer.apple.com/documentation/screencapturekit/sccontentfilter/init(display:excludingwindows:)
- [S10] MrKai77/DynamicNotchKit：https://github.com/MrKai77/DynamicNotchKit/blob/main/Sources/DynamicNotchKit/Utility/DynamicNotchPanel.swift ，https://github.com/MrKai77/DynamicNotchKit/blob/main/Sources/DynamicNotchKit/DynamicNotch/DynamicNotch.swift ，https://github.com/MrKai77/DynamicNotchKit/blob/main/Sources/DynamicNotchKit/Utility/NSScreen+Extensions.swift
- [S11] TheBoredTeam/boring.notch：https://github.com/TheBoredTeam/boring.notch/blob/main/boringNotch/components/Notch/BoringNotchWindow.swift ，https://github.com/TheBoredTeam/boring.notch/blob/main/boringNotch/components/Notch/BoringNotchSkyLightWindow.swift
- [S12] Lakr233/NotchDrop：https://github.com/Lakr233/NotchDrop/blob/main/NotchDrop/NotchWindow.swift ，https://github.com/Lakr233/NotchDrop/blob/main/NotchDrop/NotchWindowController.swift
- [S13] ShinoKana/audicap：https://github.com/ShinoKana/audicap/blob/HEAD/AudicapApp.swift ，https://github.com/ShinoKana/audicap/blob/HEAD/Recognizer.swift
- [S14] Apple, `.nonactivatingPanel`：https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel
- [S15] Apple, `ignoresMouseEvents`：https://developer.apple.com/documentation/appkit/nswindow/ignoresmouseevents
- [S16] Apple, `becomesKeyOnlyIfNeeded`：https://developer.apple.com/documentation/appkit/nspanel/becomeskeyonlyifneeded
- [S17] Apple, `isFloatingPanel`：https://developer.apple.com/documentation/appkit/nspanel/isfloatingpanel
- [S18] Apple, `.fullScreenAuxiliary`：https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreenauxiliary
- [S19] Apple, `.canJoinAllSpaces`：https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallspaces
- [S20] Apple, `.stationary`：https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/stationary
- [S21] Apple, `NSWindow.Level`：https://developer.apple.com/documentation/appkit/nswindow/level-swift.struct
- [S22] Apple, `NSScreen.safeAreaInsets`：https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets
- [S23] Apple, `NSScreen.main`：https://developer.apple.com/documentation/appkit/nsscreen/main
- [S24] Apple, `didChangeScreenParametersNotification`：https://developer.apple.com/documentation/appkit/nsapplication/didchangescreenparametersnotification
- [S25] Apple, `NSScreen.screensHaveSeparateSpaces`：https://developer.apple.com/documentation/appkit/nsscreen/screenshaveseparatespaces
- [S26] Apple, `accessibilityDisplayShouldReduceMotion`：https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshouldreducemotion
- [S27] Murmo 官网（页面文字来自其前端包 `/assets/index-CmVJnazZ.js`）：https://murmo.app/

**字幕可读性**
- [S28] Apple, Get captions of spoken and computer audio on Mac：https://support.apple.com/guide/mac-help/use-live-captions-mchldd11f4fd/mac
- [S29] Apple, `SpeechTranscriber.ReportingOption.volatileResults`：https://developer.apple.com/documentation/speech/speechtranscriber/reportingoption/volatileresults
- [S30] Apple, `SpeechAnalyzer`：https://developer.apple.com/documentation/speech/speechanalyzer
- [S31] BBC Subtitle Guidelines：https://www.bbc.co.uk/accessibility/forproducts/guides/subtitles/
- [S32] Netflix, Chinese (Simplified) Timed Text Style Guide：https://partnerhelp.netflixstudios.com/hc/en-us/articles/215986007-Chinese-Simplified-Timed-Text-Style-Guide
- [S33] Netflix, Chinese (Traditional) Timed Text Style Guide：https://partnerhelp.netflixstudios.com/hc/en-us/articles/215994807-Chinese-Traditional-Timed-Text-Style-Guide
- [S34] Netflix, English (USA) Timed Text Style Guide：https://partnerhelp.netflixstudios.com/hc/en-us/articles/217350977-English-USA-Timed-Text-Style-Guide
- [S35] DCMP Captioning Key – Presentation Rate：https://dcmp.org/learn/601-captioning-key---presentation-rate
- [S36] DCMP Captioning Key – Elements of Quality Captioning：https://dcmp.org/learn/599-captioning-key---elements-of-quality-captioning
- [S37] 47 CFR §79.1（Cornell LII）：https://www.law.cornell.edu/cfr/text/47/79.1
- [S38] W3C, Understanding SC 1.2.4 Captions (Live)（GitHub 源文件；w3.org 有反爬验证）：https://github.com/w3c/wcag/blob/main/understanding/20/captions-live.html
- [S39] Liu et al., Modeling and Improving Text Stability in Live Captions, CHI EA 2023：https://doi.org/10.1145/3544549.3585609
- [S40] Arivazhagan et al., Re-Translation Strategies for Long Form, Simultaneous, Spoken Language Translation, ICASSP 2020：https://doi.org/10.1109/icassp40776.2020.9054585
- [S41] Arivazhagan et al., Re-translation versus Streaming for Simultaneous Translation, IWSLT 2020：https://doi.org/10.18653/v1/2020.iwslt-1.27
- [S42] Arkhangorodsky et al., MeetDot, EMNLP 2021 Demo：https://doi.org/10.18653/v1/2021.emnlp-demo.23
- [S43] Berke et al., Preferred Appearance of Captions Generated by ASR for DHH Viewers, CHI EA 2019（只看了标题）：https://doi.org/10.1145/3290607.3312921

**补进度与摘要可信**
- [S44] Asthana et al., Summaries, Highlights, and Action Items: … LLM-powered Meeting Recap System, PACM HCI 2025：https://doi.org/10.1145/3711074 （全文：https://arxiv.org/abs/2307.15793 ）
- [S45] EngageSync / Since U Been Gone, arXiv 2025：https://arxiv.org/abs/2503.16739
- [S46] Minuteman, arXiv 2023：https://arxiv.org/abs/2309.05272
- [S47] Tang et al., TofuEval, arXiv 2024：https://arxiv.org/abs/2402.13249
- [S48] Ramprasad et al., Analyzing LLM Behavior in Dialogue Summarization, arXiv 2024：https://arxiv.org/abs/2406.03487
- [S49] Liu, Zhang, Liang, Evaluating Verifiability in Generative Search Engines, Findings of EMNLP 2023：https://arxiv.org/abs/2304.09848
- [S50] Ding et al., Citations and Trust in LLM Generated Responses, arXiv 2025：https://arxiv.org/abs/2501.01303
- [S51] Epistemic Erosion: An Error Class Beyond Hallucination in LLM Text Generation, AACL 2026：https://doi.org/10.18653/2026.aacl-long.223
- [S52] Fernández et al., Modelling and Detecting Decisions in Multi-party Dialogue, SIGdial 2008（只看了元数据）：https://aclanthology.org/W08-0125/

**法律**
- [S53] 18 U.S.C. §2511：https://www.law.cornell.edu/uscode/text/18/2511
- [S54] Digital Media Law Project, Recording Phone Calls and Conversations：https://www.dmlp.org/legal-guide/recording-phone-calls-and-conversations
- [S55] California Penal Code §632：https://california.public.law/codes/penal_code_section_632
- [S56] California Penal Code §631：https://california.public.law/codes/penal_code_section_631
- [S57] In re Otter.ai Privacy Litigation, 5:25-cv-06911 (N.D. Cal.) 案卷：https://www.courtlistener.com/docket/71118721/in-re-otterai-privacy-litigation/
- [S58] 同案 Doc. 68，Order Granting in Part Motion to Dismiss（2026-08-13）：https://www.courtlistener.com/docket/71118721/68/in-re-otterai-privacy-litigation/
- [S59] GDPR 第 2 条：https://gdpr-info.eu/art-2-gdpr/
- [S60] GDPR 序言第 18 条：https://gdpr-info.eu/recitals/no-18/
- [S61] 德国刑法 §201：https://www.gesetze-im-internet.de/stgb/__201.html
- [S62] 《中华人民共和国个人信息保护法》（国家网信办全文）：http://www.cac.gov.cn/2021-08/20/c_1631050028355286.htm

**竞品披露**
- [S63] Apple, Record and transcribe a call on iPhone：https://support.apple.com/guide/iphone/iph57c6590e9/ios
- [S64] Microsoft, View live transcription in Teams meetings：https://support.microsoft.com/en-us/office/view-live-transcription-in-microsoft-teams-meetings-dc1a8f23-2e20-4684-885e-2152e06a4a8b
- [S65] Microsoft, Use live captions in Teams meetings：https://support.microsoft.com/en-us/office/use-live-captions-in-microsoft-teams-meetings-4be2d304-f675-4b57-8347-cbd000a21260
- [S66] Google Meet Help, "Take notes for me"：https://support.google.com/meet/answer/14754931
- [S67] Otter, Recording Permissions with Otter：https://help.otter.ai/hc/en-us/articles/39339238308503-Recording-Permissions-with-Otter
- [S68] Otter, Otter Desktop App (Mac & Windows)：https://help.otter.ai/hc/en-us/articles/35973988280215-Otter-Desktop-App-Mac-Windows
- [S69] Granola, How to transcribe a Zoom meeting without recording it：https://www.granola.ai/blog/how-to-transcribe-a-zoom-meeting-without-recording-it-3-ways-that-work-in-2026
