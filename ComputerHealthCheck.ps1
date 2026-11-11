<#
.SYNOPSIS
  电脑全面体检脚本 - 涵盖硬件错误、断电记录、磁盘、文件系统、驱动、外设、系统文件等 20 项检查
.USAGE
  方式一: 双击同目录的 RunHealthCheck.bat
  方式二: powershell -ExecutionPolicy Bypass -File .\ComputerHealthCheck.ps1
  可选参数: -Days 14   (事件回看天数, 默认 7)
            -Deep      (需管理员: 附加 SFC/DISM 系统文件深度扫描, 较慢)
.OUTPUT
  屏幕输出 + 在脚本目录/logs 下生成完整报告 ComputerHealthReport_时间戳.txt
#>
param(
    [int]$Days = 7,
    [switch]$Deep
)

$ErrorActionPreference = 'SilentlyContinue'
$now = Get-Date
$script:Report  = New-Object System.Text.StringBuilder
$script:Verdict = New-Object System.Collections.Generic.List[object]

function Emit([string]$t = '') {
    Write-Host $t
    [void]$script:Report.AppendLine($t)
}
function Add-Verdict([string]$section, [string]$status, [string]$detail) {
    $script:Verdict.Add([pscustomobject]@{Section=$section; Status=$status; Detail=$detail})
    $icon = switch ($status) { 'PASS' {'[通过]'} 'WARN' {'[注意]'} 'FAIL' {'[异常]'} 'INFO' {'[信息]'} }
    Emit ('  {0} {1}: {2}' -f $icon, $section, $detail)
}

# ============ 0. 系统概况 ============
Emit ''
Emit '================= 电脑全面体检 ================='
$os   = Get-CimInstance Win32_OperatingSystem
$boot = $os.LastBootUpTime
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Emit ('系统: {0} | 开机于 {1} (已运行 {2:N1} 小时)' -f $os.Caption, $boot, ($now - $boot).TotalHours)
Emit ('回看窗口: 最近 {0} 天 | 管理员权限: {1}' -f $Days, $isAdmin)
if (-not $isAdmin) { Emit '提示: 未用管理员运行, SFC/DISM 深度扫描将跳过 (其余检查不受影响)' }

# ============ 1. WHEA 硬件纠错 (PCIe/CPU/内存硬件层) ============
Emit ''
Emit '--- 1. WHEA 硬件错误 (PCIe/总线/缓存纠错) ---'
$whea = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'; StartTime=$now.AddDays(-$Days)}
$wc = if ($whea) { @($whea).Count } else { 0 }
if ($wc -eq 0) {
    Add-Verdict 'WHEA硬件错误' 'PASS' "窗口内 0 条"
} else {
    $ids = @($whea | Group-Object Id | ForEach-Object { "Id $($_.Name) x$($_.Count)" }) -join ', '
    Add-Verdict 'WHEA硬件错误' 'FAIL' "$wc 条 ($ids) - 通常指向 PCIe 链路/硬件信号问题, 建议联系排查"
}

# ============ 2. 脏关机 / 断电记录 ============
Emit ''
Emit '--- 2. 关机健康 (意外断电检测) ---'
$dirty = Get-WinEvent -FilterHashtable @{LogName='System'; Id=41; ProviderName='Microsoft-Windows-Kernel-Power'; StartTime=$now.AddDays(-$Days)}
$dc = if ($dirty) { @($dirty).Count } else { 0 }
if ($dc -eq 0) {
    Add-Verdict '意外断电/脏关机' 'PASS' "窗口内 0 次"
} else {
    $times = @($dirty | Sort-Object TimeCreated -Descending | Select-Object -First 5 | ForEach-Object { $_.TimeCreated.ToString('MM-dd HH:mm') }) -join ' | '
    Add-Verdict '意外断电/脏关机' 'FAIL' "$dc 次 ($times) - 每次都是文件系统轮盘赌, 排查供电/关机习惯/快速启动"
}

# ============ 3. 蓝屏 / 内核崩溃 ============
Emit ''
Emit '--- 3. 蓝屏 / 内核崩溃 ---'
$bsod = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WER-SystemErrorReporting'; StartTime=$now.AddDays(-30)}
$bc = if ($bsod) { @($bsod).Count } else { 0 }
if ($bc -eq 0) {
    Add-Verdict '蓝屏(30天)' 'PASS' '0 次'
} else {
    Add-Verdict '蓝屏(30天)' 'FAIL' "$bc 次 - 需分析 C:\Windows\Minidump"
}

# ============ 4. GPU 驱动重置 (游戏闪退/黑屏元凶) ============
Emit ''
Emit '--- 4. 显卡驱动崩溃/重置 ---'
$nvres = Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$now.AddDays(-$Days)} -MaxEvents 5000 |
    Where-Object { $_.ProviderName -eq 'nvlddmkm' -or $_.Id -eq 4101 }
$nc = if ($nvres) { @($nvres).Count } else { 0 }
if ($nc -eq 0) {
    Add-Verdict '显卡驱动重置' 'PASS' '窗口内 0 次'
} else {
    Add-Verdict '显卡驱动重置' 'WARN' "$nc 次 (TDR) - 游戏中黑屏闪烁/闪退, 关注驱动版本与温度"
}

# ============ 5. 文件系统 / 磁盘 I/O 错误 ============
Emit ''
Emit '--- 5. 文件系统 / 磁盘错误事件 ---'
$fserr = Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$now.AddDays(-$Days)} -MaxEvents 5000 |
    Where-Object { ($_.ProviderName -eq 'Ntfs' -and $_.Id -in 50,55,137) -or ($_.ProviderName -in 'disk','volmgr','storahci','stornvme' -and $_.Id -in 7,11,51,153,154) }
$fc = if ($fserr) { @($fserr).Count } else { 0 }
if ($fc -eq 0) {
    Add-Verdict '文件系统/磁盘IO' 'PASS' '窗口内 0 条'
} else {
    $sample = @($fserr | Select-Object -First 3 | ForEach-Object { "$($_.ProviderName)/Id$($_.Id)" }) -join ', '
    Add-Verdict '文件系统/磁盘IO' 'FAIL' "$fc 条 ($sample) - 立即备份数据, 检查硬盘健康"
}

# ============ 6. 磁盘健康 + 空间 ============
Emit ''
Emit '--- 6. 磁盘健康与剩余空间 ---'
$disks = Get-PhysicalDisk
foreach ($d in $disks) {
    if ($d.HealthStatus -eq 'Healthy') {
        Add-Verdict "硬盘 $($d.FriendlyName)" 'PASS' "健康 ($($d.MediaType))"
    } else {
        Add-Verdict "硬盘 $($d.FriendlyName)" 'FAIL' "状态: $($d.HealthStatus) - 尽快备份数据!"
    }
}
$vols = Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.Size -gt 10GB }
foreach ($v in $vols) {
    $pct = [math]::Round($v.SizeRemaining / $v.Size * 100, 1)
    $freeGB = [math]::Round($v.SizeRemaining / 1GB)
    if ($pct -lt 10)       { Add-Verdict "分区 $($v.DriveLetter):" 'FAIL' "仅剩 $freeGB GB ($pct%) - 立刻清理, 影响SSD寿命与性能" }
    elseif ($pct -lt 15)   { Add-Verdict "分区 $($v.DriveLetter):" 'WARN' "剩 $freeGB GB ($pct%), 建议清理" }
    else                   { Add-Verdict "分区 $($v.DriveLetter):" 'PASS' "剩 $freeGB GB ($pct%)" }
}

# ============ 7. 系统级错误 (已过滤无害噪音) ============
Emit ''
Emit '--- 7. 系统日志错误 (已过滤已知噪音) ---'
$knownNoise = @('Schannel','Perflib','Microsoft-Windows-DistributedCOM','Microsoft-Windows-TPM-WMI')
$syserr = Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=$now.AddDays(-$Days)} -MaxEvents 2000 |
    Where-Object { $knownNoise -notcontains $_.ProviderName }
$sc = if ($syserr) { @($syserr).Count } else { 0 }
if ($sc -eq 0) {
    Add-Verdict '系统错误(过滤后)' 'PASS' '窗口内 0 条'
} else {
    $top = @($syserr | Group-Object ProviderName, Id | Sort-Object Count -Descending | Select-Object -First 5 |
        ForEach-Object { "$($_.Group[0].ProviderName)/Id$($_.Group[0].Id) x$($_.Count)" }) -join ', '
    Add-Verdict '系统错误(过滤后)' 'WARN' "$sc 条: $top"
}
$tpm = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-TPM-WMI'; Id=1801; StartTime=$now.AddDays(-$Days)}
if ($tpm) { Add-Verdict 'SecureBoot证书' 'INFO' 'TPM 1801 提示 CA 密钥待更新 (非紧急, 见 aka.ms/securebootca)' }

# ============ 8. 应用崩溃 ============
Emit ''
Emit '--- 8. 应用崩溃 ---'
$apperr = Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='Application Error'; StartTime=$now.AddDays(-3)} -MaxEvents 50
$ac = if ($apperr) { @($apperr).Count } else { 0 }
if ($ac -eq 0) {
    Add-Verdict '应用崩溃(3天)' 'PASS' '0 次'
} else {
    $apps = @($apperr | ForEach-Object {
        $x = [xml]$_.ToXml()
        ($x.Event.EventData.Data | Where-Object { $_.Name -eq 'AppName' }).'#text'
    } | Group-Object | Sort-Object Count -Descending | Select-Object -First 4 | ForEach-Object { "$($_.Name) x$($_.Count)" }) -join ', '
    Add-Verdict '应用崩溃(3天)' 'WARN' "$ac 次: $apps"
}

# ============ 9. 服务失败 ============
Emit ''
Emit '--- 9. 服务启动失败 (已过滤无害项) ---'
$knownSvc = @('GamingServices','ToDesk','Steam Client Service','EAAntiCheatService')
$svcfail = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Service Control Manager'; Level=1,2; StartTime=$now.AddDays(-1)} -MaxEvents 100
$svcfail = $svcfail | Where-Object { $msg = $_.Message; -not ($knownSvc | Where-Object { $msg -match $_ }) }
$vc = if ($svcfail) { @($svcfail).Count } else { 0 }
if ($vc -eq 0) {
    Add-Verdict '服务失败(24h)' 'PASS' '无'
} else {
    $names = @($svcfail | Select-Object -First 3 | ForEach-Object { (($_.Message -split "`n")[0]).Trim() }) -join ' ; '
    Add-Verdict '服务失败(24h)' 'WARN' "$vc 条: $names"
}

# ============ 10. USB 外设断连 (鼠标/键盘掉线) ============
Emit ''
Emit '--- 10. USB 设备断连 ---'
$usbrem = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Kernel-PnP'; Id=411; StartTime=$now.AddDays(-$Days)} -MaxEvents 200
$usbrem = $usbrem | Where-Object {
    $x = [xml]$_.ToXml()
    $iid = ($x.Event.EventData.Data | Where-Object { $_.Name -eq 'DeviceInstanceId' }).'#text'
    $iid -and $iid -notlike 'ROOT\*'
}
$uc = if ($usbrem) { @($usbrem).Count } else { 0 }
if ($uc -eq 0) {
    Add-Verdict 'USB物理断连' 'PASS' "窗口内 0 次"
} else {
    Add-Verdict 'USB物理断连' 'WARN' "$uc 次 - 无线外设顿卡若伴随此值增长, 查USB口/线材; 若此值为0仍感觉卡顿, 是无线链路(接收器位置/电池/干扰)问题"
}

# ============ 11. 问题设备 (已过滤无害项) ============
Emit ''
Emit '--- 11. 设备管理器异常项 ---'
$knownDev = @('PS/2','Synthetic Gamepad','Base System Device')
$baddev = Get-PnpDevice -PresentOnly | Where-Object { $_.Status -ne 'OK' -and $_.Status -ne 'Unknown' }
$baddev = $baddev | Where-Object { $n = $_.FriendlyName; -not ($knownDev | Where-Object { $n -match $_ }) }
if (-not $baddev -or @($baddev).Count -eq 0) {
    Add-Verdict '设备管理器' 'PASS' '无异常设备'
} else {
    $list = @($baddev | Select-Object -First 4 | ForEach-Object {
        $n = if ($_.FriendlyName) { $_.FriendlyName } else { $_.InstanceId }
        "$n [$($_.Status)]"
    }) -join ', '
    Add-Verdict '设备管理器' 'WARN' "异常: $list (匿名 ACPI 设备多为板厂功能挂件, 无害)"
}

# ============ 12. Windows 激活 ============
Emit ''
Emit '--- 12. Windows 激活 ---'
$act = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND Name LIKE 'Windows%'" |
    Select-Object -First 1
if ($act -and $act.LicenseStatus -eq 1) {
    Add-Verdict '系统激活' 'PASS' '已激活'
} elseif ($act) {
    Add-Verdict '系统激活' 'FAIL' "状态码 $($act.LicenseStatus) (1=正常) - 设置>系统>激活 处理"
} else {
    Add-Verdict '系统激活' 'WARN' '未查询到许可证信息'
}

# ============ 13. 内存 XMP ============
Emit ''
Emit '--- 13. 内存频率 (XMP) ---'
$mem = Get-CimInstance Win32_PhysicalMemory | Select-Object -First 1
if ($mem) {
    if ($mem.ConfiguredClockSpeed -lt $mem.Speed) {
        Add-Verdict '内存XMP' 'WARN' "运行 $($_ = $null; $mem.ConfiguredClockSpeed) MHz 低于标称 $($mem.Speed) MHz - BIOS 里开启 XMP"
    } else {
        Add-Verdict '内存XMP' 'PASS' "$($mem.ConfiguredClockSpeed) MHz 满速"
    }
}

# ============ 14. GPU 状态 ============
Emit ''
Emit '--- 14. 显卡状态 ---'
$smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
if ($smi) {
    $g = & nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,pcie.link.gen.current,pcie.link.gen.max,driver_version --format=csv,noheader 2>$null
    if ($g) {
        $p = ($g -split ',').Trim()
        Emit ("  {0} | 驱动 {1} | {2}C | 占用 {3}% | PCIe Gen{4}/Gen{5}max" -f $p[0], $p[5], $p[1], $p[3], $p[4])
        if ([int]$p[1] -gt 85) { Add-Verdict 'GPU温度' 'WARN' "当前 $($p[1])C 偏高" }
        else { Add-Verdict 'GPU状态' 'PASS' "温度 $($p[1])C 正常, 链路 Gen$($p[3])" }
        if ([int]$p[3] -lt [int]$p[4]) { Add-Verdict 'PCIe链路' 'WARN' "当前 Gen$($p[3]) 低于最大 Gen$($p[4]) - 链路被降速" }
    }
} else { Add-Verdict 'GPU状态' 'INFO' '未检测到 nvidia-smi (N卡驱动)' }

# ============ 15. 快速启动/休眠 (脏关机元凶检查) ============
Emit ''
Emit '--- 15. 快速启动 / 休眠 ---'
$hib = Get-Item 'C:\hiberfil.sys' -Force
$hibReg = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled).HiberbootEnabled
if ($hib -and $hibReg -eq 1) {
    Add-Verdict '快速启动' 'INFO' '已开启 (混合关机) - 若出现"点关机后机器假死被断电", 用管理员执行: powercfg /h off'
} elseif (-not $hib) {
    Add-Verdict '快速启动' 'PASS' '休眠已关闭, 全量关机 (最稳)'
} else {
    Add-Verdict '快速启动' 'INFO' '休眠文件存在但注册表开关异常'
}

# ============ 16. CPU / 内存压力 ============
Emit ''
Emit '--- 16. 当前资源占用 ---'
$cs = Get-CimInstance Win32_Processor | Select-Object -First 1
$ramFree = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
$ramTotal = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
$ramPct = [math]::Round($ramFree / $ramTotal * 100, 1)
Emit ("  CPU 负载 {0}% | 内存可用 {1}/{2} GB ({3}%)" -f $cs.LoadPercentage, $ramFree, $ramTotal, $ramPct)
if ($ramPct -lt 10) { Add-Verdict '内存余量' 'WARN' "仅剩 $ramPct% - 关闭大内存应用或加内存" }
else { Add-Verdict '资源占用' 'PASS' "CPU $($cs.LoadPercentage)%, 内存余 $ramPct%" }

# ============ 17. 待装更新 ============
Emit ''
Emit '--- 17. Windows 更新 ---'
Emit '  (查询微软服务器, 约 10~60 秒, 请稍候...)'
try {
    $s = New-Object -ComObject Microsoft.Update.Session
    $r = $s.CreateUpdateSearcher().Search("IsInstalled=0 and IsHidden=0")
    if ($r.Updates.Count -eq 0) {
        Add-Verdict 'Windows更新' 'PASS' '无待装更新'
    } else {
        $list = @($r.Updates | Select-Object -First 3 | ForEach-Object { $_.Title }) -join ' | '
        Add-Verdict 'Windows更新' 'WARN' "待装 $($r.Updates.Count) 项: $list"
    }
} catch {
    Add-Verdict 'Windows更新' 'INFO' '查询失败 (网络/服务), 请在 设置>Windows更新 手动确认'
}

# ============ 18. 深度扫描 (可选, 管理员 + -Deep) ============
Emit ''
Emit '--- 18. 系统文件深度扫描 ---'
if ($Deep -and $isAdmin) {
    Emit '  运行 SFC 验证中 (5~15 分钟, 不修改文件)...'
    $sfc = sfc /verifyonly 2>&1 | Out-String
    if ($sfc -match '没有发现|did not find|no integrity') { Add-Verdict 'SFC系统文件' 'PASS' '未发现损坏' }
    elseif ($sfc -match '损坏|violation|corrupt') { Add-Verdict 'SFC系统文件' 'FAIL' '发现损坏 - 管理员执行 sfc /scannow 修复' }
    else { Add-Verdict 'SFC系统文件' 'INFO' '结果无法解析, 请人工查看输出' }
    Emit '  运行 DISM 组件库扫描中 (5~10 分钟)...'
    $dism = dism /online /cleanup-image /scanhealth 2>&1 | Out-String
    if ($dism -match '无损坏|no corruption') { Add-Verdict 'DISM组件库' 'PASS' '组件库健康' }
    elseif ($dism -match '损坏|corruption') { Add-Verdict 'DISM组件库' 'WARN' '可修复损坏 - 执行 dism /online /cleanup-image /restorehealth' }
} elseif ($Deep -and -not $isAdmin) {
    Add-Verdict '深度扫描' 'INFO' '需要管理员权限: 右键"以管理员身份运行" RunHealthCheck.bat 并加 -Deep'
} else {
    Add-Verdict '深度扫描' 'INFO' '跳过 (加 -Deep 参数并管理员运行可启用 SFC/DISM)'
}

# ============ 总结 ============
Emit ''
Emit '=================== 体检总结 ==================='
$fail = @($script:Verdict | Where-Object { $_.Status -eq 'FAIL' })
$warn = @($script:Verdict | Where-Object { $_.Status -eq 'WARN' })
$pass = @($script:Verdict | Where-Object { $_.Status -eq 'PASS' })
Emit ("通过 {0} 项 | 注意 {1} 项 | 异常 {2} 项" -f $pass.Count, $warn.Count, $fail.Count)
if ($fail.Count -gt 0) {
    Emit ''
    Emit '!!! 发现异常, 需要处理:'
    $fail | ForEach-Object { Emit ("  [异常] {0}: {1}" -f $_.Section, $_.Detail) }
} elseif ($warn.Count -gt 0) {
    Emit ''
    Emit '以下为注意事项 (不致命):'
    $warn | ForEach-Object { Emit ("  [注意] {0}: {1}" -f $_.Section, $_.Detail) }
} else {
    Emit ''
    Emit '全绿! 系统无异常, 放心使用。'
}

# ============ 保存报告 ============
$stamp = Get-Date -Format 'yyyyMMdd_HHmm'
# 保存到脚本目录下的 logs 子目录 (不存在则自动创建), 不可写时依次退到 文档 / TEMP
$dir1 = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'logs'
New-Item -ItemType Directory -Path $dir1 -Force | Out-Null
$dir2 = [Environment]::GetFolderPath('MyDocuments')
$path = $null
foreach ($d in @($dir1, $dir2, $env:TEMP)) {
    $try = Join-Path $d "ComputerHealthReport_$stamp.txt"
    try {
        [IO.File]::WriteAllText($try, $script:Report.ToString(), (New-Object System.Text.UTF8Encoding $true))
        $path = $try
        break
    } catch { continue }
}
Emit ''
if ($path) { Emit ("完整报告已保存: {0}" -f $path) }
else { Emit '报告保存失败, 请检查脚本目录写入权限' }
