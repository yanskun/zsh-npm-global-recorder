# =======================
# npm global recorder (zsh)
# - npm install -g foo → ~/.default-npm-packages に追記（重複回避）
# - npm uninstall -g foo → 対応行を削除
# - 成功(exit code 0)時のみ反映
# - name@1.2.3 / name@latest / @scope/name@beta → 正規化して name / @scope/name
# =======================

# --- config ---
# 明示の DEFAULT_NPM_PKGS_FILE があれば最優先
# なければ MISE_NODE_DEFAULT_PACKAGES_FILE、それも無ければ $HOME/.default-npm-packages
: ${DEFAULT_NPM_PKGS_FILE:=${MISE_NODE_DEFAULT_PACKAGES_FILE:-$HOME/.default-npm-packages}}
# ---------------

# 作業用の内部変数
typeset -ga __npm_global_pending_pkgs=()
typeset -g  __npm_global_action=""   # "install" | "uninstall" | ""

# 便利関数: 変数初期化
__npm_recorder_reset() {
  __npm_global_pending_pkgs=()
  __npm_global_action=""
}

# 便利関数: パッケージ名の正規化
# - @scope/name@version → @scope/name
# - name@tag             → name
__npm_normalize_pkg() {
  local p="$1"
  if [[ $p == @*/*@* ]]; then
    print -r -- "${p%\@*}"
  else
    print -r -- "${p%%@*}"
  fi
}

# 便利関数: “パッケージらしい” 単語かを大雑把に判定
#  - 許容: name / @scope/name / name@ver / gitやURL/ローカルパスは除外
__npm_is_pkg_token() {
  setopt local_options extendedglob
  local token="$1"
  # オプションは除外
  [[ $token == -* ]] && return 1

  # URL / Git / ローカルパスらしきものを除外
  [[ $token == (http|https|git)://* ]] && return 1
  [[ $token == git+* ]] && return 1
  [[ $token == ./* || $token == ../* || $token == /* ]] && return 1

  # おおまかなパターン: @scope/name(…)? or bare-name(…)?（英数._-）
  [[ $token == (@*/*|[a-z0-9._-]##)(@*)(#c0,1) ]] && return 0

  return 1
}

# 便利関数: install 処理
__npm_recorder_apply_install() {
  local pkg
  for pkg in $__npm_global_pending_pkgs; do
    # 完全一致が未登録なら追記
    if ! grep -qxF -- "$pkg" "$DEFAULT_NPM_PKGS_FILE" 2>/dev/null; then
      print -r -- "$pkg" >> "$DEFAULT_NPM_PKGS_FILE"
    fi
  done
}

# 便利関数: uninstall 処理（シンボリックリンク対応）
__npm_recorder_apply_uninstall() {
  # ファイルが無ければやることなし
  [[ -f $DEFAULT_NPM_PKGS_FILE ]] || { __npm_recorder_reset; return; }

  local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/npm-default-pkgs.XXXXXXXX")" || { __npm_recorder_reset; return; }

  # 除外対象を連想配列に登録してフィルタ
  local pkg
  typeset -A deny_map=()
  for pkg in $__npm_global_pending_pkgs; do
    deny_map[$pkg]=1
  done

  local -a kept=()
  local line
  while IFS= read -r line || [[ -n $line ]]; do
    [[ -n ${deny_map[$line]} ]] && continue
    kept+=("$line")
  done < "$DEFAULT_NPM_PKGS_FILE"

  if (( ${#kept} )); then
    printf '%s\n' "${kept[@]}" >| "$tmp"
  else
    : >| "$tmp"
  fi

  # 既存ファイルがシンボリックリンクでも壊さないよう、コピーで上書き
  if ! cat -- "$tmp" >| "$DEFAULT_NPM_PKGS_FILE"; then
    command rm -f -- "$tmp"
    __npm_recorder_reset
    return
  fi

  command rm -f -- "$tmp"
}

# preexec: 実行直前にコマンドラインを解析
preexec() {
  __npm_recorder_reset

  local cmd="$1"
  local -a argv; argv=(${(z)cmd})  # zsh 準拠の分割（クォートを考慮）

  (( ${#argv} )) || return

  # npm / corepack npm / npx 経由をざっくり検出
  # 例: "npm i -g foo", "corepack npm install -g foo"
  local head1="${argv[1]}"
  if [[ $head1 != (npm|npx|corepack) ]]; then
    return
  fi

  # corepack npm の形に対応
  local i=1
  if [[ $head1 == corepack ]]; then
    (( ${#argv} >= 2 )) || return
    if [[ ${argv[2]} == npm ]]; then
      i=2
    else
      return
    fi
  fi

  local sub="${argv[i+1]:-}"  # install|i / uninstall|remove|rm|r|un など
  local action=""

  case "$sub" in
    install|i)                      action="install" ;;
    uninstall|remove|rm|r|un)       action="uninstall" ;;
    *)                              return ;;
  esac

  # -g/--global の有無確認（global でなければ対象外）
  local has_global=0 a
  for a in $argv; do
    [[ $a == "-g" || $a == "--global" ]] && { has_global=1; break; }
  done
  (( has_global )) || return

  # パッケージ候補を抽出（コマンド本体とサブコマンドは除外）
  local -i first_pkg_idx=$(( i + 2 ))
  local -a raw_pkgs=()
  if (( first_pkg_idx <= $#argv )); then
    local -i idx
    local token
    for (( idx = first_pkg_idx; idx <= $#argv; idx++ )); do
      token=${argv[idx]}
      __npm_is_pkg_token "$token" && raw_pkgs+="$token"
    done
  fi
  (( ${#raw_pkgs} )) || return

  # 正規化して保持
  local -a clean=()
  local p
  for p in $raw_pkgs; do
    clean+=("$(__npm_normalize_pkg "$p")")
  done

  __npm_global_pending_pkgs=(${clean:#""})
  __npm_global_action="$action"
}

# precmd: 直前コマンドの終了コードを見て、成功時のみ反映
precmd() {
  (( ${#__npm_global_pending_pkgs} )) || return
  local -i exit_status=$?  # 直前コマンドの終了コード
  (( exit_status == 0 )) || { __npm_recorder_reset; return; }

  # ファイルの準備（install時に必要）
  if [[ $__npm_global_action == "install" ]]; then
    [[ -d ${DEFAULT_NPM_PKGS_FILE:h} ]] || mkdir -p -- "${DEFAULT_NPM_PKGS_FILE:h}"
    [[ -f $DEFAULT_NPM_PKGS_FILE ]] || : >| "$DEFAULT_NPM_PKGS_FILE"
  fi

  case "$__npm_global_action" in
    install)
      __npm_recorder_apply_install
      ;;

    uninstall)
      __npm_recorder_apply_uninstall
      ;;

    *)
      ;;
  esac

  __npm_recorder_reset
}
