#!/usr/bin/env bash
# 一次安裝這份 nvim 設定需要的所有東西 (macOS / Ubuntu / Debian),空環境即可使用。
# 可重複執行:每次都會把 neovim 更新到最新穩定版,其餘工具已符合版本就略過。
#
# 版本原則:一律先裝「最新版」,裝完實際執行確認能跑;只有跑不起來
# (例如舊版 macOS 跑不了新版 Node) 才退一版再試,直到找到能跑的最新版。
# Homebrew:macOS 上「已安裝 brew」且「要裝的 formula 與其依賴都有適用此系統的預編譯 bottle」
# 才使用;只要有一個沒有 bottle (舊版 macOS,brew 會從原始碼編譯 Rust / LLVM 數小時) 就整個改用
# 官方預編譯檔。Linux 一律走 apt + 官方預編譯檔。
#
# 用法:./install.sh [--no-rust] [--no-font] [--no-plugins] [--no-brew]
#   --no-rust     不安裝 Rust 工具鏈 (rustup / rust-analyzer / clippy)
#   --no-brew     macOS 上不使用 Homebrew,一律下載官方預編譯檔
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
MAX_TRIES=8              # 找不到能跑的版本時,最多往回試幾個版本

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

BIN_DIR="$HOME/.local/bin"
UNAME_S="${UNAME_S:-$(uname -s)}" # 可由環境變數覆寫 (測試用)
UNAME_M="${UNAME_M:-$(uname -m)}"

# 平台對應的 release 檔名 / 代號
detect_platform() {
	case "$UNAME_S-$UNAME_M" in
	Linux-x86_64 | Linux-amd64)
		NVIM_ASSET="nvim-linux-x86_64.tar.gz" TS_ASSET="tree-sitter-linux-x64.gz"
		NODE_PLAT="linux-x64" LG_PLAT="Linux_x86_64"
		;;
	Linux-aarch64 | Linux-arm64)
		NVIM_ASSET="nvim-linux-arm64.tar.gz" TS_ASSET="tree-sitter-linux-arm64.gz"
		NODE_PLAT="linux-arm64" LG_PLAT="Linux_arm64"
		;;
	Darwin-arm64)
		NVIM_ASSET="nvim-macos-arm64.tar.gz" TS_ASSET="tree-sitter-macos-arm64.gz"
		NODE_PLAT="darwin-arm64" LG_PLAT="Darwin_arm64" RUST_TRIPLE="aarch64-apple-darwin"
		;;
	Darwin-x86_64)
		NVIM_ASSET="nvim-macos-x86_64.tar.gz" TS_ASSET="tree-sitter-macos-x64.gz"
		NODE_PLAT="darwin-x64" LG_PLAT="Darwin_x86_64" RUST_TRIPLE="x86_64-apple-darwin"
		;;
	*) die "不支援的系統 / CPU:$UNAME_S $UNAME_M (Windows 請使用 windows 分支的 install.ps1)" ;;
	esac
}

# ---------------------------------------------------------- 版本探索 / 安裝 --

# GitHub 某個 repo 的穩定版 tag,新到舊,一行一個。
# 順序:API (有完整清單) → releases/latest/download/<asset> 的轉址 → releases/latest 頁面轉址 (只有最新一個)
release_tags() { # $1 = owner/repo  $2 = 任一個 release asset 檔名 (選填)
	local out
	out="$(curl -fsSL --retry 2 "https://api.github.com/repos/$1/releases?per_page=30" 2>/dev/null |
		grep -o '"tag_name": *"[^"]*"' | sed 's/.*: *"\(.*\)"/\1/' |
		grep -E '^v?[0-9]+\.[0-9]+(\.[0-9]+)?$' | sort -Vr)" || true
	if [ -z "$out" ] && [ -n "${2:-}" ]; then
		out="$(curl -fsSI "https://github.com/$1/releases/latest/download/$2" 2>/dev/null | tr -d '\r' |
			sed -n 's#^[Ll]ocation: .*/releases/download/\([^/]*\)/.*#\1#p' | head -n1)" || true
	fi
	if [ -z "$out" ]; then
		out="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" 2>/dev/null |
			sed -n 's#.*/releases/tag/\(.*\)#\1#p')" || true
	fi
	printf '%s\n' "$out"
}

# Node.js 各個 LTS 主版本的最新版,新到舊 (例如 v26.x, v24.x, v22.x ...)
node_versions() {
	local idx
	idx="$(curl -fsSL --retry 3 https://nodejs.org/dist/index.json)" || return 1
	printf '%s' "$idx" | tr '}' '\n' | grep '"lts":"' |
		sed -n 's/.*"version":"\(v[0-9.]*\)".*/\1/p' | awk -F. '!seen[$1]++'
}

# Mach-O 檔頭記載的「最低 macOS 版本」(只用於 macOS,需要 otool)
macho_minos() {
	otool -l "$1" 2>/dev/null | awk '
		/cmd LC_BUILD_VERSION/ { b = 1 }
		b && /minos/ { print $2; exit }
		/cmd LC_VERSION_MIN_MACOSX/ { m = 1 }
		m && /^ *version / { print $2; exit }'
}

# 這個指令真的能在這個系統上跑嗎? (依 PATH 解析;$BIN_DIR 排在 PATH 最前面,所以優先檢查我們裝的那份)
#   1. 能執行 --version
#   2. macOS:檔頭的最低系統版本 <= 目前系統版本
#      (macOS 不一定會在啟動時拒絕需求較新的程式,可能 --version 成功、用到新 API 才當掉)
can_run() { # $1 = 指令名稱
	local path minos mac
	hash -r
	path="$(command -v "$1" 2>/dev/null)" || return 1
	"$path" --version >/dev/null 2>&1 || return 1
	if [ "$UNAME_S" = "Darwin" ] && have otool; then
		minos="$(macho_minos "$path")"
		mac="$(sw_vers -productVersion 2>/dev/null || true)"
		if [ -n "$minos" ] && [ -n "$mac" ] && ! version_ge "$mac" "$minos"; then
			return 1
		fi
	fi
	return 0
}

# 從 stdin 讀版本 (新到舊),依序「安裝 → 確認能在此系統執行」,裝到第一個能跑的版本為止。
#   $1 = 執行檔名稱  $2 = 安裝函式 (收一個版本參數)
# 只有最新版跑不起來才會退版,並明確告知。
try_install() {
	local bin="$1" fetch="$2" tag n=0 first=1
	while read -r tag; do
		[ -n "$tag" ] || continue
		n=$((n + 1))
		[ "$n" -le "$MAX_TRIES" ] || break
		if "$fetch" "$tag" >/dev/null 2>&1 && can_run "$bin"; then
			if [ "$first" -eq 0 ]; then
				warn "$bin 的較新版本無法在此系統執行,已改用能執行的最新版 $tag"
			fi
			return 0
		fi
		first=0
	done
	return 1
}

# ---- 各工具的「安裝指定版本」函式 (成功回傳 0;每一步都自己 return,因為會被 if 呼叫) ----

fetch_nvim() { # $1 = tag (例如 v0.12.6)
	local tmp rc=0
	tmp="$(mktemp -d)"
	{
		download "https://github.com/neovim/neovim/releases/download/$1/$NVIM_ASSET" "$tmp/nvim.tar.gz" &&
			rm -rf "$HOME/.local/nvim" && mkdir -p "$HOME/.local/nvim" &&
			tar -xzf "$tmp/nvim.tar.gz" -C "$HOME/.local/nvim" --strip-components=1 &&
			ln -sf "$HOME/.local/nvim/bin/nvim" "$BIN_DIR/nvim"
	} || rc=1
	rm -rf "$tmp"
	return $rc
}

fetch_tree_sitter() { # $1 = tag
	local tmp rc=0
	tmp="$(mktemp -d)"
	{
		download "https://github.com/tree-sitter/tree-sitter/releases/download/$1/$TS_ASSET" "$tmp/ts.gz" &&
			gunzip -f "$tmp/ts.gz" && install -m 755 "$tmp/ts" "$BIN_DIR/tree-sitter"
	} || rc=1
	rm -rf "$tmp"
	return $rc
}

fetch_lazygit() { # $1 = tag (例如 v0.44.1)
	local tmp rc=0 ver="${1#v}"
	tmp="$(mktemp -d)"
	{
		download "https://github.com/jesseduffield/lazygit/releases/download/$1/lazygit_${ver}_${LG_PLAT}.tar.gz" "$tmp/lg.tar.gz" &&
			tar -xzf "$tmp/lg.tar.gz" -C "$tmp" lazygit && install -m 755 "$tmp/lazygit" "$BIN_DIR/lazygit"
	} || rc=1
	rm -rf "$tmp"
	return $rc
}

fetch_ripgrep() { # $1 = tag (例如 14.1.1,沒有 v)
	local tmp rc=0
	tmp="$(mktemp -d)"
	{
		download "https://github.com/BurntSushi/ripgrep/releases/download/$1/ripgrep-$1-${RUST_TRIPLE}.tar.gz" "$tmp/rg.tar.gz" &&
			tar -xzf "$tmp/rg.tar.gz" -C "$tmp" --strip-components=1 && install -m 755 "$tmp/rg" "$BIN_DIR/rg"
	} || rc=1
	rm -rf "$tmp"
	return $rc
}

fetch_fd() { # $1 = tag (例如 v10.2.0)
	local tmp rc=0
	tmp="$(mktemp -d)"
	{
		download "https://github.com/sharkdp/fd/releases/download/$1/fd-$1-${RUST_TRIPLE}.tar.gz" "$tmp/fd.tar.gz" &&
			tar -xzf "$tmp/fd.tar.gz" -C "$tmp" --strip-components=1 && install -m 755 "$tmp/fd" "$BIN_DIR/fd"
	} || rc=1
	rm -rf "$tmp"
	return $rc
}

fetch_node() { # $1 = 版本 (例如 v22.23.5)
	local tmp rc=0 b
	tmp="$(mktemp -d)"
	{
		download "https://nodejs.org/dist/$1/node-$1-${NODE_PLAT}.tar.gz" "$tmp/node.tar.gz" &&
			rm -rf "$HOME/.local/node" && mkdir -p "$HOME/.local/node" &&
			tar -xzf "$tmp/node.tar.gz" -C "$HOME/.local/node" --strip-components=1 &&
			for b in node npm npx; do ln -sf "$HOME/.local/node/bin/$b" "$BIN_DIR/$b"; done
	} || rc=1
	rm -rf "$tmp"
	return $rc
}

# ---- Homebrew (只在 macOS、且保證不會從原始碼編譯時使用) ----

# 目前 macOS 對應的 bottle 標籤 (例如 arm64_sonoma / sonoma);不認得的版本回傳失敗
brew_bottle_tag() {
	local v major minor arch="" name
	v="$(sw_vers -productVersion 2>/dev/null)" || return 1
	major="${v%%.*}"
	minor="${v#*.}"
	minor="${minor%%.*}"
	case "$major" in
	26) name="tahoe" ;;
	15) name="sequoia" ;;
	14) name="sonoma" ;;
	13) name="ventura" ;;
	12) name="monterey" ;;
	11) name="big_sur" ;;
	10)
		case "$minor" in
		15) name="catalina" ;;
		14) name="mojave" ;;
		*) return 1 ;;
		esac
		;;
	*) return 1 ;;
	esac
	[ "$UNAME_M" = "arm64" ] && arch="arm64_"
	printf '%s%s\n' "$arch" "$name"
}

# formula 有適用此系統的 bottle 嗎? (用 brew info 的 JSON;"all" 代表與系統無關的通用 bottle)
brew_has_bottle() { # $1 = formula  $2 = bottle 標籤
	local json
	# 先存成變數:pipefail 下 `brew info | grep -q` 會因 SIGPIPE 誤判
	json="$(brew info --json=v2 --formula "$1" 2>/dev/null)" || return 1
	grep -Eq "\"($2|all)\": *\{" <<<"$json"
}

# formula 與它的執行期依賴,是否都有 bottle (已安裝的依賴不需要再裝,略過)
brew_all_bottled() { # $1 = formula
	local tag f
	tag="$(brew_bottle_tag)" || return 1
	for f in "$1" $(brew deps --formula "$1" 2>/dev/null); do
		if [ "$f" != "$1" ] && brew list --formula "$f" >/dev/null 2>&1; then
			continue
		fi
		brew_has_bottle "$f" "$tag" || {
			warn "Homebrew 的 $f 沒有適用此系統 ($tag) 的預編譯檔,不使用 brew 安裝 $1"
			return 1
		}
	done
}

# 用 Homebrew 安裝 (已安裝則升級) 並確認能執行,成功回傳 0;任何一步不行就回傳 1,讓呼叫端改用官方預編譯檔。
#   $1 = 執行檔名  $2 = formula  其餘 = 一併移除的、先前由本腳本放進 $BIN_DIR 的連結 (例如 node 的 npm npx)
try_brew() {
	[ "$USE_BREW" -eq 1 ] || return 1
	local bin="$1" formula="$2" l
	shift 2
	brew_all_bottled "$formula" || return 1
	log "使用 Homebrew 安裝 $formula"
	if brew list --formula "$formula" >/dev/null 2>&1; then
		brew upgrade --formula "$formula" >/dev/null 2>&1 || true
	else
		brew install --formula "$formula" || return 1
	fi
	# $BIN_DIR 在 PATH 最前面,先前裝的官方預編譯檔會蓋掉 brew 的版本,所以移除
	rm -f "$BIN_DIR/$bin"
	for l in "$@"; do rm -f "$BIN_DIR/$l"; done
	can_run "$bin" || {
		warn "Homebrew 安裝的 $bin 無法在此系統執行,改用官方預編譯檔"
		return 1
	}
}

# ---- 各工具的「確保已安裝」函式 ----

ensure_nvim() {
	local cur latest
	cur="$(nvim_version)"
	latest="$(release_tags neovim/neovim "$NVIM_ASSET")"
	latest="${latest%%$'\n'*}"
	if [ -z "$latest" ]; then
		# 查不到最新版 (離線 / 被限流):已經符合最低版本就先用現有的
		if [ -n "$cur" ] && version_ge "$cur" "$MIN_NVIM"; then
			warn "無法查詢 neovim 最新版本,沿用現有的 $cur"
			return 0
		fi
		die "無法查詢 neovim 最新版本,請檢查網路"
	fi
	if [ "v$cur" = "$latest" ] && can_run nvim; then
		log "neovim $cur 已是最新版"
		return 0
	fi
	if try_brew nvim neovim; then
		cur="$(nvim_version)"
		if version_ge "$cur" "$MIN_NVIM"; then
			log "neovim $cur (Homebrew)"
			return 0
		fi
	fi
	log "安裝 neovim (最新:$latest)"
	release_tags neovim/neovim "$NVIM_ASSET" | try_install nvim fetch_nvim ||
		die "找不到能在這個系統執行的 neovim 版本"
	cur="$(nvim_version)"
	log "neovim $cur"
	if ! version_ge "$cur" "$MIN_NVIM"; then
		warn "這個系統只能執行 neovim $cur,低於 nvim-treesitter (main) 要求的 $MIN_NVIM,語法高亮 / parser 可能無法使用。建議升級作業系統"
	fi
	# 系統另有舊版 (例如 apt 的 neovim) 排在 PATH 前面時,提醒使用者
	if [ "$(command -v nvim)" != "$BIN_DIR/nvim" ]; then
		warn "PATH 中另有 nvim:$(command -v nvim)。請移除它 (例如 sudo apt remove neovim),或讓 $BIN_DIR 排在 PATH 前面"
	fi
}

ensure_node() {
	if have node && have npm && [ "$(node --version | sed 's/^v//; s/\..*//')" -ge "$MIN_NODE_MAJOR" ]; then
		log "node $(node --version) 已符合 (>= $MIN_NODE_MAJOR)"
		return 0
	fi
	if try_brew node node npm npx && have npm; then
		log "node $(node --version) (Homebrew)"
		return 0
	fi
	log "安裝 Node.js LTS (nodejs.org)"
	node_versions | try_install node fetch_node || die "找不到能在這個系統執行的 Node.js 版本"
	log "node $("$BIN_DIR/node" --version)"
}

ensure_tree_sitter() {
	local cur
	cur="$(tree_sitter_version)"
	if [ -n "$cur" ] && version_ge "$cur" "$MIN_TREE_SITTER"; then
		log "tree-sitter $cur 已符合 (>= $MIN_TREE_SITTER)"
		return 0
	fi
	if try_brew tree-sitter tree-sitter-cli; then
		cur="$(tree_sitter_version)"
		if version_ge "$cur" "$MIN_TREE_SITTER"; then
			log "tree-sitter $cur (Homebrew)"
			return 0
		fi
	fi
	log "安裝 tree-sitter-cli (官方 release)"
	release_tags tree-sitter/tree-sitter "$TS_ASSET" | try_install tree-sitter fetch_tree_sitter ||
		die "找不到能在這個系統執行的 tree-sitter-cli"
	cur="$(tree_sitter_version)"
	version_ge "$cur" "$MIN_TREE_SITTER" ||
		warn "這個系統只能執行 tree-sitter $cur,低於要求的 $MIN_TREE_SITTER,treesitter parser 可能無法安裝"
}

# 選用工具:失敗只警告
ensure_optional() { # $1 = 執行檔名  $2 = repo  $3 = 安裝函式  $4 = 顯示名稱  $5 = brew formula (選填)
	if can_run "$1"; then
		log "$4 已安裝"
		return 0
	fi
	if [ -n "${5:-}" ] && try_brew "$1" "$5"; then
		log "$4 (Homebrew)"
		return 0
	fi
	log "安裝 $4"
	release_tags "$2" | try_install "$1" "$3" || warn "$4 找不到可用的預編譯版本 (網路問題,或所有版本都不支援此系統)"
}

# ------------------------------------------------------- 平台專屬:基礎套件 --
install_base_linux() {
	have apt-get || die "目前只支援 apt (Debian/Ubuntu) 與 macOS。請依 lua/config/deps.lua 的清單手動安裝依賴。"
	local sudo=""
	if [ "$(id -u)" -ne 0 ]; then
		have sudo || die "需要 sudo 或 root 權限來安裝套件"
		sudo="sudo"
	fi
	log "apt 安裝基礎工具"
	$sudo apt-get update
	$sudo apt-get install -y ca-certificates git curl tar unzip gzip build-essential ripgrep fd-find fontconfig
}

install_base_macos() {
	local ver
	ver="$(sw_vers -productVersion 2>/dev/null || true)"
	log "macOS ${ver:-?}"
	if ! xcode-select -p >/dev/null 2>&1; then
		xcode-select --install >/dev/null 2>&1 || true
		die "缺少 Xcode Command Line Tools (提供 git / clang / make)。請在跳出的視窗完成安裝後,重新執行本腳本"
	fi
	have curl || die "找不到 curl"
	setup_brew
}

# 決定要不要用 Homebrew (結果存在 USE_BREW)。需要:沒有 --no-brew、已安裝 brew、認得此 macOS 版本的 bottle 標籤。
setup_brew() {
	USE_BREW=0
	if [ "$WITH_BREW" -eq 0 ]; then
		log "不使用 Homebrew (--no-brew),直接下載官方預編譯檔"
		return 0
	fi
	if ! have brew; then
		local b
		for b in /opt/homebrew/bin /usr/local/bin; do
			# 加在 PATH 最後面,維持 $BIN_DIR 優先
			[ -x "$b/brew" ] && PATH="$PATH:$b" && break
		done
	fi
	if ! have brew; then
		log "沒有安裝 Homebrew,直接下載官方預編譯檔"
		return 0
	fi
	if ! brew_bottle_tag >/dev/null; then
		warn "不認得這個 macOS 版本的 Homebrew bottle 標籤,不使用 brew,直接下載官方預編譯檔"
		return 0
	fi
	USE_BREW=1
	export HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_INSTALL_CLEANUP=1
	log "偵測到 Homebrew:有預編譯 bottle 的工具用 brew 安裝,否則下載官方預編譯檔"
	brew update --quiet >/dev/null 2>&1 || warn "brew update 失敗,使用現有的 formula 資訊"
	export HOMEBREW_NO_AUTO_UPDATE=1
}

# ripgrep / fd (Linux 走 apt)。macOS 的官方預編譯檔需要新版系統 (ripgrep 14 要 macOS 13、fd 10 要 14),
# 舊版 macOS 沒有能用的預編譯檔時,改用 cargo 編譯 (rustup 提供預編譯的 Rust 工具鏈,只編這一個工具,不會編 LLVM)。
install_rg_fd_macos() {
	ensure_optional rg BurntSushi/ripgrep fetch_ripgrep "ripgrep" ripgrep
	ensure_optional fd sharkdp/fd fetch_fd "fd" fd
	cargo_fallback rg ripgrep "ripgrep (live grep / 全域搜尋會用到)"
	cargo_fallback fd fd-find "fd (選用,沒有時退回 rg)"
}

cargo_fallback() { # $1 = 執行檔名  $2 = crate 名稱  $3 = 顯示名稱
	can_run "$1" && return 0
	if have cargo; then
		log "預編譯的 $3 無法在此系統執行,改用 cargo 編譯 (數分鐘)"
		cargo install --locked "$2" || warn "cargo install $2 失敗"
	else
		warn "找不到能執行的 $3,且沒有 cargo 可以編譯 (使用了 --no-rust?)。請之後手動安裝"
	fi
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
	WITH_BREW=1
	USE_BREW=0
	local arg
	for arg in "$@"; do
		case "$arg" in
		--no-rust) WITH_RUST=0 ;;
		--no-font) WITH_FONT=0 ;;
		--no-plugins) WITH_PLUGINS=0 ;;
		--no-brew) WITH_BREW=0 ;;
		-h | --help)
			sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
			exit 0
			;;
		*)
			echo "未知參數:$arg" >&2
			exit 1
			;;
		esac
	done

	detect_platform
	mkdir -p "$BIN_DIR"
	local orig_path="$PATH"
	export PATH="$BIN_DIR:$HOME/.cargo/bin:$PATH"

	case "$UNAME_S" in
	Linux) install_base_linux ;;
	Darwin) install_base_macos ;;
	esac

	ensure_nvim
	ensure_node
	ensure_tree_sitter
	ensure_optional lazygit jesseduffield/lazygit fetch_lazygit "lazygit" lazygit
	install_font
	install_rust || warn "Rust 工具鏈安裝失敗 (選用,Rust 專案才會用到),可稍後重新執行本腳本"
	if [ "$UNAME_S" = "Darwin" ]; then
		install_rg_fd_macos
	fi
	setup_nvim

	if ! grep -qx "$BIN_DIR" <<<"${orig_path//:/$'\n'}"; then
		warn "請確認 $BIN_DIR 在你的 PATH 內 (例如在 ~/.zshrc 或 ~/.bashrc 加上 export PATH=\"\$HOME/.local/bin:\$PATH\")"
	fi
	if [ "$WITH_FONT" -eq 1 ]; then
		log "提醒:請在終端機設定使用 \"JetBrainsMono Nerd Font\",否則圖示會顯示成方框"
	fi
	log "完成。開啟 nvim 後執行 :Deps 可檢查所有依賴;Copilot 請執行 :Copilot auth"
}

# 被 source 時 (測試) 只載入函式,不執行
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	main "$@"
fi
