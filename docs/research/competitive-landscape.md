# 竞品调研：Mac 实时字幕与会中补进度

状态：调研稿 · 2026-11-12 · 对应 [PRD.md](../../PRD.md)、issue #1

本文所有事实都标了来源编号 `[n]`，完整链接见文末「来源」，访问日期均为 2026-11-12。来源主要是官方产品页、帮助中心、定价页和 GitHub README。没能从公开资料确认的内容标为「未核实」。价格以访问当天页面显示为准，可能因地区和年付或月付不同而变化。本次没有实际安装和试用这些产品，交互描述来自文档，不代表实测体验。

## 一、关键结论

1. **「刘海 + 本地字幕 + 端侧会中总结」已经有人做了。** NotchLive 把刘海（或屏幕顶部中央）当作字幕区，用本地 Whisper 或 Apple 语音模型转写。它的 Pro 版用 Apple Intelligence 模型在本机生成「current focus、key points、open questions、action items」，而且不录音也能分析实时字幕 [33][34]。Murmo 也住在刘海里，本地字幕永久免费，AI 总结走云端，每月 6 美元 [3]。因此我们的差异化不能靠「刘海字幕」或「本地总结」本身。
2. **「按一次键补上最近几分钟，每条都能点回原话」仍是空位。** 能在会中补进度的产品都绑定自家会议平台，并且依赖云端和企业授权，包括 Google Meet「Summary so far」[15]、Teams Copilot [16]、Zoom in‑meeting questions [17]、飞书 AI 总结和 AI 视图 [30][31]、腾讯会议元宝笔记和问元宝 [26][27]。跨平台的 Mac 字幕应用（Murmo、NotchLive、AirTranslate、Apple 实时字幕）在公开资料里都没有「固定时间窗摘要 + 原话证据」的设计 [1][3][5][34]。
3. **证据回链已经是行业惯例，但集中在云端和会后场景。** Granola 每条增强笔记旁有放大镜，可查看它来自逐字稿哪里 [14]。腾讯问元宝写明「时间戳一键溯源，点击回到现场，用原文验证 AI」[27]。飞书 AI 视图的节点可「进一步查看信息来源」[31]。Teams Copilot 的回答会注明引用来源 [16]。Zoom 提供 meeting citations [17]。在端侧、会中、跨会议平台的组合里，还没有看到同类做法。
4. **中英混说是大平台的短板，也是我们的机会。** Google Meet「Take notes for me」不支持中文，并明确说明同一场会议不支持多种语言 [15]。飞书字幕可自动识别中、英、日三种语言 [28]，但只能在飞书会议里用。Granola 桌面端开启多语言转写后，可以在会中切换语言，包括 Mandarin 和 Cantonese，不过转写由云端供应商完成 [10][13]。PRD 选定的底座 Audicap 在 Auto 模式下，最多可同时运行 5 个语言识别器，再按句子置信度选择结果；其中 ja/en/zh‑Hans 已在真实会议中测过 [36]。
5. **本地字幕已是免费的基础能力。** Apple 实时字幕内置在系统里且在本机处理 [1]，Murmo 字幕免费 [3]，AirTranslate 开源且可免费下载 [5]，NotchLive 的 Free 版也包含本地字幕 [33]。按时长收费的云端字幕产品，例如 LiveCaptions 的 10 小时套餐为 4.99 美元/月 [2]，在隐私和价格上都不占优。我们的价值需要落在「补进度」上。
6. **屏幕共享时隐藏字幕，竞品已经当作卖点。** Murmo 有 Stealth mode [3]，NotchLive 有 Ghost Mode [33]。飞书说明桌面端共享屏幕时，其他人看不到你开启的字幕 [28]。PRD 目前把这项放在「后续验证」，优先级可能偏低。
7. **会议纪要工具已经从「会后纪要」扩展到「会中提问」，但大多需要账号和云端，部分还要机器人入会。** Otter 和 Fireflies 的机器人可以自动加入会议，也提供无机器人的桌面端或浏览器录制 [20][22]。Granola 不派机器人，但数据存放在美国 AWS [12]。Otter 的 Live‑Assist 和 ZoomMate 的 agent 已经在做会中教练和工作流 [20][18]。这些方向与 PRD「暂不做」的范围一致，不建议追。

## 二、对比总表

说明：「会中补进度」指会议进行中查看「刚才说了什么」的能力；「证据回链」指摘要能否定位到原话。

| 产品 | 采集方式 | 端侧 / 云端 | 中英混说 | 会中补进度 | 证据回链 | 浮层 / 刘海 | 价格 | 隐私要点 |
|---|---|---|---|---|---|---|---|---|
| Apple 实时字幕 [1] | 系统音频或麦克风二选一 | 端侧 | 未核实（文档只写「并非所有语言可用」） | 无摘要，只有字幕窗 | 无 | 可移动、可缩放的窗口；无音频时自动隐藏 | 系统内置 | 「Audio is processed on device」 |
| Murmo [3][4] | 系统音频，任意 App | 字幕端侧；AI 总结云端 | 未核实 | 未见会中摘要；会后要点、任务、决定 | 未核实 | **刘海**；Stealth mode | 字幕免费；Pro 6 美元/月或 60 美元/年 | 只有请求总结时才把内容发给 AI 服务商；匿名使用统计 |
| NotchLive [33][34][35] | App 和媒体、我的声音、全部；系统与麦克风分两条时间线 | 端侧（Whisper 或 Apple 语音；总结用 Apple Intelligence） | 自动识别语言（Whisper）；混说效果未核实 | **有**：Meeting Intelligence 显示 current focus、key points 等，可手动或自动运行 | 未核实（文档提到 key moments，没写点击回到原话） | **刘海或屏幕顶部中央**；Ghost Mode | Free 版有本地字幕；Pro 价格未核实（定价页需 JS 渲染） | 音频不上传；匿名诊断默认开启，可关闭 |
| AirTranslate [5] | ScreenCaptureKit 系统音频和麦克风 | 默认端侧（Apple Speech/Translation）；可选自带 key 的云端引擎 | Apple 模式需选源语言；云端如 Gemini 可自动检测；混说效果未核实 | 无摘要 | 无 | 纯文字浮层，无内容时隐藏；⌘⇧C 开关 | 免费开源（Apache‑2.0） | 默认不保存逐字稿文件 |
| LiveCaptions.app [2] | 整机、单个 App 或麦克风 | **云端**语音识别 | 未核实 | 无摘要 | 无 | 透明、置顶、点击穿透的浮层 | 4.99 美元/10 小时、9.99 美元/28 小时、19.99 美元/60 小时（每月） | 音频实时发往识别服务商，声称不存储 |
| MacWhisper [6][7] | 录制会议（检测 Zoom、Teams 等）、App 音频、文件 | 本地 Whisper/Parakeet；AI 可选本地（Ollama）或云端 | 支持 100 种语言；混说未核实 | 无（会议录完后再转写） | 未核实 | 无 | 免费版；Pro 一次买断 64 欧元 | 本地模型；会议录音存在应用内 |
| Granola [8]–[14] | 系统音频和麦克风，无机器人；无法单独采集某个 App | **云端**转写和 LLM | 桌面端「多语言转写」可在会中切换；支持 Mandarin、Cantonese | 有：会中可对本场会议提问，帮助中心列出「Catching up on what you missed」用途 | **有**：笔记旁的放大镜可看出处（会后笔记） | 浮动的「live meeting indicator」 | Basic 0 美元；Business 14 美元；Enterprise 35 美元（每人每月） | 数据在美国 AWS；转写后删除音频；可关闭用于训练 |
| Otter [20][21] | 机器人入会，或桌面端和 Chrome 无机器人录制 | 云端 | 「multiple languages」；中文未核实 | 有：Ask Otter、Live‑Assist 实时教练 | 未核实 | 无 | Basic 免费（300 分钟/月）；Pro 16.99 美元/月；Business 30 美元/月 | 云端账号体系 |
| Fireflies [22] | 机器人（fred@fireflies.ai），或 Chrome 扩展、桌面端无机器人 | 云端 | 100+ 语言；Business 版有 Multi‑language Mode | 实时笔记和 Live Assist | 未核实 | 无 | Free；Pro 10 美元（年付）；Business 19 美元；Enterprise 39 美元 | 云端 |
| Fathom [23] | 未核实（定价页未写明） | 云端 | 未核实 | 会后即时总结、Ask Fathom | 未核实 | 无 | Free；Team 15 美元起 | 云端 |
| tl;dv [24] | 首页称「NO BOT REQUIRED」 | 云端 | 100+ 语言，可翻译逐字稿 | 会后生成 | 未核实 | 无 | 未核实（定价页需 JS 渲染） | GDPR、SOC2 |
| Google Meet「Take notes for me」[15] | 平台内 | 云端（Gemini） | **不支持中文；同一场会议不支持多语言** | **有**：迟到可看「Summary so far」 | 未核实 | 平台内面板 | 需要符合条件的 Workspace 或 Google AI 方案 | 管理员可要求参会者同意 |
| Teams Copilot [16] | 平台内，需转写 | 云端 | 需选择发言语言；混说未核实 | **有**：迟到超过 5 分钟主动提示补进度；私有 Copilot 面板 | **有**：会议聊天中的回答会注明来源 | 可弹出成独立窗口 | Copilot 许可或 Teams Premium | 外部组织主办的会议不可用 |
| Zoom（AI Companion → ZoomMate）[17][18][19] | 平台内；My Notes 也支持 Teams、Meet、线下会议 | 云端 | 实时翻译字幕 46 种语言；混说未核实 | **有**：in‑meeting questions（免费版每月 3 场） | **有**：Zoom 会议提供 meeting citations | 平台内 | 付费 Workplace 14.16 美元起；ZoomMate 20 美元起 | 企业管理 |
| 飞书会议、妙记 [28]–[32] | 平台内 | 云端 | **字幕自动识别中英日** | **有**：会中 AI 总结侧栏，以及 AI 视图结构化图表 | **有**：AI 视图节点可查来源；妙记点文字定位到视频 | 平台内，字幕可开独立窗口 | 智能纪要超出免费额度后另购 | 可设置仅主持人开启 AI 总结；敏感会议需谨慎 |
| 腾讯会议 AI 小助手 [25]–[27] | 平台内 | 云端（混元） | 未核实 | **有**：「不必担心走神错过关键信息」；元宝笔记会中实时推送 | **有**：「时间戳一键溯源…用原文验证 AI」 | 平台内 | 未核实 | 企业版 |
| 通义听悟 [39] | 电脑端实时记录 | 云端 | 「多语言同步翻译」；混说未核实 | 未核实 | 未核实 | 未核实 | 未核实 | 云端 |
| Audicap（PRD 底座）[36] | 系统音频 | 端侧（SpeechAnalyzer） | **Auto 模式最多 5 种语言并行，按句选择** | 无 | 无 | 菜单栏加浮层 | 免费（MIT） | 本地 |
| Meetily [37] | 麦克风和系统音频，无机器人 | 端侧转写；总结可选 Ollama 或云端 | 未核实 | 实时逐字稿，会后总结 | 未核实 | 无 | 社区版免费（MIT）；另有 PRO | 本地优先 |
| anarlog（原 Hyprnote）[38] | 设备音频，无机器人 | 端侧转写可选；总结可本地或自带 key | 未核实 | 会后笔记和聊天 | 未核实 | 无 | 开源（MIT）；有可选托管服务 | 本地 SQLite；云端需主动开启 |

## 三、分产品笔记

### A. Mac 字幕和刘海类（与我们最直接竞争）

**NotchLive（最需要关注）。** 它在刘海或屏幕顶部中央显示字幕，有 Focus 和可搜索的 Timeline 两种视图，系统音频和麦克风分两条时间线显示 [33]。转写可用 6 档本地 Whisper 模型，macOS 26 上也可用 Apple 语音 [34]。Pro 版的 Meeting Intelligence 要求 macOS 26 并启用 Apple Intelligence，可在不录音的情况下分析实时字幕，输出 current focus、key points、open questions、action items 和 key moments，可以自动运行，也可以在实时工具栏里手动触发 [34]。其他功能还包括：Ghost Mode（屏幕共享时排除窗口）、识别到会议时询问是否记录、「Start fresh…」清空当前会话，以及只读的本地 MCP [33][34]。隐私方面，音频在本机处理、不上传，但 TelemetryDeck 匿名诊断默认开启 [35]。公开文档没有写摘要能否点回原话，也没有中英混说的专门说明。**对我们的含义**：「端侧总结在 Mac 上可行」已经有产品验证。我们要在「固定时间窗、一键触发、逐条证据、区分提议和决定」这几点上明显做得更好。

**Murmo。** 定位是「Your tiny meeting sidekick living in the notch」，需要 macOS 26 和 Apple Silicon [3]。HackerChoice 的介绍说它使用 Apple 的离线语音模型 [4]。免费版提供无限本地字幕、本地存储和 Stealth mode。Pro 版每月 6 美元，提供 AI summaries 和 auto chapters，每月有 100 万 token 的合理使用上限。总结由云端 AI 服务商处理，「只有你请求时才发送」[3]。总结发生在会后（「after each meeting」），页面没有提到会中补进度 [3]。

**AirTranslate。** 开源，GitHub 上约 484 star [5]。默认走 Apple Speech 和 Apple Translation 的本地路径；云端引擎（OpenAI、Gemini、Qwen 等）需要用户自己提供 key [5]。字幕交互上有几处值得参考 [5]：
- 浮层只有文字，没有内容时不显示。
- 上一句字幕会保留 8 秒。
- 往回滚动旧字幕时，会暂停自动跟随最新内容。
- 确认后的文本会替换临时文本，已停止会话的迟到结果不会覆盖新会话。

它没有摘要功能。

**Apple 实时字幕。** 系统内置，在本机处理，可在电脑音频和麦克风之间切换。没有音频时窗口自动隐藏，也可选择常驻显示。字体、颜色、窗口大小和快捷键都能调 [1]。它没有历史回看和摘要，是我们「字幕可读」验收的天然基线。

**LiveCaptions.app。** 支持整机、单个 App 和麦克风三种采集模式，提供透明、置顶、点击穿透的浮层，可翻译成 60 种语言，并能双语显示。按时长订阅，音频发往云端识别服务商 [2]。「单个 App」采集值得参考，Granola 就明确做不到这一点 [13]。

**MacWhisper。** 主要是文件转写和会议录制：能识别 Zoom、Teams 等会议，提示用户录音，录完后再转写。其他参会者合并为一个说话人。AI 总结可接本地的 Ollama、LM Studio 或云端模型。Pro 版一次买断 64 欧元 [6][7]。它不做实时补进度。

### B. 跨平台 AI 纪要类（无机器人或机器人入会）

**Granola。** 在桌面端采集系统音频和麦克风，不派机器人。系统音频显示为灰色气泡，麦克风显示为绿色气泡。实时逐字稿面板可以搜索和复制 [13]。会中可以对本场会议提问，帮助中心把「Catching up on what you missed」列为会中用途 [11]。会议结束后生成的增强笔记里，每条旁边都有放大镜，可查看出处 [14]。多语言方面，桌面端可在会中切换语言，支持 31 种语言，包括 Mandarin 和 Cantonese [10]。数据存放在美国 AWS，转写完成后删除音频 [12]。它无法单独采集某个 App 的音频，会议期间播放的音乐也会被转写进去 [13]。价格：免费、14 美元、35 美元三档 [9]。

**Otter、Fireflies、Fathom、tl;dv。** 这几款都以云端为主。Otter 和 Fireflies 同时提供机器人入会和无机器人的录制方式 [20][22]。Otter 有 Live‑Assist 实时教练 [20]，Fireflies 有 Live Assist 和 Multi‑language Mode [22]。Fathom 和 tl;dv 主打会后即时总结 [23][24]。它们与我们的交集主要是「会后纪要」，PRD 已把这部分列为暂不做。

**开源本地派：Meetily 和 anarlog。** Meetily 约有 3.26 万 star，本地转写，总结可用 Ollama 本地模型或自选云端，有付费 PRO 版 [37]。anarlog 由原 Hyprnote 团队维护，团队现在在做 char.com。它把「转写」和「Intelligence」两项设置分开，并在设置里一直显示当前使用的服务商和模型 [38]。这两款都偏向会后笔记，不做刘海字幕或会中补进度。

### C. 会议平台内置 AI（会中补进度能力最强，但锁定在平台内）

**Google Meet。** 迟到的人可以用「Summary so far」补进度 [15]。纪要的 Decisions 部分会给每个决定标状态：Aligned、Needs Further Discussions、Disagreed、Shelved [15]。限制是只支持 8 种语言、不含中文，同一场会议也不支持多语言 [15]。

**Microsoft Teams Copilot。** 迟到超过 5 分钟时，会主动提示帮你补进度。Copilot 在私有面板里，可以弹出成独立窗口 [16]。会议聊天中的回答会注明引用来源 [16]。需要开启转写或选择「仅会中」模式，并且需要相应许可 [16]。

**Zoom。** In‑meeting questions 免费版每月可用 3 场，付费版不限场次。Zoom 会议提供 meeting citations [17]。ZoomMate 正转向 agent 和工作流方向，起价 20 美元/人/月 [18]。

**飞书。** 实时字幕能自动识别中、英、日，会中可以检索全部历史字幕，并按发言人筛选 [28]。开启 AI 总结后，右侧面板会实时展示总结 [30]。AI 视图（V7.50 及以上）把会议信息做成结构化图表，节点可以查看信息来源 [31]。妙记里点击任意文字，可定位到视频对应位置 [32]。限制是只能在飞书会议里用，超出免费额度需另外购买 [29]。

**腾讯会议。** AI 小助手 Pro「根据当前会中的实时讨论进行回答……不必担心走神错过关键信息」。有人提到「我」、你关注的发言人或话题时，会主动提醒 [25]。元宝笔记会根据当前讨论实时刷新结论和待办 [26]。问元宝支持「时间戳一键溯源，点击回到现场，用原文验证 AI」[27]。AI 托管可以在你临时离开时继续记录 [27]。

## 四、PRD 可以占据的空位

1. **跨会议平台、无机器人、一键补上「最近 N 分钟」。** 平台内置的方案能补进度，但只限自家平台，并且需要企业许可 [15][16][17][29]。跨平台的 Mac 字幕应用还没有固定时间窗的一键摘要 [3][5][34]。
2. **端侧完成补进度，并给出可点击的原话证据。** 证据回链目前只出现在云端或会后场景 [14][16][17][27][31]。把端侧、会中、证据三者结合起来，目前没有看到先例。
3. **严格区分「讨论、提议、决定、行动」，没有证据就不写。** Google 有决定状态分类 [15]，但不支持中文。各家对「不编造负责人或日期」都没有明确承诺；本次调研没有找到相关表述。
4. **中英混说的端侧体验。** Meet 不支持混说 [15]，飞书只在自家平台可用 [28]，Granola 依赖云端 [10]。Audicap 的并行识别方案 [36] 是端侧路线里少见的现成实现。
5. **默认不落盘。** Granola 把数据存在云端 [12]，Murmo 有本地存储 [3]，NotchLive 只在用户选择记录时保存会话 [34]。「停止后可复制，清空即消失」可以讲成一个清楚的隐私卖点。

## 五、值得借鉴

- **逐条证据入口**：参考 Granola 每条笔记旁的放大镜 [14]，以及腾讯「点击回到现场，用原文验证 AI」的文案 [27]。
- **决定的状态分类**：参考 Google Meet 的 Aligned、Needs Further Discussions、Disagreed、Shelved [15]，可直接映射到 PRD 用户故事 10。
- **主动提示补进度**：Teams 在迟到超过 5 分钟时会主动提示 [16]，可作为下一阶段「从上次查看到现在」的触发参考。
- **点名提醒**：腾讯在有人提到「我」或关注的话题时提醒 [25]，适合列入后续候选。
- **回看不被打断**：AirTranslate 回看时暂停自动跟随 [5]，与 PRD 用户故事 9 一致，可直接参考其实现。
- **麦克风和系统音频分开显示**：参考 Granola 的绿色与灰色气泡 [13]，以及 NotchLive 分开的两条时间线 [33]，对应 PRD 中「我」与「对方／系统」的标记。
- **共享屏幕时隐藏字幕**：参考 Murmo 的 Stealth mode [3]、NotchLive 的 Ghost Mode [33]，以及飞书在共享屏幕时不让他人看到字幕的做法 [28]。
- **始终显示当前服务商和模型**：参考 anarlog 把转写和 Intelligence 两个设置分开，并一直显示当前所用的服务商和模型 [38]，对应 PRD 用户故事 13。
- **单个 App 音源**：参考 LiveCaptions 的单 App 采集 [2]，可以避开 Granola 把会中播放的音乐也转写进去的问题 [13]。
- **无内容时自动隐藏**：参考 Apple 实时字幕 [1] 和 AirTranslate [5]，与 PRD「闲置自动收起」一致。

## 六、明确避免

- **默认把内容发往云端，或要求注册账号**：Granola 把数据存放在美国 AWS [12]；LiveCaptions 把音频发往识别服务商 [2]。这些都与 PRD 的隐私定位冲突。
- **机器人入会**：Otter 和 Fireflies 的机器人模式 [20][22]。
- **摘要在用户阅读时自动刷新**：腾讯元宝笔记会根据当前讨论实时刷新结论 [26]。这对「随时看一眼」有用，但和 PRD「当前摘要保持稳定，用户可刷新」的原则相反，首版应坚持由用户触发刷新。
- **功能膨胀**：Otter 的实时教练 [20]、腾讯识别会议氛围和多种 AI 角色 [26]、ZoomMate 的 agent 和工作流 [18]，都超出「补进度」这个核心任务。
- **按时长计费的字幕**：LiveCaptions 用完额度就暂停字幕 [2]。本地字幕应该不限时长。
- **遥测默认开启**：NotchLive 的匿名诊断默认开启 [35]。我们应在 PRD 中写明遥测立场。

## 七、对 PRD.md 的修改建议（仅建议，本 PR 不改 PRD）

1. **增加「竞品基线」小节，并更新「字幕可读」验收项的对照对象。** 现在的对照只有 Murmo 和 AirTranslate。建议加入 NotchLive 和 Apple 实时字幕：前者在刘海形态和端侧总结上与我们最接近 [33][34]，后者是系统内置的基线 [1]。「补进度」验收建议也和 NotchLive 的 Meeting Intelligence 做一次对照。
2. **把「屏幕共享时隐藏字幕」从后续验证提前到首版的 should‑have。** 理由是竞品已普遍提供 [3][28][33]。仍需验证各会议工具对窗口共享和整屏共享的实际表现，技术可行性未核实。
3. **摘要条目增加状态字段。** 把 PRD 中的「讨论、明确决定、行动」细化为：讨论、提议、已决定、有分歧或搁置、行动，参考 Google Meet 的分类 [15]。验收时专门检查「提议没有被写成决定」。
4. **写清证据的交互形态。** 每条要点至少有一个时间戳链接；鼠标悬停时预览原句；点击后在回看面板中高亮对应段落。参考 [14][27]。
5. **为中英混说写出可测的指标。** 验收样本要包含句内混说，例如「这个 PR 先 merge 再 review」。参考 Audicap Auto 模式的上限（每个 App 最多 5 个预留语言模型）[36]，在 PRD 里定下首版默认的语言组合，例如 zh‑Hans 加 en。
6. **端侧摘要的首个候选模型。** NotchLive 已用 Apple Intelligence 模型在 macOS 26 上做实时会议分析 [34]，建议 PRD 把它列为首个原型候选，并写明硬件门槛：需要支持并已启用 Apple Intelligence 的 Mac。质量和速度仍需实测，本次未核实。
7. **音源选择增加「单个 App」。** 当前 PRD 只区分系统音频和麦克风。建议增加单个 App 选项，以减少音乐、通知声等干扰 [2][13]。
8. **在「结束／隐私」中写明遥测立场。** 建议默认关闭遥测，或者默认不收集任何内容数据，并在设置中可见 [35]。
9. **为下一阶段补充「主动补进度」的触发条件。** 例如用户离开会议窗口超过 N 分钟后再回来时，提示「要看看错过的内容吗」，参考 Teams 的做法 [16]。仍保持按需生成，不在后台常驻刷新。

## 来源

访问日期均为 2026-11-12。

1. Apple Support：Get captions of spoken and computer audio on Mac — https://support.apple.com/guide/mac-help/get-captions-of-spoken-and-computer-audio-mchldd11f4fd/mac
2. LiveCaptions 官网（功能、定价、FAQ）— https://livecaptions.app/
3. Murmo 官网（文案和定价取自页面加载的 JS 资源 `/assets/index-CmVJnazZ.js`）— https://murmo.app/
4. HackerChoice：Murmo, Best Indie Products of September 15, 2025 — https://www.hackerchoice.com/indie-products/daily/2025-09-15/product/murmo-2/
5. AirTranslate README（v1.17.0）— https://github.com/himomohi/AirTranslate
6. MacWhisper 官网（功能、定价）— https://www.macwhisper.com/
7. MacWhisper Docs：Automatic Meetings Recordings — https://docs.macwhisper.com/article/30-record-meetings
8. Granola 官网 — https://www.granola.ai/
9. Granola 定价 — https://www.granola.ai/pricing
10. Granola Help：Multi-language support — https://docs.granola.ai/help-center/customising-granola/multi-language.md
11. Granola Help：Chatting with your meetings — https://docs.granola.ai/help-center/getting-more-from-your-notes/chatting-with-your-meetings.md
12. Granola Help：Security, Privacy & Data FAQs — https://docs.granola.ai/help-center/consent-security-privacy/security-privacy-data-faqs.md
13. Granola Help：How transcription works — https://docs.granola.ai/help-center/taking-notes/transcription.md
14. Granola Help：AI-enhanced notes — https://docs.granola.ai/help-center/taking-notes/ai-enhanced-notes.md
15. Google Meet Help："Take notes for me" in Google Meet — https://support.google.com/meet/answer/14754931?hl=en
16. Microsoft Support：Catch up on meetings with Microsoft Copilot in Teams — https://support.microsoft.com/en-us/teams/copilot/catch-up-on-meetings-with-microsoft-365-copilot-in-teams
17. Zoom：AI note-taking（My Notes，含与 Otter、Fathom、Granola 的对比及定价）— https://www.zoom.com/en/products/ai-assistant/features/ai-note-taking/
18. Zoom News：Zoom launches ZoomMate — https://news.zoom.com/zoom-launches-zoommate/
19. Zoom：Accessibility（实时翻译字幕 46 种语言）— https://www.zoom.com/en/products/ai-assistant/features/accessibility/
20. Otter 官网 — https://otter.ai/
21. Otter 定价 — https://otter.ai/pricing
22. Fireflies 定价 — https://fireflies.ai/pricing
23. Fathom 定价 — https://www.fathom.ai/pricing
24. tl;dv 官网 — https://tldv.io/
25. 腾讯会议 AI 小助手 Pro — https://meeting.tencent.com/ai/
26. 腾讯会议元宝笔记 — https://meeting.tencent.com/ai/summary/
27. 腾讯会议 AI 助手（智能回顾、元宝笔记、问元宝、AI 托管）— https://meeting.tencent.com/ai-tab/ai-assistant/
28. 飞书帮助中心：使用字幕功能 — https://www.feishu.cn/hc/zh-CN/articles/360045408014
29. 飞书帮助中心：在视频会议中使用智能纪要 — https://www.feishu.cn/hc/zh-CN/articles/244959839578
30. 飞书帮助中心：飞书智能伙伴使用说明书 — https://www.feishu.cn/hc/zh-CN/articles/318505042260
31. 飞书帮助中心：在视频会议中使用 AI 视图 — https://www.feishu.cn/hc/zh-CN/articles/092000440742
32. 飞书帮助中心：查看妙记 — https://www.feishu.cn/hc/zh-CN/articles/022111234449
33. NotchLive README — https://github.com/lemberalla/notchlive-releases
34. NotchLive How to use — https://notchlive.app/how-to-use
35. NotchLive Privacy — https://notchlive.app/privacy
36. Audicap README — https://github.com/ShinoKana/audicap
37. Meetily README — https://github.com/Zackriya-Solutions/meetily
38. anarlog README（原 Hyprnote）— https://github.com/fastrepl/anarlog
39. 通义听悟官网 — https://tingwu.aliyun.com/
