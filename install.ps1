<#
.SYNOPSIS
  安裝這份 nvim 設定需要的外部依賴 (Windows 10/11,使用 winget)。

.DESCRIPTION
  可重複執行:已經符合版本的工具會略過。
  依賴清單與 lua/config/deps.lua 保持一致;新增依賴時兩邊一起改。
  Ubuntu 請使用 ubuntu 分支的 install.sh。

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
if (-not (Have 'clangd')) { Install-Winget 'LLVM.LLVM' }                 # 選用:C / C++ LSP

# ------------------------------------------- C 編譯器:mingw64 的 gcc (給 treesitter) --
if ((Have 'gcc') -or (Have 'clang')) {
    Log 'C 編譯器已安裝'
} elseif (Test-Path (Join-Path $MingwDir 'gcc.exe')) {
    Log "找到 $MingwDir,加入 PATH"
    Add-UserPath $MingwDir
} else {
    Log '安裝 mingw-w64 (WinLibs)'
    Install-Winget 'BrechtSanders.WinLibs.POSIX.UCRT' -Required
    # winget 會把它放在 WinGet\Packages 底下,找出 gcc.exe 所在資料夾並加入 PATH
    $pkgRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    $gcc = Get-ChildItem -Path $pkgRoot -Recurse -Filter gcc.exe -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -like '*WinLibs*' } | Select-Object -First 1
    if ($gcc) {
        Add-UserPath $gcc.DirectoryName
        Warn "gcc 在 $($gcc.DirectoryName),而 lua/plugins/lsp.lua 的 clangd --query-driver 指向 $MingwDir。若要用 clangd,請把該路徑改成上面的位置,或把 mingw64 放到 C:\mingw64。"
    } else {
        Warn '安裝完成但找不到 gcc.exe,請重開終端機後執行 :Deps 確認'
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
