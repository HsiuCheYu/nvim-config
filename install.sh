#!/usr/bin/env bash
# 一次安裝這份 nvim 設定需要的所有東西 (macOS / Ubuntu / Debian),空環境即可使用。
# 可重複執行:neovim / tree-sitter-cli 每次都會升級到 Homebrew 的最新版,其餘工具已安裝就略過。
#
# 所有工具統一用 Homebrew (macOS / Linuxbrew) 安裝;沒有 brew 時會先用官方安裝程式裝好。
#   neovim, node, tree-sitter-cli, lazygit, ripgrep, fd
# 注意:舊版 macOS / 沒有預編譯 bottle 的平台,brew 會從原始碼編譯 (Rust / LLVM 可能要數小時)。
#
# 用法:./install.sh [--no-rust] [--no-font] [--no-plugins]
#   --no-rust     不安裝 Rust 工具鏈 (rustup / rust-analyzer / clippy)
#   --no-font     不安裝 Nerd Font (JetBrains Mono)
#   --no-plugins  不安裝外掛、treesitter parser 與 Mason 套件
#
# 依賴清單與 lua/config/deps.lua 保持一致;新增依賴時兩邊一起改。
# Windows 請使用 windows 分支的 install.ps1。
#
# 相容 macOS 內建的 bash 3.2:不要使用 mapfile、關聯陣列、${var,,} 等 bash 4 語法。

set -euo pipefail

MIN_NVIM="0.12.0"        # nvim-treesitter (main) 要求
MIN_TREE_SITTER="0.26.1" # nvim-treesitter (main) 要求,且不能用 npm 版
MIN_NODE_MAJOR=18        # Mason 用 npm 安裝 prettier / jsonls

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

nvim_version() { have nvim && nvim --version 2>/dev/null | head -n1 | first_version || true; }
tree_sitter_version() { have tree-sitter && tree-sitter --version 2>/dev/null | first_version || true; }

download() { curl -fsSL --retry 3 "$1" -o "$2"; }

UNAME_S="${UNAME_S:-$(uname -s)}" # 可由環境變數覆寫 (測試用)

# ------------------------------------------------------------ 平台:基礎套件 --
# Linuxbrew 與編譯 treesitter parser 需要:git curl build-essential procps file
install_base_linux() {
	have apt-get || die "目前只支援 apt (Debian/Ubuntu) 與 macOS。請依 lua/config/deps.lua 的清單手動安裝依賴。"
	local sudo=""
	if [ "$(id -u)" -ne 0 ]; then
		have sudo || die "需要 sudo 或 root 權限來安裝套件"
		sudo="sudo"
	fi
	log "apt 安裝基礎工具"
	$sudo apt-get update
	$sudo apt-get install -y ca-certificates git curl tar unzip gzip build-essential procps file fontconfig
}

install_base_macos() {
	log "macOS $(sw_vers -productVersion 2>/dev/null || echo '?')"
	if ! xcode-select -p >/dev/null 2>&1; then
		xcode-select --install >/dev/null 2>&1 || true
		die "缺少 Xcode Command Line Tools (提供 git / clang / make)。請在跳出的視窗完成安裝後,重新執行本腳本"
	fi
	have curl || die "找不到 curl"
}

# ---------------------------------------------------------------- Homebrew --

# 把已安裝在預設位置、但不在 PATH 的 brew 接上來 (shellenv 會把 brew 的 bin 放到 PATH 最前面)
load_brew() {
	local b
	for b in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew "$HOME/.linuxbrew/bin/brew"; do
		if [ -x "$b" ]; then
			eval "$("$b" shellenv)"
			return 0
		fi
	done
	return 1
}

BREW_ON_PATH=0 # 腳本開始時 brew 是否已經在 PATH 上 (是的話不用再寫入 shell 設定檔)

# 把 brew shellenv 寫進 shell 設定檔,讓之後新開的終端機也找得到 brew 裝的工具 (可重複執行,不會重複寫入)
persist_brew_shellenv() {
	[ "$BREW_ON_PATH" -eq 0 ] || return 0
	have brew || return 0
	local rc line
	case "$(basename "${SHELL:-}")" in
	zsh) if [ "$UNAME_S" = "Darwin" ]; then rc="$HOME/.zprofile"; else rc="$HOME/.zshrc"; fi ;;
	bash) if [ "$UNAME_S" = "Darwin" ]; then rc="$HOME/.bash_profile"; else rc="$HOME/.bashrc"; fi ;;
	*)
		warn "無法判斷 shell ($SHELL),請自行把 eval \"\$($(command -v brew) shellenv)\" 加進 shell 設定檔"
		return 0
		;;
	esac
	if [ -f "$rc" ] && grep -q 'brew shellenv' "$rc"; then
		log "$rc 已有 brew shellenv"
		return 0
	fi
	line="eval \"\$($(command -v brew) shellenv)\""
	printf '\n# Homebrew (由 nvim-config 的 install.sh 加入)\n%s\n' "$line" >>"$rc"
	log "已把 brew shellenv 寫入 $rc,請重新開啟終端機,或執行:source $rc"
}

setup_brew() {
	if have brew; then
		BREW_ON_PATH=1
	else
		load_brew || true
	fi
	if ! have brew; then
		# Homebrew 的安裝程式不允許用 root 執行
		[ "$(id -u)" -ne 0 ] || die "找不到 Homebrew,且不能用 root 安裝它。請改用一般使用者執行,或先自行安裝 brew"
		log "安裝 Homebrew (官方安裝程式)"
		NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" ||
			die "Homebrew 安裝失敗"
		load_brew || die "Homebrew 已安裝,但找不到 brew 執行檔"
	fi
	export HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_INSTALL_CLEANUP=1
	log "$(brew --version | head -n1) ($(brew --prefix))"
	brew update --quiet || warn "brew update 失敗,使用現有的 formula 資訊"
	export HOMEBREW_NO_AUTO_UPDATE=1
}

# 安裝 formula;已安裝時,第二個參數是 upgrade 才升級
brew_ensure() { # $1 = formula  $2 = "upgrade" (選填)
	if brew list --formula "$1" >/dev/null 2>&1; then
		if [ "${2:-}" = "upgrade" ]; then
			log "brew upgrade $1"
			brew upgrade --formula "$1" || warn "brew upgrade $1 失敗,沿用現有版本"
		else
			log "$1 已安裝"
		fi
	else
		log "brew install $1"
		brew install --formula "$1"
	fi
}

# 實際會被執行的 $1 是不是 brew 裝的那份?不是的話 (例如舊版腳本放在 ~/.local/bin 的檔案) 提醒使用者
check_shadow() { # $1 = 執行檔名
	local path prefix
	path="$(command -v "$1" 2>/dev/null)" || return 0
	prefix="$(brew --prefix)"
	case "$path" in
	"$prefix"/*) ;;
	*) warn "$1 解析到 $path,不是 Homebrew 的版本。請移除它,或讓 $prefix/bin 排在 PATH 前面" ;;
	esac
}

ensure_tools() {
	local cur
	brew_ensure neovim upgrade
	brew_ensure node
	brew_ensure tree-sitter-cli upgrade
	brew_ensure lazygit
	brew_ensure ripgrep
	brew_ensure fd

	cur="$(nvim_version)"
	log "neovim $cur"
	version_ge "${cur:-0}" "$MIN_NVIM" ||
		warn "neovim $cur 低於 nvim-treesitter (main) 要求的 $MIN_NVIM,語法高亮 / parser 可能無法使用"
	cur="$(tree_sitter_version)"
	log "tree-sitter ${cur:-?}"
	version_ge "${cur:-0}" "$MIN_TREE_SITTER" ||
		warn "tree-sitter ${cur:-?} 低於要求的 $MIN_TREE_SITTER,treesitter parser 可能無法安裝"
	have node && [ "$(node --version | sed 's/^v//; s/\..*//')" -ge "$MIN_NODE_MAJOR" ] ||
		warn "node 版本低於 $MIN_NODE_MAJOR,Mason 無法安裝 prettier / jsonls"

	local t
	for t in nvim node npm tree-sitter lazygit rg fd; do
		check_shadow "$t"
	done
}

install_font() {
	[ "$WITH_FONT" -eq 1 ] || return 0
	local dir fonts tmp
	if [ "$UNAME_S" = "Darwin" ]; then
		dir="$HOME/Library/Fonts"
		if ls "$dir" 2>/dev/null | grep -qi "JetBrainsMono.*Nerd"; then
			log "Nerd Font 已安裝"
			return 0
		fi
	else
		dir="$HOME/.local/share/fonts/JetBrainsMonoNerdFont"
		# 注意:pipefail 下 `fc-list | grep -q` 會因 SIGPIPE 誤判,所以先存成變數
		fonts="$(fc-list 2>/dev/null || true)"
		if grep -qi "JetBrainsMono Nerd" <<<"$fonts"; then
			log "Nerd Font 已安裝"
			return 0
		fi
	fi
	log "安裝 JetBrains Mono Nerd Font"
	tmp="$(mktemp -d)"
	{
		download "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip" "$tmp/font.zip" &&
			mkdir -p "$dir" && unzip -oq "$tmp/font.zip" -d "$dir"
	} || {
		rm -rf "$tmp"
		warn "Nerd Font 安裝失敗 (選用),可稍後手動安裝"
		return 0
	}
	rm -rf "$tmp"
	if [ "$UNAME_S" = "Linux" ]; then
		fc-cache -f "$dir" >/dev/null 2>&1 || true
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
main() {
	WITH_RUST=1
	WITH_FONT=1
	WITH_PLUGINS=1
	local arg
	for arg in "$@"; do
		case "$arg" in
		--no-rust) WITH_RUST=0 ;;
		--no-font) WITH_FONT=0 ;;
		--no-plugins) WITH_PLUGINS=0 ;;
		-h | --help)
			sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
			exit 0
			;;
		*)
			echo "未知參數:$arg" >&2
			exit 1
			;;
		esac
	done

	case "$UNAME_S" in
	Linux) install_base_linux ;;
	Darwin) install_base_macos ;;
	*) die "不支援的系統:$UNAME_S (Windows 請使用 windows 分支的 install.ps1)" ;;
	esac

	setup_brew
	persist_brew_shellenv
	export PATH="$HOME/.cargo/bin:$PATH"
	ensure_tools
	install_font
	install_rust || warn "Rust 工具鏈安裝失敗 (選用,Rust 專案才會用到),可稍後重新執行本腳本"
	setup_nvim

	if [ "$WITH_FONT" -eq 1 ]; then
		log "提醒:請在終端機設定使用 \"JetBrainsMono Nerd Font\",否則圖示會顯示成方框"
	fi
	log "完成。請重新開啟終端機 (或 source 上面提到的 shell 設定檔),讓 PATH 生效"
	log "開啟 nvim 後執行 :Deps 可檢查所有依賴;Copilot 請執行 :Copilot auth"
}

# 被 source 時 (測試) 只載入函式,不執行
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	main "$@"
fi
