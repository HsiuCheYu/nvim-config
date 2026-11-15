<#
.SYNOPSIS
  一次安裝這份 nvim 設定需要的所有東西 (Windows 10/11,使用 winget),空環境即可使用。

.DESCRIPTION
  可重複執行:每次都會把 neovim 更新到最新版,其餘工具已符合版本就略過。
  依賴清單與 lua/config/deps.lua 保持一致;新增依賴時兩邊一起改。
  Ubuntu 請使用 ubuntu 分支的 install.sh。

.PARAMETER NoRust
  不安裝 Rust 工具鏈 (rustup / rust-analyzer / clippy)。

.PARAMETER NoFont
  不安裝 Nerd Font (JetBrains Mono)。

.PARAMETER NoPlugins
  不安裝外掛、treesitter parser 與 Mason 套件。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\install.ps1
#>
[CmdletBinding()]
param(
    [switch]$NoRust,
    [switch]$NoFont,
    [switch]$NoPlugins
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'  # Windows PowerShell 5.1 的進度條會讓 Invoke-WebRequest 慢很多

$MinNvim = [version]'0.12.0'        # nvim-treesitter (main) 要求
$MinTreeSitter = [version]'0.26.1'  # nvim-treesitter (main) 要求,且不能用 npm 版
$MingwDir = 'C:\mingw64\bin'        # lua/plugins/lsp.lua 的 clangd --query-driver 指向這裡

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
    param([string]$Id, [switch]$Required)
    Log "winget install $Id"
    winget install --id $Id --exact --silent --accept-package-agreements --accept-source-agreements
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
if (Have 'nvim') {
    Log '更新 neovim 到最新版 (winget)'
    winget upgrade --id Neovim.Neovim --exact --silent --accept-package-agreements --accept-source-agreements
    if ($WingetOk -notcontains $LASTEXITCODE) {
        Warn "winget 無法更新 neovim (結束代碼 $LASTEXITCODE)。若 nvim 不是用 winget 裝的,請自行更新。"
    }
    Update-SessionPath
} else {
    Install-Winget 'Neovim.Neovim' -Required
}
$nvimVer = if (Have 'nvim') { Get-FirstVersion ((nvim --version | Select-Object -First 1) | Out-String) }
if (-not $nvimVer -or $nvimVer -lt $MinNvim) {
    Warn "neovim $nvimVer 低於 $MinNvim (nvim-treesitter main 的要求),請更新後再開啟"
} else {
    Log "neovim $nvimVer"
}

# ------------------------------------------------------ 一般 CLI 工具 (winget) --
if (-not (Have 'git')) { Install-Winget 'Git.Git' -Required }
if (-not (Have 'rg')) { Install-Winget 'BurntSushi.ripgrep.MSVC' -Required }
if (-not (Have 'fd')) { Install-Winget 'sharkdp.fd' }
if (-not (Have 'npm')) { Install-Winget 'OpenJS.NodeJS.LTS' -Required }  # Mason 用 npm 安裝 prettier / jsonls
if (-not (Have 'lazygit')) { Install-Winget 'JesseDuffield.lazygit' }
if (-not (Have 'clangd')) { Install-Winget 'LLVM.LLVM' }                 # 選用:C / C++ LSP
if (-not $NoFont) { Install-Winget 'DEVCOM.JetBrainsMonoNerdFont' }      # 選用:mini.icons 的圖示

# ------------------------------------------- C 編譯器:mingw64 的 gcc (給 treesitter) --
if ((Have 'gcc') -or (Have 'clang')) {
    Log 'C 編譯器已安裝'
} elseif (Test-Path (Join-Path $MingwDir 'gcc.exe')) {
    Log "找到 $MingwDir,加入 PATH"
    Add-UserPath $MingwDir
} else {
    Log '安裝 mingw-w64 (WinLibs)'
    Install-Winget 'BrechtSanders.WinLibs.POSIX.UCRT'
    # winget 會把它放在 WinGet\Packages 底下,找出 gcc.exe 所在資料夾並加入 PATH
    $pkgRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    $gcc = Get-ChildItem -Path $pkgRoot -Recurse -Filter gcc.exe -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -like '*WinLibs*' } | Select-Object -First 1
    if ($gcc) {
        Add-UserPath $gcc.DirectoryName
        Warn "gcc 在 $($gcc.DirectoryName),而 lua/plugins/lsp.lua 的 clangd --query-driver 指向 $MingwDir。若要用 clangd,請把該路徑改成上面的位置,或把 mingw64 放到 C:\mingw64。"
    } else {
        Warn '找不到 gcc.exe (安裝失敗或尚未生效)。treesitter 需要 C 編譯器,請自行安裝 mingw-w64 並加入 PATH,再重新執行本腳本'
    }
}

# --------------------------------------- tree-sitter-cli (官方 release,不可用 npm) --
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
# 選用工具:失敗只警告,不影響後面的外掛安裝
if ($NoRust) {
    Log '略過 Rust 工具鏈 (-NoRust)'
} else {
    try {
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
    } catch {
        Warn "Rust 工具鏈安裝失敗 (選用,Rust 專案才會用到):$($_.Exception.Message)"
    }
}

# ------------------------------------- 外掛 / parser / Mason 套件 (headless) --
if ($NoPlugins) {
    Log '略過外掛安裝 (-NoPlugins)'
} elseif (-not (Have 'nvim')) {
    Warn '找不到 nvim,略過外掛安裝。請重開終端機後再執行本腳本'
} else {
    $cfg = Join-Path $env:LOCALAPPDATA 'nvim'
    $here = $PSScriptRoot
    if (-not (Test-Path $cfg)) {
        Log "連結設定:$cfg -> $here"
        New-Item -ItemType Junction -Path $cfg -Value $here | Out-Null  # junction 不需要系統管理員權限
    }
    $item = Get-Item $cfg -Force
    $target = if ($item.LinkType) { @($item.Target)[0] } else { $item.FullName }
    if ((Resolve-Path $target).ProviderPath -ne (Resolve-Path $here).ProviderPath) {
        Warn "$cfg 已存在且不是這個 repo,略過外掛安裝。請自行處理後再執行 nvim"
    } else {
        Log '安裝外掛 (Lazy! sync)'
        nvim --headless '+Lazy! sync' +qa
        Log '安裝 treesitter parser 與 Mason 套件 (可能需要幾分鐘)'
        nvim --headless "+lua require('config.bootstrap').run()" +qa
    }
}

Log '完成。請重新開啟終端機讓 PATH 生效;開啟 nvim 後執行 :Deps 檢查所有依賴,Copilot 請執行 :Copilot auth'
if (-not $NoFont) { Log '提醒:請在終端機設定使用 "JetBrainsMono Nerd Font",否則圖示會顯示成方框' }
