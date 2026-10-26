# reimburse_bot

自动填报飞书「费用报销」表单的脚本。

## 文件

- `data.json`：42 条报销项 `{name, amount, file}`，顺序与 9 月费用报销单一致。
- `fill_reimbursement.ps1`：主脚本。逐条填内容、日期（今天）、金额、搜索并上传发票，然后点「添加明细」。
  - 参数：`-Start <从0开始的索引>`、`-Count <条数>`、`-NoAdd`（最后不添加新明细）、`-SkipUpload`。
- `repair_upload.ps1`：按金额定位已有明细卡片，重新上传发票。用于补漏。
- `audit.ps1`：导出每张卡片的金额和发票文件名到 `%TEMP%\invoice_work\audit.txt`。

## 运行方式

```
powershell -NoProfile -ExecutionPolicy Bypass -File .\fill_reimbursement.ps1 -Start 0
```

运行前保持飞书费用报销表单打开，不要操作鼠标键盘。

## 实现要点

- 控件定位用 Windows UI Automation：先找到「添加明细」按钮，再沿 ControlViewWalker 上溯到飞书窗口，所有查找限定在该窗口内（全桌面扫描每次 2 秒，限定后约 0.3 秒）。
- 日期弹窗的「今天」不在飞书窗口子树里，必须从桌面根节点查找。
- 内容输入框是 contenteditable，占位符「请输入」在填写后消失，所以按「内容」标签的固定偏移点击。
- 上传：点「上传文件」→ 在原生打开对话框的搜索框输入文件名 → SelectionItemPattern 选中结果 → 点「打开(O)」→ 用卡片里出现同名文件 chip 验证。
- 添加明细优先用 InvokePattern；鼠标点在这个按钮上不可靠，且按钮可能在窗口可视区域下方。
- 脚本假定末尾有一张空白卡片。续跑前若没有空白卡片，先 InvokePattern 添加一张。

## 已知坑

- 不要在「打开」未生效时双击结果行：对话框若已关闭，双击会落在飞书「上传文件」上，弹出新的文件对话框。
- 残留对话框会阻塞后续点击，脚本每张卡片开始时会先关闭残留对话框。
- 卡片内容被覆盖时发票 chip 可能丢失（角码曾因此缺失），用 `audit.ps1` 核对。
