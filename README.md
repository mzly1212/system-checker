# System Checker - Windows 电脑全面体检脚本

一个 PowerShell 脚本，一次性完成 20 项系统健康检查，输出中文体检报告。无需安装任何依赖，Windows 10/11 自带环境即可运行。

## 检查项目

| # | 检查项 | 说明 |
|---|--------|------|
| 1 | WHEA 硬件纠错 | PCIe/总线/缓存层的硬件错误事件 |
| 2 | 意外断电/脏关机 | Kernel-Power 41 事件统计 |
| 3 | 蓝屏/内核崩溃 | 30 天内 WER 系统错误报告 |
| 4 | 显卡驱动重置 | TDR 事件（游戏黑屏/闪退元凶） |
| 5 | 文件系统/磁盘 I/O 错误 | NTFS、disk、storahci/stornvme 关键事件 |
| 6 | 磁盘健康与空间 | 物理磁盘健康状态 + 分区剩余空间告警 |
| 7 | 系统日志错误 | 已过滤 Schannel/DCOM 等已知无害噪音 |
| 8 | 应用崩溃 | 近 3 天按程序分组统计 |
| 9 | 服务启动失败 | 近 24 小时，已过滤无害项 |
| 10 | USB 设备断连 | 物理断连事件（无线外设卡顿排查） |
| 11 | 设备管理器异常 | 已过滤板厂功能挂件等无害项 |
| 12 | Windows 激活状态 | 许可证状态检查 |
| 13 | 内存 XMP | 实际频率 vs 标称频率 |
| 14 | GPU 状态 | nvidia-smi 温度/占用/PCIe 链路（N 卡） |
| 15 | 快速启动/休眠 | 脏关机元凶检查 |
| 16 | 当前资源占用 | CPU 负载 + 内存余量 |
| 17 | Windows 更新 | 待装更新列表 |
| 18 | 系统文件深度扫描 | SFC/DISM（可选，需管理员 + `-Deep`） |

## 使用方法

**方式一**：双击 `RunHealthCheck.bat`

**方式二**：命令行运行

```powershell
powershell -ExecutionPolicy Bypass -File .\ComputerHealthCheck.ps1
```

### 可选参数

```powershell
# 指定事件回看天数（默认 7 天）
powershell -ExecutionPolicy Bypass -File .\ComputerHealthCheck.ps1 -Days 14

# 附加 SFC/DISM 系统文件深度扫描（需管理员，较慢）
powershell -ExecutionPolicy Bypass -File .\ComputerHealthCheck.ps1 -Deep
```

> 提示：非管理员运行时仅第 18 项深度扫描跳过，其余检查不受影响。

## 输出

- **屏幕**：实时逐项输出检查结果（`[通过]` / `[注意]` / `[异常]` / `[信息]`）
- **报告文件**：保存到脚本目录下 `logs/ComputerHealthReport_时间戳.txt`
  - 目录不存在时自动创建；若不可写则依次降级到「文档」目录、TEMP
- **体检总结**：末尾汇总通过/注意/异常项数，异常项单独列出

## 示例输出

```
=================== 体检总结 ===================
通过 12 项 | 注意 2 项 | 异常 1 项

!!! 发现异常, 需要处理:
  [异常] 意外断电/脏关机: 3 次 (11-02 21:14 | 10-28 09:36 | 10-25 23:50) - 每次都是文件系统轮盘赌, 排查供电/关机习惯/快速启动
```

## 许可

MIT
