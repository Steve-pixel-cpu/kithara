# Kithara 图标资产

App 定名 **Kithara**（κιθάρα）：阿波罗的基萨拉琴，「guitar」的希腊词源祖先。
神话渊源：音乐之神阿波罗的专属音乐会弦乐器。

## 设计语言

- **构图**：几何化 kithara 轮廓——弧形双臂 + 横杆（圆头端点暗喻弦栓）+ 六根竖弦 + 圆角音箱条
- **六弦**：对应 EADGBE，五灰一绿；居中绿弦 = 「已调准」，与 app 内调准反馈（`|cents| < 5` 变绿）同色闭环
- **品牌绿**：`#47E6A2 → #2BC489` 渐变（暗色底） / `#1FB377 → #148F5C`（浅色底）；状态色 `#34D399`（发光层）
- **暗色主题**：径向深板岩底 `#1C2130 → #10131B`，呼应 app 深色 UI
- **浅色变体**：「大理石」暖白底 `#F4F1E8 → #E7E2D4`（希腊大理石意象）

## 文件结构

```
design/icon/
├── master/                    ← SVG 源文件（唯一编辑入口）
│   ├── icon-dark.svg          完整图标（含背景），iOS/通用导出源
│   ├── icon-light.svg         浅色「大理石」变体
│   ├── icon-foreground.svg    Android 自适应前景层（透明底，安全区内 66%）
│   └── export-template.svg    带注释母版：改色/改坐标先改这里，再镜像到上面三个
├── exports/
│   ├── icon_1024.png                商店通用 1024×1024（= dark 母版渲染）
│   ├── icon_1024_dark.png           暗色主题 1024
│   ├── icon_1024_light.png          浅色变体 1024
│   ├── android/
│   │   ├── foreground_1024.png      自适应前景（发布资源由 resize 流程生成）
│   │   ├── foreground_432.png       mipmap 缩放参考
│   │   └── foreground_324.png       mipmap 缩放参考
│   ├── ios/AppIcon.appiconset/
│   │   └── Icon-App-1024x1024@3x.png  Xcode 单尺寸目录唯一必需文件
│   └── favicon/favicon_64.png       Web favicon 参考
└── README.md
```

## 各端接入要点

- **iOS**: Xcode 14+ 单尺寸 `1024×1024`（`Icon-App-1024x1024@3x.png`），运行时系统自动缩放。
  勿预圆角——系统加圆角与暗色模式处理。
- **Android**: 自适应图标两层：
  - 前景层 = `icon-foreground.svg` 渲染（内容控制在中心 66% 安全区内，已遵守）
  - 背景层 = 纯色 `#FFFFFF`（launch_background 联动）
- **Web/favicon**: `favicon_64.png`，或直接内联 SVG。

## 修改流程

1. 改 `master/export-template.svg`（带坐标/颜色注释）
2. 镜像同步 `icon-dark.svg` / `icon-light.svg` / `icon-foreground.svg`
3. 用 Chrome headless 重渲染 exports（见下）

## 渲染命令（Chrome headless 光栅化）

```bash
CHROME="/c/Program Files/Google/Chrome/Application/chrome.exe"
shot() { "$CHROME" --headless --disable-gpu --no-sandbox --hide-scrollbars \
  --user-data-dir="$TMP/chrome-headless-icon" \
  --window-size=1024,1024 --screenshot="$2" "file:///$1"; }
```

⚠️ 并发多实例共享 profile 会静默失败——必须串行 + 独立 `--user-data-dir`。
