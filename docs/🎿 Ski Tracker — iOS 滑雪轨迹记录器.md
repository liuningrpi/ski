# 🎿 Ski Tracker — iOS 滑雪轨迹记录器

一款轻量级 iOS 滑雪轨迹记录 App，使用 Swift + SwiftUI 构建，支持实时 GPS 轨迹录制、地图渲染、统计指标展示和本地 JSON 存储。无需上架 App Store，通过 Xcode 直接安装到 iPhone 即可使用。

---

## 功能特性

| 功能 | 状态 | 说明 |
|------|------|------|
| GPS 定位权限请求 | ✅ MVP | 支持 When In Use / Always |
| Start / Stop 录制 | ✅ MVP | 一键开始/停止，停止时自动保存 |
| 地图轨迹折线 | ✅ MVP | MKPolyline + 自动跟随 |
| 实时统计指标 | ✅ MVP | 时长/距离/最高速度/平均速度/海拔/落差 |
| 本地 JSON 保存 | ✅ MVP | Documents/last_session.json |
| 历史回看 | ✅ MVP | 加载上次 session 的轨迹与统计 |
| 后台/锁屏录制 | ✅ V1.1 | Background Location Updates |
| 动态省电策略 | ✅ V1.1 | 根据速度自动调整 distanceFilter |
| 飘点/瞬移过滤 | ✅ | accuracy ≤ 20m + 单步 ≤ 100m |
| 异常速度过滤 | ✅ | speed > 60 m/s 自动忽略 |

---

## 技术栈

- **语言**: Swift 5.9+
- **UI 框架**: SwiftUI
- **定位**: CoreLocation
- **地图**: MapKit (UIViewRepresentable + MKPolyline)
- **存储**: FileManager + JSON (Codable)
- **最低版本**: iOS 17.0
- **开发工具**: Xcode 15+

---

## 项目结构

```
SkiTracker/
├── SkiTracker.xcodeproj/
│   └── project.pbxproj
├── SkiTracker/
│   ├── App/
│   │   └── SkiTrackerApp.swift          # App 入口 + 依赖注入
│   ├── Location/
│   │   └── LocationTracker.swift        # CLLocationManager 封装
│   ├── Model/
│   │   └── TrackModels.swift            # TrackPoint / TrackSession 数据模型
│   ├── Storage/
│   │   └── SessionStore.swift           # JSON 读写存储层
│   ├── UI/
│   │   ├── ContentView.swift            # 主界面（权限/录制/地图/统计）
│   │   ├── TrackMapView.swift           # 地图 + 折线渲染
│   │   ├── StatsView.swift              # 统计指标卡片
│   │   └── HistoryView.swift            # 历史记录回看
│   ├── Assets.xcassets/
│   └── Info.plist                       # 权限声明 + 后台模式
└── README.md
```

---

## 如何在真机上运行

### 前置条件

1. **Mac** 安装 Xcode 15 或更高版本
2. **iPhone** 运行 iOS 17.0 或更高版本
3. **Apple ID**（免费即可，无需付费开发者账号）

### 步骤

1. **克隆项目**
   ```bash
   git clone https://github.com/<your-username>/SkiTracker.git
   cd SkiTracker
   ```

2. **用 Xcode 打开项目**
   ```bash
   open SkiTracker.xcodeproj
   ```

3. **配置签名**
   - 在 Xcode 中选择 `SkiTracker` target
   - 进入 **Signing & Capabilities**
   - 选择你的 **Team**（Apple ID）
   - 如有需要，修改 **Bundle Identifier** 为唯一值（如 `com.yourname.skitracker`）

4. **连接 iPhone**
   - 用数据线连接 iPhone 到 Mac
   - 在 Xcode 顶部选择你的设备作为运行目标
   - 首次连接可能需要在 iPhone 上信任该电脑

5. **编译运行**
   - 按 `Cmd + R` 或点击 ▶️ 按钮
   - 首次安装后，需要在 iPhone 上：
     - 前往 **设置 → 通用 → VPN 与设备管理**
     - 信任你的开发者证书

6. **授权定位**
   - App 启动后点击「授权定位」按钮
   - 在系统弹窗中选择「使用 App 时允许」或「始终允许」

---

## 权限设置说明

| 权限 | 用途 | 必须？ |
|------|------|--------|
| When In Use Location | 前台录制轨迹 | ✅ 必须 |
| Always Location | 后台/锁屏持续录制 | 可选 (V1.1) |
| Background Location | 后台定位更新 | 可选 (V1.1) |

如果定位权限被拒绝，App 会显示提示并引导用户前往系统设置开启。

---

## 如何导出 last_session.json

录制完成后，轨迹数据自动保存为 JSON 文件。导出方式：

### 方法 1：通过 Xcode

1. 连接 iPhone 到 Mac
2. 打开 Xcode → **Window → Devices and Simulators**
3. 选择你的设备 → 找到 **Ski Tracker** App
4. 点击齿轮图标 → **Download Container**
5. 右键 `.xcappdata` 文件 → **Show Package Contents**
6. 导航到 `AppData/Documents/last_session.json`

### 方法 2：通过 Finder (iOS 17+)

1. 连接 iPhone 到 Mac
2. 在 Finder 中选择设备 → **文件** 标签
3. 展开 **Ski Tracker** → 拖出 `last_session.json`

### JSON 数据格式示例

```json
{
  "id": "A1B2C3D4-...",
  "startedAt": "2025-01-15T09:30:00Z",
  "endedAt": "2025-01-15T11:45:00Z",
  "deviceInfo": "iPhone",
  "points": [
    {
      "id": "...",
      "latitude": 39.9042,
      "longitude": 116.4074,
      "altitude": 2150.5,
      "horizontalAccuracy": 5.0,
      "verticalAccuracy": 3.0,
      "speed": 12.5,
      "course": 180.0,
      "timestamp": "2025-01-15T09:30:01Z"
    }
  ]
}
```

---

## 验收测试脚本

按以下步骤测试 App 功能：

1. **权限测试**
   - 室外开阔处打开 App
   - 点击「授权定位」→ 系统弹窗出现 → 选择允许
   - 左上角状态变为绿色「使用时允许」

2. **录制测试**
   - 点击「开始滑雪」
   - 步行或移动 200–500 米
   - 观察地图折线随移动更新
   - 观察统计数据实时变化
   - 点击「停止录制」→ 确认停止

3. **距离精度验证**
   - 确认显示距离与实际移动距离误差在 5–15% 以内

4. **持久化测试**
   - 停止后完全杀掉 App（从后台划掉）
   - 重新打开 App
   - 点击右上角时钟图标 → 进入历史记录
   - 确认轨迹能重绘、统计数据一致

5. **后台测试 (V1.1)**
   - 开始录制 → 锁屏 5 分钟 → 期间步行移动
   - 解锁后确认轨迹点持续增长、折线连续

---

## 数据过滤策略

为保证轨迹质量，App 内置以下过滤机制：

| 过滤规则 | 阈值 | 说明 |
|----------|------|------|
| 水平精度 | ≤ 20m | 丢弃精度差的 GPS 点 |
| 单步距离 | ≤ 100m | 过滤瞬移/飘点 |
| 速度上限 | ≤ 60 m/s (216 km/h) | 过滤异常速度值 |
| 无效速度 | speed < 0 | CLLocation 返回 -1 表示无效 |

---

## 注意事项

- 所有速度和海拔数据**基于设备 GPS 定位估算**，仅供参考
- 免费 Apple ID 签名的 App 有效期为 7 天，到期后需重新安装
- 建议在开阔区域使用，树林/建筑密集区 GPS 信号可能不稳定
- 持续使用 GPS 会消耗电量，建议充满电后使用

---

## License

MIT License
