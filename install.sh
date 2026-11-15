#!/usr/bin/env bash
# 一次安裝這份 nvim 設定需要的所有東西 (macOS / Ubuntu / Debian),空環境即可使用。
# 可重複執行:每次都會把 neovim 更新到最新穩定版,其餘工具已符合版本就略過。
#
# 用法:./install.sh [--no-rust] [--no-font] [--no-plugins]
#   --no-rust     不安裝 Rust 工具鏈 (rustup / rust-analyzer / clippy)
#   --no-font     不安裝 Nerd Font (JetBrains Mono)
#   --no-plugins  不安裝外掛、treesitter parser 與 Mason 套件
#
# 依賴清單與 lua/config/deps.lua 保持一致;新增依賴時兩邊一起改。
# Windows 請使用 windows 分支的 install.ps1。

set -euo pipefail

MIN_NVIM="0.12.0"        # nvim-treesitter (main) 要求
MIN_TREE_SITTER="0.26.1" # nvim-treesitter (main) 要求,且不能用 npm 版
MIN_NODE_MAJOR=18        # Mason 用 npm 安裝 prettier / jsonls

WITH_RUST=1
WITH_FONT=1
WITH_PLUGINS=1
for arg in "$@"; do
	case "$arg" in
	--no-rust) WITH_RUST=0 ;;
	--no-font) WITH_FONT=0 ;;
	--no-plugins) WITH_PLUGINS=0 ;;
	-h | --help)
		sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
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

# GitHub「最新 release」的版本號 (例如 v0.12.6)。
# 不抓網頁,直接看 releases/latest/download/<asset> 的第一層轉址,與下載走同一條路。
github_latest_tag() { # $1 = owner/repo  $2 = 任一個 release asset 檔名
	local loc
	loc="$(curl -fsSI "https://github.com/$1/releases/latest/download/$2" | tr -d '\r' | grep -i '^location:' | head -n1)" || return 1
	printf '%s' "$loc" | sed -n 's#.*/releases/download/\([^/]*\)/.*#\1#p'
}

download() { curl -fsSL --retry 3 "$1" -o "$2"; }

BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
ORIG_PATH="$PATH"
export PATH="$BIN_DIR:$HOME/.cargo/bin:$PATH"

OS="$(uname -s)"
ARCH="$(uname -m)"
case "$ARCH" in
x86_64 | amd64) ARCH_NVIM="x86_64" ARCH_NODE="x64" ARCH_LG="x86_64" ;;
aarch64 | arm64) ARCH_NVIM="arm64" ARCH_NODE="arm64" ARCH_LG="arm64" ;;
*) die "不支援的 CPU 架構:$ARCH" ;;
esac

# ------------------------------------------------------- Linux (apt) 專用 --
install_nvim_linux() {
	local latest cur
	cur="$(nvim_version)"
	latest="$(github_latest_tag neovim/neovim "nvim-linux-${ARCH_NVIM}.tar.gz" || true)"
	if [ -z "$latest" ]; then
		# 查不到最新版 (離線 / API 限制):已經符合最低版本就先用現有的
		if [ -n "$cur" ] && version_ge "$cur" "$MIN_NVIM"; then
			warn "無法查詢 neovim 最新版本,沿用現有的 $cur"
			return 0
		fi
		latest="latest"
	elif [ "v$cur" = "$latest" ]; then
		log "neovim $cur 已是最新版"
		return 0
	fi
	log "安裝 neovim ${latest} (官方 release,apt 版本通常太舊)"
	local tmp
	tmp="$(mktemp -d)"
	download "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${ARCH_NVIM}.tar.gz" "$tmp/nvim.tar.gz"
	rm -rf "$HOME/.local/nvim"
	mkdir -p "$HOME/.local/nvim"
	tar -xzf "$tmp/nvim.tar.gz" -C "$HOME/.local/nvim" --strip-components=1
	ln -sf "$HOME/.local/nvim/bin/nvim" "$BIN_DIR/nvim"
	rm -rf "$tmp"
	# 系統另有舊版 (例如 apt 的 neovim) 排在 PATH 前面時,提醒使用者
	if [ "$(command -v nvim)" != "$BIN_DIR/nvim" ]; then
		warn "PATH 中另有 nvim:$(command -v nvim)。請移除它 (sudo apt remove neovim),或讓 $BIN_DIR 排在 PATH 前面"
	fi
}

# apt 的 nodejs 太舊 (Ubuntu 22.04 只有 12),所以直接裝 nodejs.org 的 LTS,免 sudo
install_node_linux() {
	if have node && have npm && [ "$(node --version | sed 's/^v//; s/\..*//')" -ge "$MIN_NODE_MAJOR" ]; then
		log "node $(node --version) 已符合 (>= $MIN_NODE_MAJOR)"
		return 0
	fi
	log "安裝 Node.js LTS (nodejs.org)"
	local idx ver tmp
	idx="$(curl -fsSL --retry 3 https://nodejs.org/dist/index.json)"
	ver="$(printf '%s' "$idx" | tr '}' '\n' | grep '"lts":"' | sed -n 's/.*"version":"\(v[0-9.]*\)".*/\1/p')"
	ver="${ver%%$'\n'*}"
	[ -n "$ver" ] || die "無法取得 Node.js LTS 版本"
	tmp="$(mktemp -d)"
	download "https://nodejs.org/dist/${ver}/node-${ver}-linux-${ARCH_NODE}.tar.gz" "$tmp/node.tar.gz"
	rm -rf "$HOME/.local/node"
	mkdir -p "$HOME/.local/node"
	tar -xzf "$tmp/node.tar.gz" -C "$HOME/.local/node" --strip-components=1
	for b in node npm npx; do ln -sf "$HOME/.local/node/bin/$b" "$BIN_DIR/$b"; done
	rm -rf "$tmp"
}

install_tree_sitter_linux() {
	local cur
	cur="$(tree_sitter_version)"
	if [ -n "$cur" ] && version_ge "$cur" "$MIN_TREE_SITTER"; then
		log "tree-sitter $cur 已符合 (>= $MIN_TREE_SITTER)"
		return 0
	fi
	log "安裝 tree-sitter-cli (官方 release)"
	local tmp
	tmp="$(mktemp -d)"
	download "https://github.com/tree-sitter/tree-sitter/releases/latest/download/tree-sitter-linux-${ARCH_NODE}.gz" "$tmp/ts.gz"
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

install_font_linux() {
	# 注意:pipefail 下 `fc-list | grep -q` 會因 SIGPIPE 誤判,所以先存成變數
	local fonts
	fonts="$(fc-list 2>/dev/null || true)"
	if grep -qi "JetBrainsMono Nerd" <<<"$fonts"; then
		log "Nerd Font 已安裝"
		return 0
	fi
	log "安裝 JetBrains Mono Nerd Font"
	local dir="$HOME/.local/share/fonts/JetBrainsMonoNerdFont" tmp
	tmp="$(mktemp -d)"
	download "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip" "$tmp/font.zip" || return 1
	mkdir -p "$dir"
	unzip -oq "$tmp/font.zip" -d "$dir" || return 1
	fc-cache -f "$dir" >/dev/null 2>&1 || true
	rm -rf "$tmp"
}

install_linux() {
	have apt-get || die "目前只支援 apt (Debian/Ubuntu) 與 macOS。請依 lua/config/deps.lua 的清單手動安裝依賴。"
	local sudo=""
	if [ "$(id -u)" -ne 0 ]; then
		have sudo || die "需要 sudo 或 root 權限來安裝套件"
		sudo="sudo"
	fi
	log "apt 安裝基礎工具"
	$sudo apt-get update
	$sudo apt-get install -y ca-certificates git curl tar unzip gzip build-essential ripgrep fd-find fontconfig
	install_nvim_linux
	install_node_linux
	install_tree_sitter_linux
	install_lazygit_linux || warn "lazygit 安裝失敗 (選用,<leader>gg 會用到),可稍後手動安裝"
	if [ "$WITH_FONT" -eq 1 ]; then
		install_font_linux || warn "Nerd Font 安裝失敗 (選用),可稍後手動安裝"
	fi
}

# ------------------------------------------------------------ macOS 專用 --
install_macos() {
	if ! have brew; then
		log "安裝 Homebrew (會一併安裝 Xcode Command Line Tools,需要輸入密碼)"
		NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
		for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
			[ -x "$b" ] && eval "$("$b" shellenv)" && break
		done
		have brew || die "Homebrew 安裝後仍找不到 brew,請重開終端機再執行本腳本"
	fi
	xcode-select -p >/dev/null 2>&1 || die "缺少 Xcode Command Line Tools (提供 git / clang / make),請執行 xcode-select --install 後再重跑"

	log "brew 安裝套件"
	brew install neovim ripgrep fd node lazygit tree-sitter-cli
	log "更新 neovim 到最新版"
	brew upgrade neovim || true
	if [ "$WITH_FONT" -eq 1 ]; then
		log "安裝 JetBrains Mono Nerd Font"
		brew install --cask font-jetbrains-mono-nerd-font || warn "Nerd Font 安裝失敗 (選用),可稍後手動安裝"
	fi
}

# ------------------------------------------------------------------- Rust --
# 選用工具:失敗只警告,不影響後面的外掛安裝 (呼叫端用 || 接住,所以每一步都要自己 return)
install_rust() {
	if [ "$WITH_RUST" -eq 0 ]; then
		log "略過 Rust 工具鏈 (--no-rust)"
		return 0
	fi
	if have rustup; then
		log "rustup 已安裝,補齊 rust-analyzer / clippy"
		rustup component add rust-analyzer clippy || return 1
	elif have cargo; then
		warn "找到 cargo 但沒有 rustup,請自行確認 rust-analyzer 與 clippy 可用"
	else
		log "安裝 Rust (rustup)"
		local tmp
		tmp="$(mktemp -d)"
		curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs -o "$tmp/rustup-init.sh" || return 1
		sh "$tmp/rustup-init.sh" -y --profile minimal -c rust-analyzer -c clippy || return 1
		rm -rf "$tmp"
	fi
}

# --------------------------------------- 外掛 / parser / Mason 套件 (headless) --
setup_nvim() {
	if [ "$WITH_PLUGINS" -eq 0 ]; then
		log "略過外掛安裝 (--no-plugins)"
		return 0
	fi
	local cfg here
	cfg="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
	here="$(cd "$(dirname "$0")" && pwd -P)"
	if [ ! -e "$cfg" ]; then
		log "連結設定:$cfg -> $here"
		mkdir -p "$(dirname "$cfg")"
		ln -s "$here" "$cfg"
	elif [ "$(cd "$cfg" 2>/dev/null && pwd -P)" != "$here" ]; then
		warn "$cfg 已存在且不是這個 repo,略過外掛安裝。請自行處理後再執行 nvim"
		return 0
	fi
	log "安裝外掛 (Lazy! sync)"
	nvim --headless "+Lazy! sync" +qa
	log "安裝 treesitter parser 與 Mason 套件 (可能需要幾分鐘)"
	nvim --headless "+lua require('config.bootstrap').run()" +qa
}

# ------------------------------------------------------------------- main --
case "$OS" in
Darwin) install_macos ;;
Linux) install_linux ;;
*) die "不支援的系統:$OS (Windows 請使用 windows 分支的 install.ps1)" ;;
esac
install_rust || warn "Rust 工具鏈安裝失敗 (選用,Rust 專案才會用到),可稍後重新執行本腳本"
setup_nvim

if ! grep -qx "$BIN_DIR" <<<"${ORIG_PATH//:/$'\n'}"; then
	warn "請確認 $BIN_DIR 在你的 PATH 內 (例如在 ~/.bashrc 或 ~/.zshrc 加上 export PATH=\"\$HOME/.local/bin:\$PATH\")"
fi
if [ "$WITH_FONT" -eq 1 ]; then
	log "提醒:請在終端機設定使用 \"JetBrainsMono Nerd Font\",否則圖示會顯示成方框"
fi
log "完成。開啟 nvim 後執行 :Deps 可檢查所有依賴;Copilot 請執行 :Copilot auth"
