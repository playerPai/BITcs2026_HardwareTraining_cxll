# 一键切换流水线 CPU 的测试程序（与单周期版 切换测试程序.ps1 同一套路）
# 用法（在 计租\流水线cpu 目录下）：
#   powershell -ExecutionPolicy Bypass -File .\切换测试程序_流水线.ps1 inst26
#   可选参数: inst26 / raw / loaduse / branch / sort16   （默认 inst26）
# 作用：把选中的 .mem 复制到流水线工程的 xsim 仿真目录并命名为 inst.mem
#       （PipelineCPU.v 的 imem 用 $readmemh("inst.mem", rom) 加载），
#       之后在 Vivado 里先 Stop 仿真再重新 Run Behavioral Simulation 即可。

param([string]$Test = 'inst26')

$map = @{
    'inst26'  = 'inst26_test.mem'
    'raw'     = 'raw_test.mem'
    'loaduse' = 'loaduse_test.mem'
    'branch'  = 'branch_test.mem'
    'sort16'  = 'sort16.mem'
}

if (-not $map.ContainsKey($Test)) {
    Write-Error "未知测试名: $Test （可选: $($map.Keys -join ' / ')）"
    exit 1
}

$srcFile = Join-Path $PSScriptRoot (Join-Path '..\单周期cpu\测试程序\机器代码' $map[$Test])
$dstDir  = Join-Path $PSScriptRoot 'PipelineProject\pipeline_cpu.sim\sim_1\behav\xsim'
$dstFile = Join-Path $dstDir 'inst.mem'

if (-not (Test-Path $srcFile)) { Write-Error "找不到源文件: $srcFile"; exit 1 }

# 仿真目录在首次运行仿真后才由 Vivado 生成；没有就先建一个
if (-not (Test-Path $dstDir)) {
    New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
    Write-Host "[提示] 仿真目录不存在，已新建: $dstDir"
}

# 备份当前 inst.mem（若存在）
if (Test-Path $dstFile) {
    $bak = $dstFile + '.bak'
    Copy-Item $dstFile $bak -Force
    Write-Host "已备份当前 inst.mem -> $bak"
}

Copy-Item $srcFile $dstFile -Force
Write-Host "[OK] 已切换: $($map[$Test]) ($((Get-Content $srcFile | Measure-Object -Line).Lines) 条指令) -> $dstFile"
Write-Host "下一步：Vivado 中先 Stop（或关闭仿真窗口），再重新 Run Behavioral Simulation。"