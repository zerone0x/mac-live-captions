# 技术可行性调研：采集、转录与端侧摘要

状态：调研结论 · 2026-11-12 · 对应 [PRD.md](../../PRD.md) 的「实现决策」与「后续决策」 · Issue #2

## 读法与方法

- 本文只依据一手资料：Apple 开发者文档、WWDC 讲稿、Apple 机器学习研究博客、开源仓库的代码与 README、模型卡和论文。所有链接的访问日期都是 **2026-11-12**，编号见文末「参考来源」。
- 标注规则：
  - **[n]**：有出处的事实。引号里的内容是原文摘录（英文保留原文）。
  - **推算**：依据有出处的数字自行计算，没有实测过。
  - **未核实**：没有找到一手资料，或资料之间互相矛盾，需要在 spike 中实测。
- 调研时 macOS 27 已经发布。PRD 的目标是 macOS 26+，所以下文会分别说明 26.x 和 27 的差异。
- 产品层面的对比见 [竞品调研](competitive-landscape.md)。本文只讨论技术上能不能做到，以及要付出什么代价。

## 结论速览

| 问题 | 结论 | 把握 |
|---|---|---|
| 能否在不用虚拟声卡、不加机器人的情况下拿到系统音频？ | 能。有两条官方路径：ScreenCaptureKit 音频（macOS 13+）和 Core Audio process tap（macOS 14.2+）。首版建议沿用 Audicap 已经跑通的 ScreenCaptureKit。 | 高 |
| Audicap 适合当底座吗？ | 适合「拆件复用」，不适合整仓 fork。采集、识别、多语种仲裁和探针这四块值得拿；界面、归档、云端校正和翻译都不要。仓库是 MIT 许可，但只有 1 位维护者、1 个 star，作者自述只在 1 台机器上测过。 | 高 |
| SpeechTranscriber 能做中英会议吗？ | 中文和英文分别都支持，但单个 transcriber 只能识别一种 locale，也**没有语种识别**。句间切换可以靠多条 locale 通道并行、按置信度仲裁来解决（Audicap 的做法）。**句内混说没有官方方案**，是最大的质量风险。 | 中 |
| 有更擅长中英混说的端侧模型吗？ | Qwen3-ASR-0.6B（Apache-2.0）官方只称支持 52 种语言和方言的语种识别，句内中英混说能力**未核实**（需 spike 实测），已有 MLX 移植。SenseVoiceSmall 可以通过 FluidAudio 在 ANE 上运行，带自动语种识别。两者都需要在 spike 中和 SpeechTranscriber 做同场对比。Whisper 不适合实时字幕。 | 中 |
| 端侧摘要能否在 10 秒内处理三分钟窗口？ | 窗口装得下：约 2–2.5K token，低于 AFM Core 4K 的上下文上限（推算）。速度取决于输出长度和机型，需要实测。用 `streamResponse` 先出第一条要点，能明显缩短体感等待。 | 中 |
| 引用能否被保证在冻结范围内？ | 能从结构上保证：在运行时用 `DynamicGenerationSchema` 加 `anyOf` 把证据 ID 限定为该窗口内的片段 ID，模型就无法编造 ID。「引用是否真的支持要点」仍需要程序校验加人工评测。 | 高（结构）／中（语义） |
| 最大的产品风险 | ① Apple Intelligence 在中国大陆不可用，而首要用户恰好是中文用户；② 句内中英混说；③ 外放时麦克风会重复收录系统声音。 | — |

---

## 1. 系统音频采集（macOS 26+）

### 1.1 两条官方路径

| 维度 | ScreenCaptureKit（SCK）音频 | Core Audio process tap |
|---|---|---|
| 入口 API | `SCStreamConfiguration.capturesAudio`，默认关闭 [7]，`SCStreamOutputType.audio` | `AudioHardwareCreateProcessTap(_:_:)` 加 `CATapDescription`，再挂到一个 aggregate device 上 [13][14][15] |
| 最低系统 | macOS 13（`capturesAudio`）[7]；macOS 15 起可在同一个 stream 里收麦克风（`captureMicrophone`、`microphoneCaptureDeviceID`）[9][11] | macOS 14.2 [13][16]（AudioCap 文档写作 14.4 [17]） |
| 采集粒度 | 音频「can only be filtered at an application level」[10]；可以用 `excludesCurrentProcessAudio` 排除自己 [8] | 可以按进程选择，也可以选「全局但排除某些进程」，例如 `init(stereoGlobalTapButExcludeProcesses:)` [14]；还能选择静音被 tap 的进程 [15] |
| 权限（TCC） | 「Screen Recording」类权限，授权结果「stored in the Screen Recording privacy setting」[10] | 必须声明 `NSAudioCaptureUsageDescription`；第一次开始从含 tap 的 aggregate device 录音时，系统才弹「system audio recording」授权框 [15][16] |
| 能否查询授权状态 | 能间接判断。`CGPreflightScreenCaptureAccess()` 可以预检，被拒时 `SCStream` 返回 `userDeclined` 错误。Audicap 据此停止重试，提示用户重开应用 [4] | **没有公开 API**。AudioCap 说「There's no public API to request audio recording permission or to check if the app has that permission」[17]。subtitles 实测发现被拒时调用全部返回成功、buffer 照常到达，但「every sample is zero」[18] |
| 授权生效时机 | 用户授权后要**重启应用**才生效（Audicap 实测）[2][4] | 授权框只在首次开始录音时出现 [15]；漏点之后没有任何报错 [18] |
| 周期性复核 | macOS Sequoia beta 期间报道为每周一次，并且每次重启后都要再确认 [12]。正式版的实际频率**未核实**（社区说法是改为每月一次，没有找到 Apple 一手资料） | 未见相关报道（**未核实**） |
| 菜单栏指示 | 采集期间系统强制显示紫色「屏幕共享」指示器（Audicap README）[2] | Audicap 认为 tap 可以避开这个指示器 [2]（**未核实**） |
| 与输出设备的关系 | Audicap 实测：切换蓝牙耳机、内置扬声器，或说话途中换输出设备，整句一个字都不丢 [4] | 跟随 tap 所绑定的设备或流 [14][15] |
| 已知问题 | 权限名义是「屏幕录制」，对字幕应用来说偏重，用户可能顾虑 | Audicap 说 tap「caused crackling playback on macOS 26.4」[2]；而 subtitles [18] 和 livesub-macos [19] 都以 tap 为主路径。两方说法矛盾，需要实测（**未核实**） |
| 现成参考 | Audicap `SCKCapture` [4]、MeetingMind [77] | insidegui/AudioCap（BSD-2-Clause）[17]、Apple 官方示例 [15]、subtitles [18]、livesub-macos [19] |

### 1.2 对 PRD 用户故事 2 的影响（「知道缺了哪项权限」）

- **SCK 更容易如实告诉用户状态**：拒绝会变成明确的错误 [4]。代价是权限名称和紫色指示器会吓到用户，而且授权后必须重启应用。
- **tap 的权限名义更贴切**（录制系统音频），但被拒时完全静默 [17][18]。只能靠「其他应用在播放，而我们只收到数字零」这样的启发式判断。subtitles 作者说这个判断「misfires at roughly one launch in four」[18]。
- 建议：首版用 SCK，并把「已授权但需重启」做成显式状态。tap 放进 spike，作为后续可能的替换路径来验证（看爆音问题、指示器和权限文案）。

### 1.3 麦克风与系统音频双路

- Audicap 的做法 [4]：系统音频走 SCK。麦克风走 `AVAudioEngine.inputNode.installTap`，并**显式绑定内置麦克风**，以免打开蓝牙耳机的麦克风后，耳机被切换到 HFP 通话模式、音质变差。它还监听 `AVAudioEngineConfigurationChange`，在配置变化时重建引擎。两路分别送进各自的 `Recognizer`，转录条目用 `mic: Bool` 标记来源。这和 PRD 中「我」与「对方／系统」的划分一致 [1]。
- macOS 15 起，SCK 本身也能在同一个 stream 里收麦克风（`captureMicrophone`、`SCStreamOutputType.microphone`）[9][11]。这样两路共用一条时间轴，但 Audicap 没有采用（原因**未核实**）。
- 资源上限：`SpeechAnalyzer` 文档说系统会限制同时进行的分析数量，超出时抛 `insufficientResources`。可以用 `ignoresResourceLimits` 绕过，但要自行测试 [24]。如果「系统＋麦克风」各跑 zh／en 两条通道，就是 4 个 analyzer。Audicap 实测三路并行时 RSS 只多出约 8 MB，墙钟时间 1.18 s 对比单路 1.07 s [3]，但它没有测过 4 路以上（**未核实**）。

### 1.4 外放时的回声与重复

问题在于：用户用内置扬声器开会时，麦克风会把对方的声音再收一遍，同一句话就会以「对方」和「我」两个身份各出现一次。Audicap 的麦克风通道**没有任何回声处理**（代码里没有 voice processing 或 AEC 相关逻辑）[4]。

可选的缓解手段：

1. **系统 voice processing**：`AVAudioIONode.setVoiceProcessingEnabled(_:)` [20]。subtitles README 写道：麦克风「is recorded through macOS voice processing, which cancels whatever the Mac plays」[18]。这是第三方的说法（**未核实**）。另外，开启 voice processing 后，其他音频可能被压低音量（ducking），Apple 为此提供了 `voiceProcessingOtherAudioDuckingConfiguration` [20]。会议声音被压低会直接伤害主路径，必须实测。
2. **神经网络 AEC**：FluidAudio 的 LocalVQE（Apache-2.0，4.8M 参数）。输入是 16 kHz 麦克风信号加「far-end reference」，算法延迟 16 ms，目前标注为 beta，「Not yet exercised inside production call pipelines」[22]。SCK 拿到的系统音频正好可以作为 reference。
3. **文本层去重**：如果一条麦克风片段与时间重叠的系统片段文本高度相似（比如归一化编辑距离很小），就丢弃这条麦克风片段。这是自行设计的兜底方案（推算），实现最便宜，但对「我复述对方」这种情况会误删。
4. **产品层**：检测到输出设备是内置扬声器时，提示用户戴耳机，或者默认不开麦克风。PRD 已经规定默认只收系统音频 [1]。

### 1.5 采集结论

- 首版：SCK 系统音频（复用 Audicap `SCKCapture`），麦克风可选，并沿用「绑定内置麦克风」的策略。回声先用 voice processing，再加文本去重兜底；两者都要在 spike 中量化。
- 后续：如果 process tap 在 26.x 和 27 上没有爆音，再评估是否换成 tap，以获得更贴切的权限文案并去掉紫色指示器。

---

## 2. Audicap 评估

### 2.1 基本情况

- 许可证是 MIT（`LICENSE`：Copyright (c) 2026 ShinoKana）[2]。截至访问日，仓库 1 个 star，最近一次推送是 2026-10-03 [5]。README 自述「so far it has only been tested on one machine」[2]。
- 构建方式是 `swiftc` 直接编译 6 个 Swift 文件，用自签证书 codesign，没有 Xcode 工程，也没有 SwiftPM [5]。`AudicapApp.swift` 有 2016 行，把采集、浮层、转录面板、设置、归档和翻译都放在同一个文件里 [4]。
- 功能 [2]：在 SCK 系统音频上运行 SpeechAnalyzer。Auto 模式下最多 5 种语言并行，逐句按置信度仲裁。可选功能包括 Apple Translation 翻译、OpenRouter 上的 Gemini 云端音频校正、每场会议归档 `.txt`／`.md`／`.wav`，以及会后外部脚本整理。

### 2.2 复用与丢弃

| 模块 | 位置 | 建议 | 理由 |
|---|---|---|---|
| `SCKCapture` | `AudicapApp.swift` 约 297–437 行 | **复用** | 用真实的 ASBD 建 buffer，不假设格式；被拒后不重连（重连只会反复弹框）；输出设备变化后 4 秒内没有回调就重建 stream；16 kHz 单声道；排除自身音频 [4] |
| `MicCapture` 和 `builtInInputDeviceID()` | 同上，约 248–485 行 | **复用** | 绑定内置麦克风，监听配置变化 [4] |
| 权限辅助 | `screenRecordingGranted()`、打开系统设置的 URL [4] | **复用** | 直接对应用户故事 2 |
| `Recognizer`（多 locale 通道、逐句仲裁、`scriptFamily`） | `Recognizer.swift` [3] | **复用并精简** | 有界 `AsyncStream(.bufferingNewest(4000))` 保证采集回调不被阻塞；仲裁规则全部有实测注释；`Result.range` 用的是音频时间轴 [3] |
| `speechprobe` | `speechprobe.swift` [5] | **复用** | 能列出 `supportedLocales`／`installedLocales`，并按 wav 测量各通道的延迟、置信度和 RSS，正好是 spike 需要的工具 |
| `tests/` | `test_langhint.swift`、`test_script.swift` [5] | 复用 `test_script` | 文字体系判定的单元测试 |
| 浮层、转录面板、设置 | `AudicapApp.swift` [4] | **丢弃** | PRD 要重新设计刘海字幕和回看面板 [1] |
| `TapeRecorder`（wav 归档） | `Refine.swift` [5] | **丢弃** | 违背 PRD「默认不录音、不落盘」[1] |
| `CloudCorrect`（音频上传到 Gemini） | `CloudCorrect.swift` [5] | **丢弃** | PRD 规定绝不发送音频 [1] |
| whisper 精修、会后脚本 | `Refine.swift`、`AudicapApp.swift` [2][5] | **丢弃** | 不在首版范围内 |
| `Entry.text` 可以被「精修」就地改写 | `AudicapApp.swift` [4] | **改造** | PRD 要求确认后的片段稳定、引用可回溯 [1]，所以片段必须不可变 |
| Translation 层 | `AudicapApp.swift` [4] | 暂不需要 | PRD 把实时翻译列为暂不做 [1] |

### 2.3 Audicap 的实测结论（作者本人测得，一台机器，**本项目未复现**）

- SpeechAnalyzer 对比 whisper 流式：速度 60–97× 实时对 3×，RSS 增加约 8 MB 对 1.5 GB；SpeechAnalyzer 原生按句断句并带标点，静音时不产生幻觉。短应答（「はい」「Yes」）whisper 漏掉 40–62% [3]。
- 多通道仲裁：「攒 0.35 s 再挑」的方案行不通，因为各通道的断句边界和到达时间相差好几秒；后来改成按音频区间分组，等其他通道最多 1 s（低置信时最多再等 2 s）[3]。
- 置信度分离度：中日混合素材上，正确通道的领先幅度最小是 0.16；英语通道在中日内容上只有 0.01–0.03 [3]。带口音的英语是难点：日本口音的英语在英语通道只得到 0.18 [2]。
- `AssetInventory` 名额：超过上限时报「Too many allocated locales, 5 maximum」，而且名额跨次运行一直保留，需要主动 `release` [3]。

---

## 3. 转录：SpeechAnalyzer／SpeechTranscriber 与备选方案

### 3.1 文档确认的行为

- **结构**：`SpeechAnalyzer` 是一个 actor，负责持有模块、接收输入和控制分析。转录模块是 `SpeechTranscriber`。输入和输出都是 `AsyncSequence`。「The analyzer can only analyze one input sequence at a time」[24]。
- **volatile 与 final**：开启 `.volatileResults` 后，「The transcriber will deliver several results for an audio range as it refines the transcription」[26]。`volatileRange` 文档写明：「results that lie outside the volatile range will not be replaced. The application can safely consolidate results that lay outside the range」[29]。这正好对应 PRD 的要求：临时字幕允许修订，确认字幕保持稳定 [1]。WWDC 示例提醒，收到 final 后要清空 volatile 文本，「If we don't clear out our volatile results, we could end up with duplicates」[32]。
- **低延迟开关**：`.fastResults` 会「reduces result latency by using a smaller "context window"」，代价是准确率 [26]。预设 `progressiveTranscription` 和 `timeIndexedProgressiveTranscription` 同时开启 volatile 与 fast [27]。
- **时间戳**：每个 `Result` 都有 `range`（音频时间区间）和 `isFinal`。开启 `.audioTimeRange` 后，文本的 AttributedString 会带上逐段的 `TimeRangeAttribute`；开启 `.transcriptionConfidence` 后会带上 `ConfidenceAttribute` [25][28]。Audicap 就是用 `r.range` 作为片段的音频时间轴 [3]。
- **控制节奏**：`finalize(through:)` 可以强制输出某个时刻之前的结果；`prepareToAnalyze(in:)` 用于预热；`ModelRetention` 控制模型缓存 [24]。
- **资产与离线**：模型由系统下载并在应用之间共享；「Once assets are downloaded, they persist between app launches」；系统可能对长期不用的资产取消订阅 [30]。名额 `maximumReservedLocales`「may vary between devices according to storage space」[30]，Audicap 实测值为 5 [2]。WWDC 讲稿说模型「operates entirely on-device」[32]。Argmax 指出模型并没有预装，需要下载 [33]。
- **语种**：SpeechTranscriber 初始化时只接收**一个** locale [25]。Argmax 的功能对比表里，SpeechAnalyzer 的「Language Detection」一栏是「–」，当时支持的语言数是 10（macOS 26 beta 1）[33]。swift-speech-lanes 也写明它「has no audio language detection, and each transcriber covers a single locale」[35]。截至访问日，Speech 框架的文档目录里仍然只有 `SpeechTranscriber`、`DictationTranscriber` 和 `SpeechDetector` 三个模块，没有语种识别模块 [24]。
- **支持的 locale**：官方文档没有静态列表，只能在运行时读取 `supportedLocales` [25]。Audicap 在代码注释里说有「30 个 locale」，可选项包括 `zh-CN`、`zh-TW`、`yue-CN`、`en-US` 等，并在真实会议上测过 zh-CN [2][3]。**完整列表未核实**，spike 第一天用 `speechprobe locales` 在目标机器上导出。
- **自定义词汇**：`DictationTranscriber` 支持 `AnalysisContext.contextualStrings` 和 `SFSpeechLanguageModel` 自定义词汇 [31]。Argmax 2025-06 指出，新的 SpeechAnalyzer（SpeechTranscriber）缺少 Custom Vocabulary，关键词识别反而不如旧的 SFSpeechRecognizer [33]。这一点对人名、产品名等专有名词的召回有影响。

### 3.2 速度与准确率（第三方数据）

| 来源 | 设置 | 结果 |
|---|---|---|
| Argmax [33] | M4 Mac mini，macOS 26 beta 1，earnings22 的 10% 子集（英语会议） | SpeechTranscriber WER 14.0%，速度因子 70；whisper-small.en 12.8% / 35；whisper-base.en 15.2% / 111 |
| MacStories [34] | 34 分钟视频，用 Yap（SpeechTranscriber）对比 MacWhisper | Yap 45 秒，MacWhisper Large V3 Turbo 1 分 41 秒，即 2.2 倍速，「no noticeable difference in transcription quality」 |
| Audicap [3] | 90 秒真实录音，流式 | 60–97× 实时，RSS 增加 8 MB |

以上都是吞吐数据，**不是流式延迟**（说话结束到出现 final 的时间）。文档没有给出流式延迟。Audicap 的仲裁会让 final 额外等 1–3 s [3]。**流式延迟未核实**，必须在 spike 中实测。

### 3.3 中英混说

- **句间切换**（一句中文、一句英文）：可以用 zh-CN 和 en-US 两条通道并行，逐句按置信度仲裁。Audicap 在中日混合素材上「六次比较全部选对」[3]。中英组合 Audicap 也测过（一段英语：en 0.870 / zh 0.584 / ja 0.528）[3]。
- **句内混说**（「我们先 review 一下这个 PR」）：每条通道都只用自己的语言模型去解码整句，最后只有一条通道胜出 [3][35]。swift-speech-lanes 写道：「Phrases in the other language survive only as well as the winning engine handles them」[35]。zh-CN 模型对夹杂的英文词处理得如何，**没有资料，未核实**。这是 PRD 用户故事 11 的核心风险 [1]。
- 学界背景：句内 code-switching 对单语或通用多语模型都难。Whisper-large-v3 等基础模型在 Mandarin-English CS 语料上「had unsatisfactory performances on modeling intra-sentential code-switching」[37]；CS-Dialogue 数据集也表明 Whisper「still have the space to improve」[38]。Apple 自己的 code-switching 研究原型注明「currently not in production」[36]。

### 3.4 备选引擎

| 引擎 | 许可证 | 中文 / 中英混说 | 流式 | Apple Silicon 速度（来源） | Swift 集成 |
|---|---|---|---|---|---|
| **SpeechTranscriber** | 系统自带 | zh-CN 支持；每个 transcriber 单 locale，无语种识别 [25][33] | 原生支持，有 volatile 与 final [26] | 70× (M4) [33]，60–97× [3] | 原生 |
| **Qwen3-ASR-0.6B / 1.7B** | Apache-2.0 [48][49][78] | 52 种语言和方言，自带语种识别 [48][78]；官方资料没有对句内 code-switching 作出声明，混说能力**未核实**，需在 spike 中实测 | 模型支持 1–8 s 动态注意力窗口的流式 [49]，但官方工具链的流式**只在 vLLM 后端可用**，且「does not support batch inference or returning timestamps」[48] | 官方只给出 GPU 并发吞吐（TTFT 92 ms，并发 128 时 2000×）[49]；Mac 上的速度**未核实** | 有 MLX 移植（mlx-audio [50]；Hugging Face 上有 `mlx-community/Qwen3-ASR-0.6B-8bit`、`-4bit` 等 [81]），需要自行包装成 Swift 或子进程 |
| **SenseVoiceSmall** | 代码 MIT [44]；权重使用 FunASR Model License，要求保留署名和模型名 [45][46] | 已发布的权重支持普通话、粤语、英语、日语、韩语，自动语种识别 [44] | 非自回归批处理模型 [44]，需要 VAD 切段后做伪流式 | 官方称比 Whisper-Small 快 5 倍以上 [44]；FluidAudio 有 CoreML/ANE 版本 [23] | FluidAudio `SenseVoiceManager`（Apache-2.0）[21][23] |
| **Fun-ASR-Nano-2512** | Apache-2.0 [80] | 中文（含 7 种方言）、英语、日语 [80]；中英混说能力**未核实** | 模型卡称支持「low-latency real-time transcription」[80] | Mac 上的速度**未核实** | 未见 Swift、CoreML 或 MLX 移植（**未核实**） |
| **Paraformer-large (zh)** | Apache-2.0 [47] | 普通话 [23][47]；混说能力**未核实** | 批处理 [23] | 未见 Mac 数据 | FluidAudio `ParaformerManager` [23] |
| **Nemotron Streaming Multilingual 0.6B** | OpenMDW-1.1 [43] | en/es/fr/it/pt/de/zh/ja，有 `auto` 模式 [23] | 真流式，0.56–4.48 s 分块 [23] | M5 Pro 上 FLEURS 中文 CER 18.57%，2 s 分块 89× [43] | FluidAudio [23] |
| **Parakeet TDT v3** | CC-BY-4.0 [42] | 25 种欧洲语言，**不含中文** [42] | 批处理或近实时 [23] | — | FluidAudio [21] |
| **Whisper（WhisperKit）** | MIT [39][41] | 99 种以上语言 [50]；CS 表现见 [37][38] | 有流式 [39] | WhisperKit 论文报告 0.46 s 延迟、2.2% WER（英语）[40]；Audicap 实测流式只有 3× 实时、常驻 1.5 GB、5 s 硬切、静音时幻觉 [3] | WhisperKit（MIT）[39] |

### 3.5 转录结论

- 默认引擎用 SpeechTranscriber，zh-CN 与 en-US 双通道，复用 Audicap 的仲裁逻辑，配置 `volatileResults` 和 `audioTimeRange`。是否开 `fastResults`，由 spike 根据延迟和准确率决定。
- 对照组：Qwen3-ASR-0.6B（MLX）和 SenseVoiceSmall（FluidAudio）。如果 SpeechTranscriber 在句内混说样本上的英文术语召回明显落后，就评估把其中一个作为「混说模式」引擎，或者作为 final 之后的二次识别（仍然在本机运行，只处理已经确认片段的音频；音频只在内存中，不落盘）。
- 不建议用 Whisper 做实时主引擎 [3]。

### 3.6 逐字稿数据模型（满足 PRD「有稳定标识、时间范围和音源」）

建议每个已确认片段（Segment）包含以下字段：

```
Segment {
  id: UInt32            // 本会话内单调递增，永不复用，例如 S0001
  source: .system | .mic
  start, end: TimeInterval   // 来自 SpeechTranscriber.Result.range，统一到会话音频时间轴
  locale: String        // 仲裁胜出的通道
  text: String          // final 之后不可变
  confidence: Double    // 各 run 的 ConfidenceAttribute 平均值
}
```

- 只有 `isFinal == true`、并且通过仲裁的结果才生成 Segment。volatile 结果只驱动字幕（PRD 的规定 [1]）。
- 多条 analyzer 必须共用同一条音频时间轴。Audicap 在重启 Recognizer 时会传入 `startOffset`，就是为了避免时间轴错位 [3]。

---

## 4. 端侧摘要

### 4.1 Apple Foundation Models 框架

- **模型版本**（Apple 文档 [56]）：

  | 系统 | 端侧模型 | 上下文 |
  |---|---|---|
  | macOS 26.0–26.3 | AFM 2 Core | 4K |
  | macOS 26.4+ | AFM 2.1 Core | 4K |
  | macOS 27 | AFM 3 Core（3B，「4-8K tokens context」）或 AFM 3 Core Advanced（20B 稀疏，「8K tokens context」） | 见左 |

  M1 及以上的 Mac 运行 Core；M3 及以上的 Mac 在 macOS 27 上运行 Core Advanced [56]。每台设备上只有一个端侧模型，应用不能自己选 [56]。实际可用的上下文以运行时的 `contextSize` 为准 [53][56]。
- **4K 上下文的算法**：4096 个 token 是「instructions, prompts, and outputs」三者之和；对中文、日文、韩文，「a token typically represents one character」[55]。生成的结构（Generable schema）也会被转成 JSON schema，同样占用上下文 [55][60]。
- **中文支持**：Apple Intelligence 支持 Chinese (simplified)／(traditional) 等 16 种语言 [65]。框架会检测输入语言，不支持时抛 `unsupportedLanguageOrLocale` [58]。可以用 `supportsLocale(_:)` 预检 [58]。中英夹杂的输入是否会触发这个错误，**未核实**。
- **地区限制（关键）**：「Apple Intelligence features will not currently work for supported devices purchased in China mainland」；在中国大陆境外购买的设备，如果人在中国大陆且 Apple 账户地区也是中国大陆，同样不可用 [65]。macOS 27 上 Apple Intelligence 默认开启，不能关闭 [56]，但这不改变地区限制。
- **能力边界**：文档把「Summarize」列为适合的任务，同时把逻辑推理和计算列为「may not be suitable」[59]。
- **结构化输出**：`@Generable` 和 `@Guide` 通过「constrained decoding」从结构上保证输出正确 [63][60]；属性「generates … in the order they're declared」[60]。`GenerationGuide.anyOf(_:)`「Enforces that the string be one of the provided values」[61]；`DynamicGenerationSchema` 可以在运行时构造 schema（文档的例子就是限定从当天菜单里选择）[60][61]。
- **延迟手段**：`prewarm(promptPrefix:)` 在至少 1 秒前调用，可以预加载模型并提前处理已知的前缀 [62]。`streamResponse` 可以流式返回部分生成的结构 [51]。每个输入 token 都会增加延迟，输出越长越慢 [64]。一个 session 同一时间只能处理一个请求 [59]。
- **公开的速度数据**：2024 年的报告：iPhone 15 Pro 上首 token 延迟约「0.6 millisecond per prompt token」，生成速度「30 tokens per second」[66]。2025 年的模型通过 KV-cache 共享改善了首 token 延迟 [67]，但没有公布新的数值。**Mac 上的数值未核实**。
- **私有云（PCC）**：从 macOS 27 起有 `PrivateCloudComputeLanguageModel`。它有 32K 上下文、每日配额、需要申请托管 entitlement，并且不能离线使用 [57]。对本产品来说，它属于「把文本发出本机」，应当套用 PRD 中云端选项的规则：默认关闭，明确告知 [1]。

### 4.2 三分钟窗口的 token 预算（推算）

| 项目 | 估算 | 依据 |
|---|---|---|
| 三分钟中文转录 | 约 600–900 字，约 600–900 token | 语速按每秒 3–5 字估算（**未核实**）；中文 1 字约 1 token [55] |
| 片段编号和时间前缀 | 30–60 段，每段约 6–8 token，合计约 200–500 | 自行设计的 `[S0123 02:41]` 格式 |
| instructions、Generable schema 和 `anyOf` 的 ID 列表 | 约 400–700 | schema 计入上下文 [55]；ID 列表随片段数增长 |
| 输出（2–4 条要点 × 约 40 字，加上类型和引用） | 约 200–350 | PRD 默认 2–4 条 [1] |
| **合计** | **约 1.4K–2.5K** | 低于 4096 [54] |

结论：首版的「最近三分钟」放得进 AFM Core 的 4K 上下文。「从上次查看到现在」可能超过 4K，需要按文档建议分块摘要后再合并 [55]，或者在 macOS 27 的 8K 模型上运行。

### 4.3 延迟估算（推算，必须实测）

- **AFM**：按 2024 年 iPhone 数据 [66] 推算，2K 输入约 1.2 s，300 token 输出约 10 s，合计会超过 10 s 目标。Mac 芯片通常比 A17 Pro 更快（**未核实**）。要点：控制输出长度（文档建议明确限定条数和句数 [59]）、开启流式（第一条要点先显示），并在面板打开时预热 [62]。
- **MLX 备选**（Qwen3 系列，Apache-2.0 [71][72]）：
  - Apple 在 M5 上测了 4096-token prompt：Qwen3-1.7B bf16 占内存 4.40 GB，Qwen3-8B 4bit 占 5.61 GB，Qwen3-14B 4bit 首 token 延迟低于 10 s；M5 的首 token 延迟比 M4 快 3.5–4 倍，生成速度快 19–27% [69]。
  - llama.cpp 的 Apple Silicon 基准（LLaMA 7B Q4_0）[70]：

    | 芯片 | prompt 处理（t/s） | 生成（t/s） |
    |---|---|---|
    | M1（8 核 GPU） | 117 | 14 |
    | M4（10 核） | 221 | 24 |
    | M4 Pro（20 核） | 440 | 51 |
    | M5（10 核） | 723 | 32 |

  - 按参数量把 7B 线性折算到 4B（推算）：M1 上处理 2K 输入约 10 s，生成 300 token 约 12 s，**达不到目标**；M4 约 5 s + 7 s，勉强；M4 Pro 和 M5 约 3 s + 4–5 s，**可以达标**。
  - Qwen3-4B-Instruct-2507 只有非思考模式，原生上下文 262,144 [72]，适合做摘要；Swift 侧可以用 mlx-swift-lm（MIT）[73]。2026-02 发布的 Qwen3.5 系列有 0.8B、2B、4B、9B 等尺寸（Apache-2.0，原生视觉语言多模态）[82]，可以作为同尺寸的对照组一起测；它的中文摘要质量和速度**未核实**。
  - 4bit 的 4B 模型内存约 3 GB（推算：依据 [69] 中 8B 4bit 占 5.61 GB 按比例折算）。8 GB 内存的 Mac 同时开会议软件时有压力，**未核实**。

### 4.4 引用约束的摘要设计

1. **冻结范围**：按下快捷键时记下 `[firstSegmentID, lastSegmentID]`。之后到达的新片段不进入本次输入（PRD 要求 [1]）。
2. **输入格式**：每个片段一行：`[S0123 02:41 对方] 文本`。片段 ID 用短字符串，节省 token。
3. **输出结构**（`DynamicGenerationSchema`，在运行时生成）：

   ```
   CatchUp {
     points: [Point]  (maximumCount 4)
   }
   Point {
     evidence: [String]  每个元素 anyOf(本窗口的片段 ID)，count 1...3   // 先生成证据，再生成文字
     kind: anyOf("讨论","决定","行动")
     text: String       // 一句话
     owner: String?     // 只在证据里明确出现时填写
     due: String?
   }
   ```

   因为属性按声明顺序生成 [60]，把 `evidence` 放在前面，可以引导模型先选原话再概括。这是一种设计假设，效果要在 spike 中对比验证。
4. **程序校验**（不通过的那条就不展示，并保留原文入口，与 PRD 一致 [1]）：
   - ID 属于冻结范围：由 `anyOf` 在结构上保证 [61]，再做一次断言。
   - 数字、日期、人名和 `owner`：必须能在引用片段的原文里找到字面匹配（允许全半角和大小写归一化）。否则删除该字段；如果字段是主要内容，就删除整条要点。这针对 PRD「不得编造人名、负责人或日期」[1]。
   - `kind == 决定 / 行动`：引用片段里必须含有决定类或承诺类的线索（例如「定了」「就这么办」「we'll」「agreed」「I'll take」）。否则降级为「讨论」。这是启发式规则，词表要在 spike 中根据标注集调整。它针对 PRD「不得把提议写成决定」[1]。
   - 可选的二次核验：用一个新 session，逐条询问「片段是否支持这句话（是/否）」，输出 `Bool`。这会增加延迟，只在时间预算有余量时启用。
5. **评测**：参考 ALCE 的引用质量指标（citation recall／precision）[74]、LongCite 的句级引用 [75]，以及 FActScore 的原子事实拆分 [76]。在 PRD 要求的人工标注样本 [1] 上统计：可用引用率、提议误判为决定的次数、编造字段的次数。ALCE 报告称，即使最强的模型在 ELI5 上也有 50% 的情况「lack complete citation support」[74]，所以不能假设模型的引用天然可靠，校验步骤必须保留。

### 4.5 摘要结论

- 首选 AFM（`SystemLanguageModel.default`），配合 `DynamicGenerationSchema`、`anyOf` 和 `streamResponse`，在面板打开时预热。
- 必须有备选：在 Apple Intelligence 不可用时（中国大陆地区、设备不符合条件、模型未就绪 [52][65]），用 MLX 运行 Qwen3-4B-Instruct-2507（4bit），或者显式提示「摘要不可用」并保留字幕和原话入口（PRD 用户故事 14 [1]）。
- PCC 和第三方云服务一律视为云端选项，默认关闭。

---

## 5. 推荐方案

| 层 | 首版推荐 | 备选或对照 | 关键依据 | 需要 spike 回答的问题 |
|---|---|---|---|---|
| 系统音频 | SCK（`capturesAudio`、16 kHz 单声道、排除自身），复用 Audicap `SCKCapture` | Core Audio process tap | 有明确的拒绝错误，输出设备无关，已在 Audicap 中验证 [4] | 26.x 和 27 上的长时稳定性；tap 是否爆音 [2] |
| 权限 UX | 状态机：未请求 → 等待授权 → 已授权待重启 → 运行中 → 被拒或出错 | — | 授权后需重启 [4]；Sequoia 起有周期性复核 [12] | 复核弹框的实际频率 |
| 麦克风 | 默认关闭；开启时绑定内置麦克风 | SCK `captureMicrophone` [9] | 避免蓝牙耳机切换到 HFP [4] | 与 SCK 内置麦克风相比的时钟对齐 |
| 回声与重复 | voice processing 加文本去重 | LocalVQE [22] | [18][20][22] | 重复率；会议声音是否被压低 [20] |
| ASR | SpeechTranscriber，zh-CN 与 en-US 双通道仲裁 | Qwen3-ASR-0.6B（MLX）、SenseVoiceSmall（FluidAudio） | [3][25][33][49][44] | 句内混说的 MER 和英文术语召回；final 延迟 |
| 片段模型 | 不可变的 Segment（ID、来源、区间、locale、置信度） | — | `volatileRange` 语义 [29]，`Result.range` [28] | — |
| 摘要 | AFM，配合 Dynamic schema、`anyOf` 和流式输出 | MLX Qwen3-4B-Instruct-2507 4bit | [56][60][61][69][72] | M1 或 8 GB 机型上的 P90 延迟；中文摘要质量 |
| 引用校验 | ID 断言、字段字面匹配、决定类线索降级 | 二次核验 | [61][74][76] | 误删率与漏检率 |
| 云端 | 首版不做 | PCC（macOS 27）或第三方，仅发送文本 | [57] | — |

## 6. 主要风险

| # | 风险 | 影响 | 可能性 | 缓解 |
|---|---|---|---|---|
| R1 | Apple Intelligence 在中国大陆不可用 [65]，而首要用户使用中文 [1] | 端侧摘要整体失效 | 高（对大陆用户） | MLX 备选；首版就设计「摘要不可用」状态；在 PRD 中写明 |
| R2 | 句内中英混说识别差 [35][37]；SpeechTranscriber 不能指定混合 locale [25] | 用户故事 11 无法兑现；摘要基于错误的转录 | 中到高 | spike 量化；对照 Qwen3-ASR 和 SenseVoice；PRD 区分句间与句内的承诺 |
| R3 | 外放时麦克风重复收录 | 「我」被误标，摘要内容重复 | 高（开麦且外放时） | 默认不开麦；voice processing；文本去重；提示戴耳机 |
| R4 | 屏幕录制权限：需重启生效、周期性复核、紫色指示器 [2][4][12] | 首次使用时流失，用户误以为在偷录屏幕 | 中 | 引导文案；后续评估 process tap |
| R5 | AFM 输出慢（输出 token 是延迟的主项）[64][66] | 补进度超过 10 s | 中 | 流式显示首条、限制条数、预热；把 PRD 的 10 s 拆成「首条」和「全部」两个指标 |
| R6 | 系统模型随 OS 更新而变化（26.0 → 26.4 → 27）[56] | 提示词效果漂移 | 中 | 按 OS 版本管理提示词 [56]；回归样本集 |
| R7 | Audicap 只有单一维护者，单机测试 [2][5] | 复用代码可能有隐藏缺陷 | 中 | 只拆件复用，自建测试；不跟踪上游 |
| R8 | 并行 analyzer 的资源上限（`insufficientResources`）[24] | 系统和麦克风各两条通道时启动失败 | 低到中 | 实测 4 路；必要时麦克风只跑单通道 |
| R9 | 语言资产未安装时无法离线 [30]；名额上限为 5 且跨次运行保留 [3] | 首次断网时无法转录 | 低 | 首次运行引导下载并显示进度；只占用 zh-CN 和 en-US 两个名额 |
| R10 | SpeechTranscriber 缺少自定义词汇 [33] | 人名、产品名错误，进而影响摘要可信度 | 中 | 评估 `DictationTranscriber` 的 `contextualStrings` [31]，或交给摘要层的字面校验 |

## 7. Spike 计划（10 个工作日）

前提：准备两台目标 Mac，一台 M1 8 GB（下限），一台 M3 或 M4（主力）；macOS 26.x 和 27 各一个环境。

**测试集**（第 1 天准备，后续所有环节共用）：

- A：真实或录制的中文会议 3 段，每段 10 分钟，其中至少 30% 的句子是**句间**中英切换。
- B：同样规模，包含至少 50 处**句内**混说（术语、缩写、人名）。
- C：英语会议 1 段，10 分钟。
- 人工逐字参考稿，标注每处混说的位置。另外标出 20 个三分钟窗口，每个窗口标注「讨论 / 提议 / 否决 / 决定 / 行动 / 负责人 / 日期」。

| 天 | 任务 | 产出 | 退出标准（可量化） |
|---|---|---|---|
| D1 | 用 Audicap 代码搭一个 CLI 或最小应用；`speechprobe locales` 导出 locale 列表；准备测试集 | locale 列表、测试集 | 确认 zh-CN 和 en-US 都在 `supportedLocales` 中，并且能下载安装 |
| D2 | 采集：SCK 对比 process tap，在 26.x 和 27 上各连续播放 30 分钟 | 掉帧和爆音记录、权限流程录屏 | SCK 30 分钟 0 次中断；拒绝授权后 2 s 内界面给出明确状态；tap 是否爆音给出是或否的结论 |
| D3 | 双路采集和回声：扬声器对比耳机 × voice processing 开关 × 文本去重 | 重复率表 | 有缓解时，外放场景下系统语音被误收为「我」的句子不超过 5%；会议音频不被明显压低（RMS 下降不超过 3 dB） |
| D4–D5 | ASR 基准：SpeechTranscriber 单 zh-CN、zh-CN+en-US 仲裁、开关 `fastResults`；Qwen3-ASR-0.6B（MLX）；SenseVoiceSmall（FluidAudio） | 每个引擎的 MER（中文 CER 加英文 WER 的混合错误率）、句内英文术语召回、final 延迟 P50/P90、RSS、CPU | 选中的引擎：A 集 MER ≤ 12%，B 集英文术语召回 ≥ 80%（阈值第一天依据基线再校准一次），final 延迟 P90 ≤ 2.5 s，断网时可以转录 |
| D6 | 片段模型和冻结范围；字幕 volatile 与 final 的展示 | 小样 | 确认后的字幕 0 次改写；回看时不被新字幕打断 |
| D7–D8 | 摘要：AFM（26.x 与 27）对比 MLX Qwen3-4B-2507 4bit 和 Qwen3-1.7B；使用 Dynamic schema 和 `anyOf` | 20 个窗口的输出、token 计数、延迟 | AFM 在 M1 上：首条要点 P90 ≤ 3 s，全部完成 P90 ≤ 10 s；引用 ID 100% 在范围内；人工判断「引用支持要点」≥ 90%；提议误判为决定 0 次；编造人名或日期 0 次 |
| D9 | 校验规则和降级：字面匹配、决定类线索、超时与失败路径 | 规则表和误删率 | 校验误删正确要点 ≤ 10%；摘要失败或超时时字幕不中断 |
| D10 | 端到端演示：音频 → 字幕 → 回看摘要 → 定位原话；写决策备忘 | 演示录像、决策备忘 | 按 PRD 的「补进度」验收项走通一次 [1]，分别记录摘要生成耗时和阅读耗时 |

**止损线**：

- 如果 D4–D5 中所有端侧 ASR 在 B 集上的英文术语召回都低于 60%，PRD 就改为只承诺句间切换。
- 如果 D7–D8 中 AFM 在 M1 上全部完成的 P90 超过 15 s，就把首版的目标硬件提高到 M3 及以上，或者只承诺首条要点的延迟。

## 8. 对 PRD 的修改建议（本 PR 不修改 PRD.md）

1. **实现决策 / Audicap**：把「以 Audicap 为候选底座」改为「拆件复用 Audicap 的采集（SCK）、麦克风、多语种识别仲裁和语音探针；不 fork 整个应用」。并注明它是单人维护、单机测试 [2][5]。
2. **平台与地区**：在「端侧摘要」中注明，Apple Intelligence 需要符合条件的设备和地区，**中国大陆当前不可用** [65]。首版要么提供 MLX 备选，要么明确显示「摘要不可用（原因）」，并在验收中加入这个状态。
3. **中英切换（用户故事 11、后续决策 2）**：把承诺拆成「句间切换（首版承诺）」和「句内混说（尽力而为，以 spike 结果为准）」。验收样本也分别统计这两类。
4. **麦克风（用户故事 12）**：加入回声和重复的处理要求，以及在外放场景下的提示。验收增加「外放时，系统语音被误标为『我』的比例」。
5. **权限（用户故事 2）**：写明系统音频走「屏幕与系统录音」权限，授权后需要重启应用，系统会周期性复核，菜单栏会显示紫色指示器 [2][4][12]。验收增加「授权后重启」和「被拒」两个状态。
6. **10 秒目标**：拆成「首条要点出现」和「全部要点完成」两个指标，并写明基线机型（建议 M1 8 GB 为下限）。
7. **摘要结构**：在「摘要内容」中写明输出结构（类型为讨论、决定或行动；证据是片段 ID 列表，只能取自冻结范围），以及校验失败时的行为（删除字段或整条，或降级为讨论）。
8. **云端选项**：注明 Apple PCC（macOS 27 的 `PrivateCloudComputeLanguageModel`）也属于「文本离开本机」，适用同一套默认关闭和告知规则 [57]。
9. **离线**：在「数据处理」验收前加一个首次运行步骤：引导下载 zh-CN 和 en-US 语音资产并显示进度。注明每个应用的 locale 名额上限，Audicap 实测为 5 [2][30]。
10. **后续「从上次查看到现在」**：注明窗口可能超过 4K 上下文，需要分块摘要或依赖 macOS 27 的 8K 模型 [55][56]。

---

## 参考来源（访问日期均为 2026-11-12）

1. 本仓库 PRD — https://github.com/zerone0x/mac-live-captions/blob/main/PRD.md
2. Audicap README（含 LICENSE） — https://github.com/ShinoKana/audicap
3. Audicap `Recognizer.swift` — https://github.com/ShinoKana/audicap/blob/main/Recognizer.swift
4. Audicap `AudicapApp.swift` — https://github.com/ShinoKana/audicap/blob/main/AudicapApp.swift
5. Audicap 仓库文件与元数据（`speechprobe.swift`、`CloudCorrect.swift`、`Refine.swift`、`deploy.sh`、`tests/`） — https://github.com/ShinoKana/audicap/tree/main ，https://api.github.com/repos/ShinoKana/audicap
6. SCStreamConfiguration — https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration
7. capturesAudio — https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/capturesaudio
8. excludesCurrentProcessAudio — https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/excludescurrentprocessaudio
9. captureMicrophone / microphoneCaptureDeviceID — https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/capturemicrophone
10. WWDC22「Meet ScreenCaptureKit」 — https://developer.apple.com/videos/play/wwdc2022/10156/
11. WWDC24「Capture HDR content with ScreenCaptureKit」 — https://developer.apple.com/videos/play/wwdc2024/10088/
12. 9to5Mac：macOS Sequoia 屏幕录制权限周期性提示 — https://9to5mac.com/2024/08/06/macos-sequoia-screen-recording-privacy-prompt/
13. AudioHardwareCreateProcessTap — https://developer.apple.com/documentation/coreaudio/audiohardwarecreateprocesstap(_:_:)
14. CATapDescription — https://developer.apple.com/documentation/coreaudio/catapdescription
15. Capturing system audio with Core Audio taps — https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps
16. NSAudioCaptureUsageDescription — https://developer.apple.com/documentation/bundleresources/information-property-list/nsaudiocaptureusagedescription
17. insidegui/AudioCap — https://github.com/insidegui/AudioCap
18. daformat/subtitles README — https://github.com/daformat/subtitles
19. ultima6-tw/livesub-macos README — https://github.com/ultima6-tw/livesub-macos
20. setVoiceProcessingEnabled(_:) 与 voiceProcessingOtherAudioDuckingConfiguration — https://developer.apple.com/documentation/avfaudio/avaudioionode/setvoiceprocessingenabled(_:) ，https://developer.apple.com/documentation/avfaudio/avaudioinputnode/voiceprocessingotheraudioduckingconfiguration
21. FluidAudio README — https://github.com/FluidInference/FluidAudio
22. FluidAudio LocalVQE 文档 — https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Enhancement/LocalVQE.md
23. FluidAudio 模型目录 — https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Models.md
24. SpeechAnalyzer — https://developer.apple.com/documentation/speech/speechanalyzer
25. SpeechTranscriber — https://developer.apple.com/documentation/speech/speechtranscriber
26. SpeechTranscriber.ReportingOption（volatileResults / fastResults） — https://developer.apple.com/documentation/speech/speechtranscriber/reportingoption
27. SpeechTranscriber.Preset — https://developer.apple.com/documentation/speech/speechtranscriber/preset
28. SpeechTranscriber.Result 与 audioTimeRange — https://developer.apple.com/documentation/speech/speechtranscriber/result ，https://developer.apple.com/documentation/speech/speechtranscriber/resultattributeoption/audiotimerange
29. SpeechAnalyzer.volatileRange — https://developer.apple.com/documentation/speech/speechanalyzer/volatilerange
30. AssetInventory 与 maximumReservedLocales — https://developer.apple.com/documentation/speech/assetinventory ，https://developer.apple.com/documentation/speech/assetinventory/maximumreservedlocales
31. DictationTranscriber — https://developer.apple.com/documentation/speech/dictationtranscriber
32. WWDC25「Bring advanced speech-to-text to your app with SpeechAnalyzer」 — https://developer.apple.com/videos/play/wwdc2025/277/
33. Argmax：Apple SpeechAnalyzer and Argmax WhisperKit — https://www.argmaxinc.com/blog/apple-and-argmax
34. MacStories：Apple 新语音 API 对比 Whisper — https://www.macstories.net/stories/hands-on-how-apples-new-speech-apis-outpace-whisper-for-lightning-fast-transcription/
35. ivan-magda/swift-speech-lanes — https://github.com/ivan-magda/swift-speech-lanes
36. Apple ML Research：Retraining-free Speech Recognition for Intra-sentential Code-switching — https://machinelearning.apple.com/research/exploring-retraining-free-speech-recognition-for-intra-sentential-code-switching
37. Investigating Zero-Shot Generalizability on Mandarin-English Code-Switched ASR (arXiv 2401.00273) — https://arxiv.org/abs/2401.00273
38. CS-Dialogue (arXiv 2502.18913) — https://arxiv.org/abs/2502.18913
39. argmaxinc/WhisperKit（现为 argmax-oss-swift，MIT） — https://github.com/argmaxinc/WhisperKit
40. WhisperKit: On-device Real-time ASR with Billion-Scale Transformers (arXiv 2507.10860) — https://arxiv.org/abs/2507.10860
41. openai/whisper-large-v3-turbo 模型卡 — https://huggingface.co/openai/whisper-large-v3-turbo
42. nvidia/parakeet-tdt-0.6b-v3 模型卡 — https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3
43. FluidInference Nemotron-3.5 ASR Streaming Multilingual CoreML 模型卡 — https://huggingface.co/FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML
44. SenseVoice README（仓库现位于 QwenAudio/SenseVoice） — https://github.com/FunAudioLLM/SenseVoice
45. FunAudioLLM/SenseVoiceSmall 模型卡 — https://huggingface.co/FunAudioLLM/SenseVoiceSmall
46. FunASR Model License — https://github.com/modelscope/FunASR/blob/main/MODEL_LICENSE
47. funasr/paraformer-zh 模型卡 — https://huggingface.co/funasr/paraformer-zh
48. QwenLM/Qwen3-ASR README — https://github.com/QwenLM/Qwen3-ASR
49. Qwen3-ASR Technical Report (arXiv 2601.21337) — https://arxiv.org/abs/2601.21337
50. mlx-audio README — https://github.com/Blaizzy/mlx-audio
51. Foundation Models 框架总览 — https://developer.apple.com/documentation/foundationmodels
52. SystemLanguageModel — https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel
53. SystemLanguageModel.contextSize — https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/contextsize
54. GenerationError.exceededContextWindowSize — https://developer.apple.com/documentation/foundationmodels/languagemodelsession/generationerror/exceededcontextwindowsize(_:)
55. Managing the context window — https://developer.apple.com/documentation/foundationmodels/managing-the-context-window
56. Detecting available Apple Foundation Models — https://developer.apple.com/documentation/foundationmodels/detecting-available-apple-foundation-models
57. Adding server-side intelligence with Private Cloud Compute — https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute
58. Supporting languages and locales with Foundation Models — https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models
59. Generating content and performing tasks with Foundation Models — https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models
60. Generating Swift data structures with guided generation（含 DynamicGenerationSchema） — https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation
61. GenerationGuide.anyOf(_:) 与 DynamicGenerationSchema — https://developer.apple.com/documentation/foundationmodels/generationguide/anyof(_:) ，https://developer.apple.com/documentation/foundationmodels/dynamicgenerationschema
62. LanguageModelSession.prewarm(promptPrefix:) — https://developer.apple.com/documentation/foundationmodels/languagemodelsession/prewarm(promptprefix:)
63. WWDC25「Meet the Foundation Models framework」 — https://developer.apple.com/videos/play/wwdc2025/286/
64. WWDC25「Deep dive into the Foundation Models framework」 — https://developer.apple.com/videos/play/wwdc2025/301/
65. Apple 支持：How to get Apple Intelligence（语言、地区、中国大陆说明） — https://support.apple.com/en-us/121115
66. Introducing Apple's On-Device and Server Foundation Models (2024) — https://machinelearning.apple.com/research/introducing-apple-foundation-models
67. Updates to Apple's On-Device and Server Foundation Language Models (2025)；技术报告 arXiv 2507.13575 — https://machinelearning.apple.com/research/apple-foundation-models-2025-updates ，https://arxiv.org/abs/2507.13575
68. Introducing the third generation of Apple Foundation Models — https://machinelearning.apple.com/research/introducing-third-generation-of-apple-foundation-models
69. Exploring LLMs with MLX and the Neural Accelerators in the M5 GPU — https://machinelearning.apple.com/research/exploring-llms-mlx-m5
70. llama.cpp：Performance of llama.cpp on Apple Silicon M-series — https://github.com/ggml-org/llama.cpp/discussions/4167
71. Qwen3 发布博客（各尺寸、上下文、Apache-2.0） — https://qwenlm.github.io/blog/qwen3/
72. Qwen/Qwen3-4B-Instruct-2507 模型卡 — https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507
73. ml-explore/mlx-lm 与 mlx-swift-lm — https://github.com/ml-explore/mlx-lm ，https://github.com/ml-explore/mlx-swift-lm
74. ALCE: Enabling LLMs to Generate Text with Citations (arXiv 2305.14627) — https://arxiv.org/abs/2305.14627
75. LongCite (arXiv 2409.02897) — https://arxiv.org/abs/2409.02897
76. FActScore (arXiv 2305.14251) — https://arxiv.org/abs/2305.14251
77. thxjune/MeetingMind README — https://github.com/thxjune/MeetingMind
78. Qwen/Qwen3-ASR-0.6B 模型卡 — https://huggingface.co/Qwen/Qwen3-ASR-0.6B
79. finnvoor/yap（MacStories 测试所用的 SpeechTranscriber CLI） — https://github.com/finnvoor/yap
80. FunAudioLLM/Fun-ASR-Nano-2512 模型卡 — https://huggingface.co/FunAudioLLM/Fun-ASR-Nano-2512
81. Hugging Face 模型检索「Qwen3-ASR mlx」（mlx-community/Qwen3-ASR-0.6B-8bit 等） — https://huggingface.co/api/models?search=Qwen3-ASR%20mlx
82. Qwen/Qwen3.5-4B 模型卡 — https://huggingface.co/Qwen/Qwen3.5-4B
