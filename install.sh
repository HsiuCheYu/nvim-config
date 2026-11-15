#!/usr/bin/env bash
# 安裝這份 nvim 設定需要的外部依賴 (macOS / Debian / Ubuntu)。
# 可重複執行:已經符合版本的工具會略過。Windows 請用 install.ps1。
#
# 用法:./install.sh [--no-rust] [--no-plugins]
#   --no-rust     不安裝 Rust 工具鏈 (rustup / rust-analyzer / clippy)
#   --no-plugins  不在最後執行 nvim --headless "+Lazy! sync"
#
# 依賴清單與 lua/config/deps.lua 保持一致;新增依賴時兩邊一起改。

set -euo pipefail

MIN_NVIM="0.12.0"        # nvim-treesitter (main) 要求
MIN_TREE_SITTER="0.26.1" # nvim-treesitter (main) 要求,且不能用 npm 版
MIN_NODE_MAJOR=18        # Mason 用 npm 安裝 prettier / jsonls

WITH_RUST=1
WITH_PLUGINS=1
for arg in "$@"; do
	case "$arg" in
	--no-rust) WITH_RUST=0 ;;
	--no-plugins) WITH_PLUGINS=0 ;;
	-h | --help)
		sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	*)
		echo "未知參數:$arg" >&2
		exit 1
		;;
	esac
done

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die() {
	printf '\033[1;31merror:\033[0m %s\n' "$*" >&2
	exit 1
}
have() { command -v "$1" >/dev/null 2>&1; }

# version_ge A B:A >= B
version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }

# 從 `--version` 輸出取第一個 x.y.z
first_version() { grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1; }

nvim_version() { have nvim && nvim --version | head -n1 | first_version || true; }
tree_sitter_version() { have tree-sitter && tree-sitter --version | first_version || true; }

BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
ORIG_PATH="$PATH"
export PATH="$BIN_DIR:$HOME/.cargo/bin:$PATH"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
	have sudo || die "需要 sudo 或 root 權限來安裝套件"
	SUDO="sudo"
fi

OS="$(uname -s)"
ARCH="$(uname -m)"
case "$ARCH" in
x86_64 | amd64) ARCH_NVIM="x86_64" ARCH_TS="x64" ARCH_LG="x86_64" ;;
aarch64 | arm64) ARCH_NVIM="arm64" ARCH_TS="arm64" ARCH_LG="arm64" ;;
*) die "不支援的 CPU 架構:$ARCH" ;;
esac

download() { curl -fsSL --retry 3 "$1" -o "$2"; }

# ---------------------------------------------------------------- Linux 用 --
install_nvim_linux() {
	local cur
	cur="$(nvim_version)"
	if [ -n "$cur" ] && version_ge "$cur" "$MIN_NVIM"; then
		log "neovim $cur 已符合 (>= $MIN_NVIM)"
		return
	fi
	log "安裝 neovim (官方 release,apt 版本通常太舊)"
	local tmp
	tmp="$(mktemp -d)"
	download "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${ARCH_NVIM}.tar.gz" "$tmp/nvim.tar.gz"
	rm -rf "$HOME/.local/nvim"
	mkdir -p "$HOME/.local/nvim"
	tar -xzf "$tmp/nvim.tar.gz" -C "$HOME/.local/nvim" --strip-components=1
	ln -sf "$HOME/.local/nvim/bin/nvim" "$BIN_DIR/nvim"
	rm -rf "$tmp"
}

install_tree_sitter_linux() {
	local cur
	cur="$(tree_sitter_version)"
	if [ -n "$cur" ] && version_ge "$cur" "$MIN_TREE_SITTER"; then
		log "tree-sitter $cur 已符合 (>= $MIN_TREE_SITTER)"
		return
	fi
	log "安裝 tree-sitter-cli (官方 release)"
	local tmp
	tmp="$(mktemp -d)"
	download "https://github.com/tree-sitter/tree-sitter/releases/latest/download/tree-sitter-linux-${ARCH_TS}.gz" "$tmp/ts.gz"
	gunzip -f "$tmp/ts.gz"
	install -m 755 "$tmp/ts" "$BIN_DIR/tree-sitter"
	rm -rf "$tmp"
}

# lazygit 是選用工具,失敗只警告 (呼叫端用 || 接住,所以每一步都要自己 return)
install_lazygit_linux() {
	if have lazygit; then
		log "lazygit 已安裝"
		return 0
	fi
	log "安裝 lazygit (官方 release)"
	local tag tmp
	tag="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/jesseduffield/lazygit/releases/latest)" || return 1
	tag="${tag##*/v}"
	[ -n "$tag" ] || return 1
	tmp="$(mktemp -d)"
	download "https://github.com/jesseduffield/lazygit/releases/download/v${tag}/lazygit_${tag}_Linux_${ARCH_LG}.tar.gz" "$tmp/lazygit.tar.gz" || return 1
	tar -xzf "$tmp/lazygit.tar.gz" -C "$tmp" lazygit || return 1
	install -m 755 "$tmp/lazygit" "$BIN_DIR/lazygit" || return 1
	rm -rf "$tmp"
}

install_linux() {
	have apt-get || die "目前只支援 apt (Debian/Ubuntu)。請依 lua/config/deps.lua 的清單手動安裝依賴。"
	log "apt 安裝基礎工具"
	$SUDO apt-get update
	$SUDO apt-get install -y git curl tar unzip gzip build-essential ripgrep fd-find nodejs npm
	install_nvim_linux
	install_tree_sitter_linux
	install_lazygit_linux || warn "lazygit 安裝失敗 (選用,<leader>gg 會用到),可稍後手動安裝"
}

# ---------------------------------------------------------------- macOS 用 --
install_macos() {
	xcode-select -p >/dev/null 2>&1 || {
		xcode-select --install || true
		die "請先完成 Xcode Command Line Tools 安裝 (提供 git / clang / make),再重新執行本腳本"
	}
	have brew || die "找不到 Homebrew,請先安裝:https://brew.sh"
	log "brew 安裝套件"
	brew install neovim ripgrep fd node lazygit tree-sitter-cli
	# 確認版本 (brew 偶爾落後於 nvim-treesitter 的要求)
	local cur
	cur="$(nvim_version)"
	[ -n "$cur" ] && version_ge "$cur" "$MIN_NVIM" || warn "neovim ${cur:-?} 低於 $MIN_NVIM,請執行 brew upgrade neovim"
}

# ------------------------------------------------------------------- Rust --
install_rust() {
	if [ "$WITH_RUST" -eq 0 ]; then
		log "略過 Rust 工具鏈 (--no-rust)"
		return
	fi
	if have rustup; then
		log "rustup 已安裝,補齊 rust-analyzer / clippy"
		rustup component add rust-analyzer clippy
	elif have cargo; then
		warn "找到 cargo 但沒有 rustup,請自行確認 rust-analyzer 與 clippy 可用"
	else
		log "安裝 Rust (rustup)"
		curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal -c rust-analyzer -c clippy
	fi
}

# ------------------------------------------------------------------- main --
case "$OS" in
Darwin) install_macos ;;
Linux) install_linux ;;
*) die "不支援的系統:$OS (Windows 請用 install.ps1)" ;;
esac
install_rust

# Ubuntu 22.04 等舊版 apt 的 nodejs 太舊,prettier 會裝不起來
if have node; then
	node_major="$(node --version | sed 's/^v//; s/\..*//')"
	if [ "$node_major" -lt "$MIN_NODE_MAJOR" ]; then
		warn "node $(node --version) 太舊 (需要 >= $MIN_NODE_MAJOR),請改用 https://nodejs.org 或 nvm / fnm 安裝新版"
	fi
fi

if ! printf '%s' "${ORIG_PATH:-}" | tr ':' '\n' | grep -qx "$BIN_DIR"; then
	warn "請確認 $BIN_DIR 在你的 PATH 內 (例如在 ~/.bashrc 或 ~/.zshrc 加上 export PATH=\"\$HOME/.local/bin:\$PATH\")"
fi

if [ "$WITH_PLUGINS" -eq 1 ]; then
	cfg="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
	here="$(cd "$(dirname "$0")" && pwd -P)"
	if [ "$(cd "$cfg" 2>/dev/null && pwd -P)" = "$here" ]; then
		log "安裝外掛 (Lazy! sync)"
		nvim --headless "+Lazy! sync" +qa
	else
		warn "此 repo 不在 $cfg,略過外掛安裝。請 clone/連結到該路徑後第一次開 nvim 即會自動安裝"
	fi
fi

log "完成。開啟 nvim 後執行 :Deps 可檢查所有依賴;Copilot 請執行 :Copilot auth"
