# 我的珠科 · 鸿蒙版 1.0.9

> 基于上游 [hainuolangbuen-netizen/MyZCST-For-HarmonyOS](https://github.com/hainuolangbuen-netizen/MyZCST-For-HarmonyOS)
> 的二次开发版本，API 26 / HarmonyOS 26。

## 下载

- HAP：`MyZCST-1.0.9-unsigned.hap`（GitHub Release 附件）
- 版本：`1.0.9` / `versionCode 1000009`
- SHA-256：`16E1E250CC6778243B9CF7ECBD6F41231DD0C8DC03A7690C9B81141F0B122070`

HAP 未签名，安装前请在 DevEco Studio 的 **Signing Configs** 勾选
`Automatically generate signature`，重新 Build 后再 `hdc install -r`。

## 本次改动

### 桌面卡片

- **今日课程**
  - 参考掌上猪科课程卡样式：标题、日期/星期/周次、课程行；
  - 显示开始时间、节次、课程名、教室/教师/周次、下课时间；
  - 下课后整张课程卡变浅并显示「✓ 已完成」；
  - `List` 支持卡片内滚动，2×2/2×4/4×4 均可使用；
  - 登录后自动同步，支持手动同步。
- **我的待办**
  - 接入门户待办接口，显示标题/内容摘要；
  - 深色列表卡，支持滚动；无待办显示「暂无待办」。
- **智能水电**
  - 通过 `getbindroom` 取房间，再调 `h5_getstuindexpage.modlist`
    读取电控/冷水/热水读数；
  - 显示「剩余电量（度）/ 剩余冷水、热水（吨）」，不显示价格；
  - 2×2/2×4/4×4，项目多时可滚动；
  - 完美校园接口失败时，可从应用内智能水电页面读取已显示的读数。

### 登录与账号

- CAS 登录页自动识别 6~20 位数字学号，写入本地并触发水电查询；
- 设置页仍保留「水电查询学号」用于修正；
- 只保存学号，不保存密码。

### 网页与支付

- 网页附件下载：下载到沙箱并用 Preview Kit 打开；
- 首页搜索、添加应用搜索；
- 微信/支付宝 `weixin://`/`alipays://` 直接 `startAbility` 拉起 App，
  H5 收银台才交给浏览器；不再白屏/卡死；
- 修复应用内智能水电页因自动刷新导致的一次性 `ST` 票根失效。

### 主题与图标

- 深色模式「我的卡片」/返回按钮对比度；
- 深色 + 沉浸光感「强」时，底部页签改为深色玻璃
  （深色 `bar_frost` 改为黑色半透明，选中图标 #8AB4FF、未选中 #A6ADB8）；
- 应用图标校徽居中。

## 已知限制

- 课程/待办接口来自学校旧移动端/门户，学校改版可能失效；
- 完美校园与智能水电接口均非公开文档接口，可能被风控；
- 自动识别学号依赖 CAS 登录页输入框结构，识别失败时可在设置手动填；
- 页面文字读取依赖页面把「度/吨」显示在 DOM 中。

## 验证

```text
powershell -NoProfile -ExecutionPolicy Bypass -File .\build-hap.ps1 -Clean
BUILD SUCCESSFUL
HAP: 1,072,691 bytes
SHA-256: 16E1E250CC6778243B9CF7ECBD6F41231DD0C8DC03A7690C9B81141F0B122070
```

无真机账号，未做端到端真机截图；构建与接口/协议路径已逐项核对。
