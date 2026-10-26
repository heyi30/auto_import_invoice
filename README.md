# reimburse-bot

飞书「费用报销」表单自动填报脚本（Windows + UI Automation）。

读入费用报销单的 42 条明细，逐条填写内容、日期（今天）、金额，搜索并上传对应发票 PDF，然后点击「添加明细」。

## 依赖

- Windows 10/11
- PowerShell 5.1
- 飞书桌面客户端（表单需提前打开）

无需安装任何第三方 Python 包；发票转图片用的是 MiKTeX 的 `pdftoppm`，仅开发期使用。

## 使用

1. 把发票 PDF 放进 `C:\Users\<你>\Downloads\10月发票`（或改脚本里的 `$invoiceDir`）。
2. 编辑 `data.json`，每条为 `{name, amount, file}`。
3. 打开飞书费用报销表单，确保末尾有一张空白明细卡片。
4. 运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\fill_reimbursement.ps1 -Start 0
```

参数：

- `-Start` 从第几条开始（0 起）
- `-Count` 本次填几条
- `-NoAdd` 最后不追加新明细
- `-SkipUpload` 只填字段不传发票

## 辅助脚本

- `repair_upload.ps1`：按金额定位明细卡片，重新上传发票。`-Amount 295.00 -File "58转24降压模块9.24_295.pdf"`
- `audit.ps1`：导出每张卡片的金额与发票文件名，用于核对。

## 实现要点

- 控件定位用 Windows UI Automation。先找到「添加明细」按钮，再沿 `ControlViewWalker` 上溯到飞书窗口，所有查找限定在该窗口内。全桌面扫描每次约 2 秒，限定后约 0.3 秒。
- 日期弹窗的「今天」不在飞书窗口子树里，必须从桌面根节点查找。
- 内容输入框是 contenteditable，占位符「请输入」在填写后消失，按「内容」标签的固定偏移点击。
- 上传流程：点「上传文件」→ 在原生打开对话框的搜索框输入文件名 → `SelectionItemPattern` 选中结果 → 点「打开(O)」→ 用卡片里出现同名文件 chip 验证。
- 添加明细优先用 `InvokePattern`：鼠标点击在这个按钮上不可靠，按钮也可能在窗口可视区域下方。

## 已知坑

- 「打开」未生效时不要双击结果行。若对话框已经关闭，双击会落在飞书「上传文件」上，弹出新的文件对话框。
- 残留对话框会阻塞后续点击，每张卡片开始前先关闭残留对话框。
- 卡片内容被覆盖时发票 chip 可能丢失，用 `audit.ps1` 核对。
- 脚本默认填「最后一张卡片」，续跑前要保证末尾有空白卡片。

## 免责声明

仅供个人报销流程自动化使用。运行时会接管鼠标键盘，请勿在运行期间操作电脑。
