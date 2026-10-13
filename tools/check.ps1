[CmdletBinding()]
param(
    [string]$FlutterCommand = 'flutter',
    [string]$DartCommand = 'dart'
)

$ErrorActionPreference = 'Stop'
$checkRoot = Split-Path -Parent $PSScriptRoot
$flutterTool = Get-Command -Name $FlutterCommand -ErrorAction Stop
$dartTool = Get-Command -Name $DartCommand -ErrorAction Stop
$nodeTool = Get-Command node -ErrorAction Stop
$gitTool = Get-Command git -ErrorAction Stop

Push-Location -LiteralPath $checkRoot
try {
    & $nodeTool.Source 'tools/check_localizations.mjs'
    if ($LASTEXITCODE -ne 0) { throw '八语言文案检查失败' }
    & $flutterTool.Source analyze --no-pub lib
    if ($LASTEXITCODE -ne 0) { throw '生产代码静态检查失败' }
    & $dartTool.Source format --output=none --set-exit-if-changed lib
    if ($LASTEXITCODE -ne 0) { throw '生产代码格式检查失败' }

    $sourceCommit = & $gitTool.Source -C $checkRoot rev-parse HEAD
    if ($LASTEXITCODE -ne 0) { throw '无法读取源码提交' }
    $sourceCommit = $sourceCommit.Trim()
    $checkOutput = Join-Path $checkRoot 'test/checks'
    New-Item -ItemType Directory -Path $checkOutput -Force | Out-Null
    $indexOutput = Join-Path $checkOutput 'official-source-index.json'
    & $nodeTool.Source 'tools/publish_sources.mjs' --commit $sourceCommit --output $indexOutput
    if ($LASTEXITCODE -ne 0) { throw '官方源离线校验失败' }

    Write-Host '检查通过。生成的索引仅用于本地预览；未提交改动不会发布。'
} finally {
    Pop-Location
}
