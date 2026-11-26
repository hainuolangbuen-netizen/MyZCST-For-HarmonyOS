# 国区（HarmonyOS）版本

本目录是手表端（Huawei Watch 系列）的工程说明。

## 形态

同一个 App Pack 里有两个模块：

| 模块 | deviceTypes | 作用 |
| --- | --- | --- |
| `entry` | phone / tablet / 2in1 | 手机主程序，负责登录、课表与水电同步、卡片 |
| `wearable` | wearable | 手表端，只做「看」：今日课程、本周课表、宿舍水电 |

## 手表上不放账号

手表端不登录学校系统：CAS 要在网页里输密码，手表上没有合适场景；
也不该把 Cookie 复制到第二台设备。数据由手机推过去：

```
手机登录 → CourseSync / FeeSync 写 CardStore
        → CardData.updateAll() 刷新桌面卡片
        → WatchSync.push() 组装 JSON 并 publish 公共事件
        → 手表收到后写入自己 preferences → WatchHome 重新解析渲染
```

payload 的键名与手机端 `CardStore` 一致（`schedule_text` / `subtitle_text` /
`updated_text` / `fee_room` / `fee_lines` / `fee_updated_text`），
手表端 `common/WatchSync.ets` 直接按同名键读，两边不用各写一套格式。

## 文本格式

沿用桌面卡片那两行文本，手表端只解析、不重新定义格式：

- 课表一行：`开始|结束|节次|课程|教室|教师|周次`，例如
  `08:10|09:50|1-2|软件工程专业导论|博文楼阶梯D301|张老师|1-16周`
- 水电一行：`名称|数值|单位|已用|告警`，例如 `剩余电量|148.20|度|10.03|0`

`WatchModel` 对字段缺失是宽容的：认不出的行跳过，不抛异常；
水电只接受「度 / 吨 / m³」三种单位，避免把金额当读数显示。

## 圆屏适配

- 466×466 圆屏，内容区左右各留 40~46vp，避开圆弧；
- 顶部时间与日期贴边，底部留 18vp + 页点，避免被系统手势遮住；
- 主信息 17~24vp，辅助 8~11vp；页签只有 3 个（课程 / 课表 / 水电），
  左右滑动切换，与手机端 `Tabs` 的交互习惯一致。

## 构建

```powershell
# 手机包（含手表模块，App Pack 里两个模块一起打）
powershell -NoProfile -ExecutionPolicy Bypass -File .\build-hap.ps1

# 只出手表模块的 HAP（调试单模块时用）
powershell -NoProfile -ExecutionPolicy Bypass -File .\build-hap.ps1 -Product wearable
```

`build-hap.ps1 -Product wearable` 会把 `-p product=wearable` 传给 hvigor，
产物在 `wearable/build/default/outputs/default/`。

## 已知限制

- 公共事件只在同一台设备内有效；真正跨端到手表需要 Wear Engine 的设备通道，
  本模块预留了事件名与 payload 结构，接入时只需把 `publish` 换成 Wear Engine 发送；
- 未在真机手表上验证，圆屏布局按 466×466 与 HarmonyOS 手表规范推演。