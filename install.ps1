<#
.SYNOPSIS
  安裝這份 nvim 設定需要的外部依賴 (Windows 10/11,使用 winget)。

.DESCRIPTION
  可重複執行:已經符合版本的工具會略過。
  依賴清單與 lua/config/deps.lua 保持一致;新增依賴時兩邊一起改。
  macOS / Linux 請用 install.sh。

.PARAMETER NoRust
  不安裝 Rust 工具鏈 (rustup / rust-analyzer / clippy)。

.PARAMETER NoPlugins
  不在最後執行 nvim --headless "+Lazy! sync"。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\install.ps1
#>
[CmdletBinding()]
param(
    [switch]$NoRust,
    [switch]$NoPlugins
)

$ErrorActionPreference = 'Stop'

$MinNvim = [version]'0.12.0'        # nvim-treesitter (main) 要求
$MinTreeSitter = [version]'0.26.1'  # nvim-treesitter (main) 要求,且不能用 npm 版

function Log($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Warn($msg) { Write-Warning $msg }
function Have($name) { [bool](Get-Command $name -ErrorAction SilentlyContinue) }

# winget 安裝完會改 PATH,但目前這個 session 看不到,手動重新讀取
function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
}

function Add-UserPath($dir) {
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (($user -split ';') -notcontains $dir) {
        [Environment]::SetEnvironmentVariable('Path', "$user;$dir", 'User')
    }
    if (($env:Path -split ';') -notcontains $dir) {
        $env:Path = "$env:Path;$dir"
    }
}

function Get-FirstVersion($text) {
    if ($text -match '(\d+\.\d+(\.\d+)?)') { return [version]$Matches[1] }
}

# 已安裝 / 無可用更新 的 winget 結束代碼,視為成功
$WingetOk = @(0, 0x8A150061, 0x8A15002B)

function Install-Winget {
    param([string]$Id, [string[]]$Extra = @(), [switch]$Required)
    Log "winget install $Id"
    winget install --id $Id --exact --silent --accept-package-agreements --accept-source-agreements @Extra
    if ($WingetOk -notcontains $LASTEXITCODE) {
        $msg = "winget 安裝 $Id 失敗 (結束代碼 $LASTEXITCODE)"
        if ($Required) { throw $msg } else { Warn $msg }
    }
    Update-SessionPath
}

if (-not (Have 'winget')) {
    throw '找不到 winget。請從 Microsoft Store 安裝「應用程式安裝程式 (App Installer)」後再執行。'
}
foreach ($tool in 'curl.exe', 'tar.exe') {
    if (-not (Have $tool)) { throw "找不到 $tool (Windows 10 1803 以上內建),請先更新 Windows。" }
}

# ---------------------------------------------------------------- Neovim --
$nvimVer = if (Have 'nvim') { Get-FirstVersion ((nvim --version | Select-Object -First 1) | Out-String) }
if ($nvimVer -and $nvimVer -ge $MinNvim) {
    Log "neovim $nvimVer 已符合 (>= $MinNvim)"
} elseif ($nvimVer) {
    Log "升級 neovim ($nvimVer < $MinNvim)"
    winget upgrade --id Neovim.Neovim --exact --silent --accept-package-agreements --accept-source-agreements
    Update-SessionPath
} else {
    Install-Winget 'Neovim.Neovim' -Required
}

# ------------------------------------------------------ 一般 CLI 工具 (winget) --
if (-not (Have 'git')) { Install-Winget 'Git.Git' -Required }
if (-not (Have 'rg')) { Install-Winget 'BurntSushi.ripgrep.MSVC' -Required }
if (-not (Have 'fd')) { Install-Winget 'sharkdp.fd' }
if (-not (Have 'npm')) { Install-Winget 'OpenJS.NodeJS.LTS' -Required }  # Mason 用 npm 安裝 prettier / jsonls
if (-not (Have 'lazygit')) { Install-Winget 'JesseDuffield.lazygit' }
if (-not (Have 'cmake')) { Install-Winget 'Kitware.CMake' -Required }    # telescope-fzf-native 的建置

# ----------------------------------- C 編譯器:Visual Studio Build Tools (C++) --
# cl.exe 不一定在 PATH 內,所以用 vswhere 偵測 (tree-sitter / cmake 都能自行找到 MSVC)
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$hasMsvc = $false
if (Test-Path $vswhere) {
    $found = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    $hasMsvc = [bool]$found
}
if ($hasMsvc) {
    Log 'MSVC C++ Build Tools 已安裝'
} elseif ((Have 'gcc') -or (Have 'clang')) {
    Log '已有 gcc / clang,略過 MSVC Build Tools'
} else {
    Log '安裝 Visual Studio Build Tools (C++ 工作負載,體積較大,需要系統管理員權限)'
    Install-Winget 'Microsoft.VisualStudio.2022.BuildTools' -Required -Extra @(
        '--override', '--passive --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'
    )
}

# ------------------------------------- tree-sitter-cli (官方 release,不可用 npm) --
$tsVer = if (Have 'tree-sitter') { Get-FirstVersion ((tree-sitter --version) | Out-String) }
if ($tsVer -and $tsVer -ge $MinTreeSitter) {
    Log "tree-sitter $tsVer 已符合 (>= $MinTreeSitter)"
} else {
    Log '安裝 tree-sitter-cli (官方 release)'
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
    $url = "https://github.com/tree-sitter/tree-sitter/releases/latest/download/tree-sitter-windows-$arch.gz"
    $binDir = Join-Path $HOME '.local\bin'
    New-Item -ItemType Directory -Force -Path $binDir | Out-Null
    $gz = Join-Path ([IO.Path]::GetTempPath()) 'tree-sitter.gz'
    Invoke-WebRequest -Uri $url -OutFile $gz
    $in = [IO.File]::OpenRead($gz)
    try {
        $zip = New-Object IO.Compression.GZipStream($in, [IO.Compression.CompressionMode]::Decompress)
        $out = [IO.File]::Create((Join-Path $binDir 'tree-sitter.exe'))
        try { $zip.CopyTo($out) } finally { $out.Dispose(); $zip.Dispose() }
    } finally { $in.Dispose() }
    Remove-Item $gz -Force
    Add-UserPath $binDir
}

# ------------------------------------------------------------------ Rust --
if ($NoRust) {
    Log '略過 Rust 工具鏈 (-NoRust)'
} else {
    if (-not (Have 'rustup')) {
        Install-Winget 'Rustlang.Rustup'
        Add-UserPath (Join-Path $HOME '.cargo\bin')
    }
    if (Have 'rustup') {
        Log '設定 Rust stable 與 rust-analyzer / clippy'
        rustup default stable
        rustup component add rust-analyzer clippy
    } else {
        Warn '找不到 rustup,請重開終端機後再執行本腳本,或自行安裝 Rust'
    }
}

# --------------------------------------------------------------- 外掛同步 --
if (-not $NoPlugins) {
    $cfg = Join-Path $env:LOCALAPPDATA 'nvim'
    $here = $PSScriptRoot
    $same = (Test-Path $cfg) -and ((Resolve-Path $cfg).ProviderPath -eq (Resolve-Path $here).ProviderPath)
    if ($same -and (Have 'nvim')) {
        Log '安裝外掛 (Lazy! sync)'
        nvim --headless '+Lazy! sync' +qa
    } else {
        Warn "此 repo 不在 $cfg,略過外掛安裝。請 clone/連結到該路徑後第一次開 nvim 即會自動安裝"
    }
}

Log '完成。請重新開啟終端機讓 PATH 生效;開啟 nvim 後執行 :Deps 檢查所有依賴,Copilot 請執行 :Copilot auth'
Log '提醒:mini.icons 需要 Nerd Font (例如 winget install --id DEVCOM.JetBrainsMonoNerdFont),並在終端機設定該字型'
