# 🎵 DouyinVoice (抖音语音提取与管理助手)

![Platform](https://img.shields.io/badge/Platform-iOS-lightgrey.svg)
![Jailbreak](https://img.shields.io/badge/Jailbreak-Required-red.svg)
![Language](https://img.shields.io/badge/Language-Objective--C-blue.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)

**DouyinVoice** 是一款专为 iOS 端抖音打造的极客级越狱插件。它不仅能让你在评论区发送自定义的高清语音包，还内置了强大的“图文/视频智能音轨提取”引擎与全功能的本地文件管理及分享系统。

---

## ✨ 核心特性

### 🎙️ 评论区语音替换 (核心玩法)
- **优雅集成**：在抖音评论区输入框右侧无缝嵌入现代感十足的系统级音符 `🎵` 图标，点击即可呼出语音包面板。
- **全局呼出**：支持通过“摇一摇”设备在任何界面快速唤出管理面板。
- **一键替换**：选择本地语音包装填后，在评论区按住“录音”并松手，自动将你的录音狸猫换太子，替换为选中的高清音频发送。

### ⚡️ 智能无损提取引擎
- **图文/视频智能分流**：彻底解决抖音底层数据结构的痛点。智能识别当前是“视频流”还是“图文流”，精准抓取隐藏的 MP3 背景音乐或 MP4 视频原声，完美规避“音视频分离”导致的提取失败。
- **可视化进度追踪**：告别“假死”盲等。引入全局暗黑悬浮 HUD，实时展示**流媒体下载进度**与 **AVFoundation 核心转码进度**。
- **自动转码与裁剪**：无论抓取到何种音频格式，底层自动将其标准化转码为抖音兼容的 `.m4a` 格式。若音频超过 29 秒上限，自动执行无损裁剪。

### 📂 现代化的文件管理调度系统
- **高颜值 UI**：采用 iOS 现代化的半屏面板 (PageSheet) 与系统原生图标 (SF Symbols)。
- **新建文件夹**：支持在插件内直接创建文件夹，对语音包进行沉浸式分类（如：搞笑、怼人、音乐等）。
- **全能左滑菜单**：
  - 🗑️ **删除**：安全移除文件。
  - 📤 **导出与分享**：一键调用系统原生的 `UIActivityViewController`，将提取的高清音频直接发送给微信好友、隔空投送 (AirDrop) 给 Mac、或保存到“文件”App 及剪映等外部应用。
  - 📂 **智能移动**：支持将文件移动至指定文件夹，内置防冲突机制（自动重命名为 `文件名_1.m4a` 避免覆盖）。
  - ✏️ **重命名**：快捷修改文件名。
- **智能排序**：文件列表按**修改时间降序**排列，最新提取或导入的声音永远在最顺手的位置。

---

## 🛠️ 编译与安装

本项目使用 [Theos](https://github.com/theos/theos) 框架进行开发。

1. 克隆项目到本地：
   ```bash
   git clone [https://github.com/ac54u/douyinvoice.git](https://github.com/ac54u/douyinvoice.git)
   cd douyinvoice
