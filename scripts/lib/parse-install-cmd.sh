#!/usr/bin/env bash
# parse_install_cmd <bash-command-string>
# Prints TAB-separated "ecosystem\tpkg\tversion" lines.
# The blocking parser uses "__ambiguous_command__\tenv -S\t" when it cannot
# safely recover the command from env's split-string option.

# parse_install_cmd   — strips shell prefixes first. For the BLOCKING path.
# parse_install_cmd_strict — no prefix stripping. For auto-record.
#
# The asymmetry is deliberate and is the structural defence against fabricated
# records. Over-detection in PreToolUse costs a false block, which is annoying
# but safe. Over-detection in PostToolUse writes a sidecar entry for a package
# nobody checked, after which a genuine install of it is waved through — a
# laundering primitive against the guard itself. Prefix stripping is textual
# guesswork about which word is the real command, so it is kept out of the path
# where guessing wrong is dangerous.
parse_install_cmd() {
  _vs_parse_install_cmd "$1" 1
}

parse_install_cmd_strict() {
  _vs_parse_install_cmd "$1" 0
}

VS_PARSE_AMBIGUOUS_ECOSYSTEM="__ambiguous_command__"
VS_UNPINNED_VERSION="__version_sentinel_unpinned__"

_restore_install_token_chars() {
  local tok="$1"
  # Use tr instead of ${value//pattern/replacement}: Bash 5 can treat `&` in
  # the replacement as the matched text, while Bash 3 treats it literally.
  tok=$(printf '%s' "$tok" | LC_ALL=C tr $'\034\035\036\037' ' ;&|')
  printf '%s' "$tok"
}

# Keep whitespace and shell separators inside a quoted argument opaque while
# the intentionally small shell parser splits command segments and words. The
# control characters are restored by _restore_install_token_chars. This is not
# a shell evaluator: it only preserves the argument boundary needed for quoted
# version ranges such as "pkg@1.x || 2.x".
_protect_install_cmd_quotes() {
  local input="$1" output="" quote="" ch="" next="" i=0
  while [[ "$i" -lt "${#input}" ]]; do
    ch="${input:i:1}"
    # Outside single quotes, a backslash can make a shell separator literal.
    # Consume the pair here so the separator is not mistaken for command
    # syntax. Preserve escaped quote/backslash characters as visibly escaped
    # data so they cannot look like the token's syntactic outer quotes.
    if [[ "$ch" == "\\" && "$quote" != "'" && $((i + 1)) -lt ${#input} ]]; then
      next="${input:i+1:1}"
      if [[ -z "$quote" ]]; then
        case "$next" in
          $'\n') i=$((i + 2)); continue ;;
          ' '|$'\t') ch=$'\034' ;;
          ';') ch=$'\035' ;;
          '&') ch=$'\036' ;;
          '|') ch=$'\037' ;;
          "'"|'"'|'\\') ch="\\$next" ;;
          *) ch="$next" ;;
        esac
        output+="$ch"
        i=$((i + 2))
        continue
      fi
      case "$next" in
        '$'|'`'|'"'|'\\')
          output+="\\$next"
          i=$((i + 2))
          continue ;;
        $'\n') i=$((i + 2)); continue ;;
      esac
    fi
    if [[ -z "$quote" ]]; then
      case "$ch" in
        "'"|'"') quote="$ch"; ch="" ;;
      esac
    elif [[ "$ch" == "$quote" ]]; then
      quote=""
      ch=""
    else
      case "$ch" in
        ' '|$'\t'|$'\n') ch=$'\034' ;;
        ';') ch=$'\035' ;;
        '&') ch=$'\036' ;;
        '|') ch=$'\037' ;;
      esac
    fi
    output+="$ch"
    i=$((i + 1))
  done
  printf '%s' "$output"
}

_is_non_registry_install_target() {
  case "$1" in
    .|..|./*|../*|/*|~/*|*.tgz|*.tar.gz|*.whl|file:*|link:*|workspace:*|portal:*|git:*|git+*|git@*|github:*|gitlab:*|bitbucket:*|http://*|https://*|ssh://*) return 0 ;;
  esac
  return 1
}

_normalize_exact_install_version() {
  local raw="$1" style="${2:-literal}"
  raw="${raw#v}"
  # Once an ecosystem-specific exact operator has been removed, selector
  # syntax must not remain. This keeps ranges, exclusions, wildcards, and
  # compound requirements out of sidecar lookups and auto-recorded entries.
  case "$raw" in
    ""|*"*"*|*"<"*|*">"*|*"="*|*"^"*|*"~"*|*","*|*"|"*|*[[:space:]]*)
      printf '%s' "$VS_UNPINNED_VERSION"; return ;;
  esac
  if [[ "$style" == "semver" ]]; then
    if [[ "$raw" =~ ^[0-9]+[.][0-9]+[.][0-9]+([-+][0-9A-Za-z.-]+)?$ ]]; then
      printf '%s' "$raw"
    else
      printf '%s' "$VS_UNPINNED_VERSION"
    fi
    return
  fi
  if [[ "$raw" =~ ^[0-9][0-9A-Za-z._!+-]*$ ]]; then
    printf '%s' "$raw"
  else
    printf '%s' "$VS_UNPINNED_VERSION"
  fi
}

_npm_install_version() {
  local raw="$1"
  case "$raw" in
    file:*|link:*|workspace:*|portal:*|git:*|git+*|github:*|http://*|https://*|ssh://*|npm:*) return ;;
  esac
  raw="${raw#=}"
  _normalize_exact_install_version "$raw" semver
}

_poetry_install_version() {
  local raw="$1"
  raw="${raw#=}"
  _normalize_exact_install_version "$raw"
}

_cargo_install_version() {
  local raw="$1"
  # A bare Cargo version requirement is caret-compatible. Only =version names
  # one registry release, whether supplied as package@=version or --vers.
  if [[ "$raw" != =* ]]; then
    printf '%s' "$VS_UNPINNED_VERSION"
    return
  fi
  _normalize_exact_install_version "${raw#=}" semver
}

# The strip flag is threaded through as an argument rather than a global: a
# security boundary must not depend on which entry point ran last in the
# process. Absent, it defaults to 0 (strict) -- the direction that cannot
# fabricate.
_vs_parse_install_cmd() {
  local cmd="$1" strip="${2:-0}"
  local segment
  local segments
  local old_ifs="$IFS"
  local redir_amp=$'\033' redir_pipe=$'\032'
  # Use mapfile/readarray with command substitution instead of process substitution
  cmd=$(_protect_install_cmd_quotes "$cmd")
  # Ampersands and pipes inside redirection operators are not command
  # separators. Protect them before splitting shell control operators, then
  # restore them in each segment.
  cmd="${cmd//&>/${redir_amp}>}"
  cmd="${cmd//>&/>${redir_amp}}"
  cmd="${cmd//<&/<${redir_amp}}"
  cmd="${cmd//>|/>${redir_pipe}}"
  IFS=$'\n' mapfile -t segments < <(printf '%s\n' "$cmd" | tr ';&|' '\n') 2>/dev/null || {
    # Fallback for older bash or environments without /dev/fd support
    local temp_output
    temp_output=$(printf '%s\n' "$cmd" | tr ';&|' '\n')
    IFS=$'\n' read -r -d '' -a segments <<< "$temp_output" || true
  }
  IFS="$old_ifs"
  for segment in "${segments[@]}"; do
    segment=$(printf '%s' "$segment" | LC_ALL=C tr "$redir_amp$redir_pipe" '&|')
    segment="${segment#"${segment%%[![:space:]]*}"}"
    [[ -z "$segment" ]] && continue
    _parse_install_segment "$segment" "$strip"
  done
}

# _strip_cmd_prefix <segment>
# Removes shell prefixes that do not change which command actually runs:
# leading environment assignments (`FOO=bar <cmd>`) and process wrappers that
# exec their argument (`timeout 30 <cmd>`, `nice -n 10 <cmd>`, `sudo <cmd>`).
# Without this, anchoring on ^(npm|...) meant such a prefix defeated the guard
# completely and the package really did get installed. NOTE the ^ anchor is
# still there, so anything OTHER than a stripped wrapper in front of the manager
# remains undetected: `python -m pip install X`, `.venv/bin/pip install X`,
# `/usr/local/bin/npm install X`. Those are pre-existing gaps, not closed here,
# and they are pinned as known limits in tests/test_parse_install_cmd.sh so this
# comment is not misread as covering them. The wrapper list
# mirrors the one Claude Code strips before matching Bash permission rules,
# plus sudo/doas.
#
# COUPLED TO hooks/hooks.json: its `if` rules are shaped `Bash(*<mgr>*)`
# rather than `Bash(<mgr> *)` precisely so the hook still spawns for these
# prefixed forms. Measured: `Bash(<mgr> *)` does NOT fire for a wrapper prefix.
# If you add a wrapper here, re-check that the rules still fire for it.
#
# WHY THE FLAG TABLE IS PER-WRAPPER AND CONSERVATIVE. Consuming `<flag> <word>`
# when that flag takes NO operand eats the real command, and whatever follows is
# then parsed as an install that never happens -- `env -i true <pm> install
# <pkg>` runs `true` and installs nothing. Historically that was severe, because
# auto-record.sh shared this parse and would record a check for <pkg>, after
# which a genuine install of it was allowed. It no longer can: auto-record.sh
# calls parse_install_cmd_strict, which never reaches this function, so the cost
# of being wrong here is now a false BLOCK rather than a fabricated record. Keep
# the table conservative regardless -- a false block on a command an agent
# legitimately wants is still a bad day, and the strict/lenient split is what
# makes that the worst case, so do not erode it. So an operand is
# consumed only for flags of THAT wrapper which REQUIRE one. Flags with optional
# operands (xargs -i, sudo -h) are deliberately absent: guessing wrong in this
# direction fabricates an install, while guessing wrong in the other direction
# merely misses one, which is the pre-existing behaviour. With the table correct,
# the word after a consumed operand IS the real command, so if it is a package
# manager then an install genuinely is happening. Entries were checked against
# the man pages on macOS/BSD (env -C/-P/-S/-u, xargs -I/-J/-L/-E, sudo -u/-g/
# -p/-C/-U, nice -n, stdbuf -i/-o/-e, timeout -s/-k) rather than from memory.
_VS_ASSIGN_RE="^[A-Za-z_][A-Za-z0-9_]*=('[^']*'|\"[^\"]*\"|[^[:space:]]*)[[:space:]]+(.*)"

_strip_cmd_prefix() {
  local seg="$1" prev="" _vs_wrapper="" _vs_optflags=""
  while [[ "$seg" != "$prev" ]]; do
    prev="$seg"
    # An assignment value may be single- or double-quoted and contain spaces
    # (`CFLAGS='-O2 -g' <pm> install <pkg>`). A bare [^[:space:]]* class stops
    # mid-value, leaving the tail in front of the manager so the ^ anchor fails
    # -- a real bypass, because the `if` rule still fires and the hook then
    # finds nothing. Held in a variable so the quoting stays readable.
    while [[ "$seg" =~ $_VS_ASSIGN_RE ]]; do
      seg="${BASH_REMATCH[2]}"
    done
    if [[ "$seg" =~ ^(timeout|time|nice|nohup|stdbuf|command|builtin|noglob|env|xargs|sudo|doas)[[:space:]]+(.*) ]]; then
      _vs_wrapper="${BASH_REMATCH[1]}"
      seg="${BASH_REMATCH[2]}"
      case "$_vs_wrapper" in
        sudo|doas) _vs_optflags='-u|-g|-p|-C|-r|-t|-U|-D|-R|-T|--user|--group|--prompt|--close-from|--role|--type|--other-user|--chdir|--chroot|--command-timeout' ;;
        timeout)   _vs_optflags='-s|-k|--signal|--kill-after' ;;
        nice)      _vs_optflags='-n|--adjustment' ;;
        stdbuf)    _vs_optflags='-i|-o|-e|--input|--output|--error' ;;
        env)       _vs_optflags='-u|-C|-P|--unset|--chdir' ;;
        xargs)     _vs_optflags='-I|-J|-n|-L|-P|-s|-d|-E|-a|--replace|--max-args|--max-lines|--max-procs|--max-chars|--delimiter|--eof|--arg-file' ;;
        *)         _vs_optflags='' ;;
      esac
      while :; do
        # `--` ends the wrapper's options; the next word IS the command.
        if [[ "$seg" =~ ^--[[:space:]]+(.*) ]]; then
          seg="${BASH_REMATCH[1]}"; break
        fi
        # `env -S` takes a COMMAND STRING as its operand, so the premise this
        # whole function rests on -- that the word after an operand is the real
        # command -- does not hold, in any of its spellings (-S x, -Sx,
        # --split-string=x). Report ambiguity rather than guess so the blocking
        # caller can fail closed.
        #
        # env ONLY. `sudo -S` means "read the password from stdin", takes no
        # operand, and the next word IS the command: `echo pw | sudo -S <pm>
        # install <pkg>` is a standard idiom, and bailing on it skipped a real
        # install.
        if [[ "$_vs_wrapper" == "env" ]] &&
           { [[ "$seg" =~ ^(-S|--split-string)([=[:space:]]|$) ]] ||
             [[ "$seg" =~ ^-S[^[:space:]] ]]; }; then
          return 2
        fi
        # A flag of this wrapper that requires a separate operand.
        if [[ -n "$_vs_optflags" ]] &&
           [[ "$seg" =~ ^($_vs_optflags)[[:space:]]+[^[:space:]\"\']+[[:space:]]+(.*) ]]; then
          seg="${BASH_REMATCH[2]}"; continue
        fi
        # Attached flags (`-o0`, `--rm`) and bare durations (`30`, `5s`, `1.5`).
        if [[ "$seg" =~ ^(-[^[:space:]]*|[0-9]+([.][0-9]+)?[smhd]?)[[:space:]]+(.*) ]]; then
          seg="${BASH_REMATCH[3]}"; continue
        fi
        break
      done
    fi
  done
  printf '%s' "$seg"
}

_parse_install_segment() {
  local seg="$1" strip="${2:-0}"
  if [[ "$strip" == "1" ]]; then
    if ! seg=$(_strip_cmd_prefix "$1"); then
      printf '%s\tenv -S\t\n' "$VS_PARSE_AMBIGUOUS_ECOSYSTEM"
      return
    fi
  fi
  if [[ "$seg" =~ ^(npm|pnpm|yarn|bun)[[:space:]]+(add|install|i)[[:space:]]+(.*) ]]; then
    local npm_manager="${BASH_REMATCH[1]}" npm_action="${BASH_REMATCH[2]}" npm_rest="${BASH_REMATCH[3]}"
    # pnpm/yarn/bun install reads the manifest; their package-adding command is
    # add. Treating install's positional values as packages creates findings
    # for command operands that those CLIs do not define as dependencies.
    if [[ "$npm_manager" != "npm" && "$npm_action" != "add" ]]; then return; fi
    _emit_npm_packages "$npm_manager" "$npm_rest" "$strip"; return
  fi
  if [[ "$seg" =~ ^pip3?[[:space:]]+install[[:space:]]+(.*) ]]; then
    _emit_pep508 pip "${BASH_REMATCH[1]}"; return
  fi
  if [[ "$seg" =~ ^poetry[[:space:]]+add[[:space:]]+(.*) ]]; then
    _emit_poetry "${BASH_REMATCH[1]}"; return
  fi
  if [[ "$seg" =~ ^uv[[:space:]]+(add|pip[[:space:]]+install)[[:space:]]+(.*) ]]; then
    local uv_action="${BASH_REMATCH[1]}" uv_rest="${BASH_REMATCH[2]}"
    if [[ "$uv_action" == "add" ]]; then
      _emit_pep508 uv-add "$uv_rest"; return
    fi
    _emit_pep508 uv-pip "$uv_rest"; return
  fi
  if [[ "$seg" =~ ^cargo[[:space:]]+add[[:space:]]+(.*) ]]; then
    _emit_cargo_add "${BASH_REMATCH[1]}"; return
  fi
  if [[ "$seg" =~ ^dotnet[[:space:]]+add[[:space:]]+package[[:space:]]+(.*) ]]; then
    _emit_dotnet_add "${BASH_REMATCH[1]}"; return
  fi
  if [[ "$seg" =~ ^dotnet[[:space:]]+package[[:space:]]+add[[:space:]]+(.*) ]]; then
    _emit_dotnet_add "${BASH_REMATCH[1]}"; return
  fi
}

# Return success when an operator consumes the following token. Return 1 for
# an attached redirect and 2 when the token is not a redirect. Strip any
# leading file-descriptor number first so descriptors of any length work.
_redirection_kind() {
  local op="$1"
  while [[ "$op" == [0-9]* ]]; do op="${op#?}"; done
  case "$op" in
    '<'|'>'|'<<'|'<<-'|'<<<'|'>>'|'<>'|'>|'|'<&'|'>&'|'&>'|'&>>') return 0 ;;
    '<'*|'>'*|'&>'*) return 1 ;;
  esac
  return 2
}

# Tables contain flags whose value can be a separate word. Long --flag=value
# and attached short forms are already one token. Boolean flags fall through
# to the generic -* branch and therefore never consume a package.
_npm_option_takes_value() {
  local manager="$1" opt="$2"
  case "$manager:$opt" in
    npm:-w|npm:--workspace|npm:--prefix|npm:--registry|npm:--cache|npm:--userconfig|npm:--globalconfig|npm:--tag|npm:--omit|npm:--include|npm:--install-strategy|npm:--allow-directory|npm:--allow-file|npm:--allow-git|npm:--allow-remote|npm:--allow-scripts|npm:--before|npm:--min-release-age|npm:--min-release-age-exclude|npm:--cpu|npm:--os|npm:--libc|npm:--loglevel|npm:--scope|npm:--script-shell|npm:--save-prefix|npm:--fetch-retries|npm:--fetch-retry-factor|npm:--fetch-retry-mintimeout|npm:--fetch-retry-maxtimeout|npm:--fetch-timeout|npm:--https-proxy|npm:--proxy|npm:--noproxy|npm:--cafile|npm:--cert|npm:--key)
      return 0 ;;
    pnpm:-C|pnpm:--dir|pnpm:--filter|pnpm:--save-catalog-name|pnpm:--allow-build|pnpm:--cpu|pnpm:--os|pnpm:--libc|pnpm:--config-dir|pnpm:--store-dir|pnpm:--virtual-store-dir|pnpm:--package-import-method|pnpm:--network-concurrency|pnpm:--fetch-retries|pnpm:--fetch-retry-factor|pnpm:--fetch-retry-mintimeout|pnpm:--fetch-retry-maxtimeout|pnpm:--fetch-timeout|pnpm:--registry|pnpm:--tag|pnpm:--reporter|pnpm:--loglevel)
      return 0 ;;
    yarn:--mode|yarn:--cwd|yarn:--cache-folder|yarn:--modules-folder|yarn:--mutex|yarn:--network-concurrency|yarn:--network-timeout|yarn:--registry|yarn:--proxy|yarn:--https-proxy|yarn:--preferred-cache-folder)
      return 0 ;;
    bun:-c|bun:--omit|bun:--ca|bun:--cafile|bun:--registry|bun:--network-concurrency|bun:--backend|bun:--concurrent-scripts|bun:--cache-dir|bun:--config|bun:--cwd|bun:--filter|bun:--minimum-release-age|bun:--minimum-release-age-excludes|bun:--linker|bun:--cpu|bun:--os)
      return 0 ;;
  esac
  return 1
}

_npm_option_is_boolean() {
  case "$1:$2" in
    npm:-S|npm:--save|npm:-B|npm:--save-bundle|npm:-D|npm:--save-dev|npm:-E|npm:--save-exact|npm:-O|npm:--save-optional|npm:--save-peer|npm:-P|npm:--save-prod|npm:--no-save|npm:-g|npm:--global|npm:--install-links|npm:--legacy-peer-deps|npm:--strict-peer-deps|npm:--prefer-dedupe|npm:--package-lock|npm:--package-lock-only|npm:--foreground-scripts|npm:--ignore-scripts|npm:--strict-allow-scripts|npm:--dangerously-allow-all-scripts|npm:--audit|npm:--bin-links|npm:--fund|npm:--dry-run|npm:--workspaces|npm:--include-workspace-root|npm:--global-style|npm:--legacy-bundling|npm:--prefer-online|npm:--prefer-offline|npm:--offline|npm:-f|npm:--force|npm:-y|npm:--yes|npm:--engine-strict|npm:--ignore-workspace-root-check|npm:--provenance|npm:--sbom|pnpm:-D|pnpm:-d|pnpm:--save-dev|pnpm:-O|pnpm:-o|pnpm:--save-optional|pnpm:--save-peer|pnpm:-P|pnpm:-p|pnpm:--save-prod|pnpm:-E|pnpm:-e|pnpm:--save-exact|pnpm:--save-catalog|pnpm:--config|pnpm:--workspace|pnpm:-g|pnpm:--global|pnpm:-w|pnpm:--workspace-root|pnpm:--offline|pnpm:--prefer-offline|pnpm:--ignore-workspace-root-check|pnpm:--lockfile-only|pnpm:--fix-lockfile|pnpm:--frozen-lockfile|pnpm:--prefer-frozen-lockfile|pnpm:--ignore-scripts|pnpm:--force|pnpm:--use-stderr|pnpm:--prod|pnpm:--dev|pnpm:--optional|yarn:-D|yarn:--dev|yarn:-P|yarn:--peer|yarn:-O|yarn:--optional|yarn:-E|yarn:--exact|yarn:-T|yarn:--tilde|yarn:-C|yarn:--caret|yarn:--prefer-dev|yarn:-i|yarn:--interactive|yarn:--cached|yarn:-F|yarn:--fixed|yarn:--json|yarn:--no-time-gate|bun:-y|bun:--yarn|bun:-p|bun:--production|bun:--no-save|bun:--save|bun:--dry-run|bun:--frozen-lockfile|bun:-f|bun:--force|bun:--no-cache|bun:--silent|bun:--quiet|bun:--verbose|bun:--no-progress|bun:--no-summary|bun:--no-verify|bun:--ignore-scripts|bun:--trust|bun:-g|bun:--global|bun:--save-text-lockfile|bun:--lockfile-only|bun:-d|bun:--dev|bun:--optional|bun:--peer|bun:-E|bun:--exact|bun:-a|bun:--analyze|bun:--only-missing)
      return 0 ;;
  esac
  # npm-style Boolean configs accept the standard --no-<name> negation.
  if [[ "$2" == --no-* ]]; then
    _npm_option_is_boolean "$1" "--${2#--no-}"
    return
  fi
  return 1
}

_npm_option_has_attached_value() {
  case "$1:$2" in
    npm:-w?*|pnpm:-C?*|bun:-c?*) return 0 ;;
  esac
  return 1
}

_find_unknown_npm_option() {
  local manager="$1" rest="$2" tok skip_next=0 options_done=0 redir_kind=0
  VS_UNKNOWN_OPTION=""
  for tok in $rest; do
    tok=$(_restore_install_token_chars "$tok")
    if [[ "$skip_next" -eq 1 ]]; then skip_next=0; continue; fi
    _redirection_kind "$tok"; redir_kind=$?
    [[ "$redir_kind" -eq 0 ]] && { skip_next=1; continue; }
    [[ "$redir_kind" -eq 1 ]] && continue
    [[ "$tok" == "--" ]] && { options_done=1; continue; }
    [[ "$options_done" -eq 1 || "$tok" != -* ]] && continue
    _npm_option_takes_value "$manager" "$tok" && { skip_next=1; continue; }
    _npm_option_is_boolean "$manager" "$tok" && continue
    _npm_option_has_attached_value "$manager" "$tok" && continue
    [[ "$tok" == --*=* ]] && continue
    # After exact value flags have been handled, a multi-letter short token is
    # either a boolean bundle (-DPE, -vvv) or an attached short operand. In
    # both cases it consumes no separate word.
    [[ "$tok" =~ ^-[^-].+ ]] && continue
    VS_UNKNOWN_OPTION="$tok"
    return 0
  done
  return 1
}

_pip_option_takes_value() {
  local manager="$1" opt="$2"
  case "$manager:$opt" in
    pip:-r|pip:--requirement|pip:-c|pip:--constraint|pip:--build-constraint|pip:--requirements-from-script|pip:-e|pip:--editable|pip:-t|pip:--target|pip:--platform|pip:--python-version|pip:--implementation|pip:--abi|pip:--root|pip:--prefix|pip:--src|pip:-f|pip:--find-links|pip:-i|pip:--index-url|pip:--extra-index-url|pip:--trusted-host|pip:--cert|pip:--client-cert|pip:--proxy|pip:--cache-dir|pip:--log|pip:--report|pip:--group|pip:--root-user-action|pip:--timeout|pip:--retries|pip:--resume-retries|pip:--exists-action|pip:--progress-bar|pip:--use-feature|pip:--use-deprecated|pip:-C|pip:--config-settings|pip:--global-option|pip:--hash|pip:--python|pip:--upgrade-strategy|pip:--keyring-provider|pip:--no-binary|pip:--only-binary|pip:--all-releases|pip:--only-final|pip:--uploaded-prior-to)
      return 0 ;;
    uv-add:-r|uv-add:--requirements|uv-add:-c|uv-add:--constraints|uv-add:-m|uv-add:--marker|uv-add:--optional|uv-add:--group|uv-add:--bounds|uv-add:--rev|uv-add:--tag|uv-add:--branch|uv-add:--extra|uv-add:--package|uv-add:--script|uv-add:--no-install-package|uv-add:--index|uv-add:--default-index|uv-add:-i|uv-add:--index-url|uv-add:--extra-index-url|uv-add:-f|uv-add:--find-links|uv-add:--index-strategy|uv-add:--keyring-provider|uv-add:-P|uv-add:--upgrade-package|uv-add:--upgrade-group|uv-add:--resolution|uv-add:--prerelease|uv-add:--fork-strategy|uv-add:--exclude-newer|uv-add:--exclude-newer-package|uv-add:--no-sources-package|uv-add:--reinstall-package|uv-add:--link-mode|uv-add:-C|uv-add:--config-setting|uv-add:--config-settings-package|uv-add:--no-build-isolation-package|uv-add:--no-build-package|uv-add:--no-binary-package|uv-add:--cache-dir|uv-add:--refresh-package|uv-add:-p|uv-add:--python|uv-add:--color|uv-add:--allow-insecure-host|uv-add:--directory|uv-add:--project|uv-add:--config-file)
      return 0 ;;
    uv-pip:-r|uv-pip:--requirements|uv-pip:-e|uv-pip:--editable|uv-pip:-c|uv-pip:--constraints|uv-pip:--overrides|uv-pip:--excludes|uv-pip:-b|uv-pip:--build-constraints|uv-pip:--extra|uv-pip:--group|uv-pip:-t|uv-pip:--target|uv-pip:--prefix|uv-pip:--no-binary|uv-pip:--only-binary|uv-pip:--python-version|uv-pip:--python-platform|uv-pip:--torch-backend|uv-pip:--index|uv-pip:--default-index|uv-pip:-i|uv-pip:--index-url|uv-pip:--extra-index-url|uv-pip:-f|uv-pip:--find-links|uv-pip:--index-strategy|uv-pip:--keyring-provider|uv-pip:-P|uv-pip:--upgrade-package|uv-pip:--upgrade-group|uv-pip:--resolution|uv-pip:--prerelease|uv-pip:--fork-strategy|uv-pip:--exclude-newer|uv-pip:--exclude-newer-package|uv-pip:--no-sources-package|uv-pip:--reinstall-package|uv-pip:--link-mode|uv-pip:-C|uv-pip:--config-setting|uv-pip:--config-settings-package|uv-pip:--no-build-isolation-package|uv-pip:--no-build-package|uv-pip:--no-binary-package|uv-pip:--cache-dir|uv-pip:--refresh-package|uv-pip:-p|uv-pip:--python|uv-pip:--color|uv-pip:--allow-insecure-host|uv-pip:--directory|uv-pip:--project|uv-pip:--config-file)
      return 0 ;;
  esac
  return 1
}

_poetry_option_takes_value() {
  case "$1" in
    -G|--group|-E|--extras|--python|--platform|--markers|--source|-C|--directory|-P|--project) return 0 ;;
  esac
  return 1
}

_cargo_option_takes_value() {
  case "$1" in
    --vers|--version|--registry|--rename|--features|-F|--package|-p|--manifest-path|-m|--path|--git|--branch|--tag|--rev|--base|--target|--color|--config|-Z|--lockfile-path) return 0 ;;
  esac
  return 1
}

_dotnet_option_takes_value() {
  case "$1" in
    --version|-v|--source|-s|--framework|-f|--package-directory|--project|--file|--configfile|--verbosity) return 0 ;;
  esac
  return 1
}

_emit_npm_packages() {
  local manager="$1" rest="$2" strip="${3:-0}" tok skip_next=0 pkg="" ver="" redir_kind=0
  if _find_unknown_npm_option "$manager" "$rest"; then
    if [[ "$strip" == "1" ]]; then
      printf '%s\t%s option %s\t\n' "$VS_PARSE_AMBIGUOUS_ECOSYSTEM" "$manager" "$VS_UNKNOWN_OPTION"
    fi
    return
  fi
  for tok in $rest; do
    tok=$(_restore_install_token_chars "$tok")
    if [[ "$skip_next" -eq 1 ]]; then skip_next=0; continue; fi
    _redirection_kind "$tok"; redir_kind=$?
    [[ "$redir_kind" -eq 0 ]] && { skip_next=1; continue; }
    [[ "$redir_kind" -eq 1 ]] && continue
    _npm_option_takes_value "$manager" "$tok" && { skip_next=1; continue; }
    [[ "$tok" == -* ]] && continue
    _is_non_registry_install_target "$tok" && continue
    pkg=""; ver=""
    if [[ "$tok" == *@npm:* ]]; then
      local target="${tok#*@npm:}"
      if [[ "$target" == @*/* ]]; then
        if [[ "$target" =~ ^(@[^/]+/[^@]+)(@(.+))?$ ]]; then
          pkg="${BASH_REMATCH[1]}"
          ver=$(_npm_install_version "${BASH_REMATCH[3]}")
        fi
      elif [[ "$target" == *@* ]]; then
        pkg="${target%@*}"
        ver=$(_npm_install_version "${target##*@}")
      elif [[ "$target" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
        pkg="$target"
        ver="$VS_UNPINNED_VERSION"
      fi
    elif [[ "$tok" == @*/* ]]; then
      if [[ "$tok" =~ ^(@[^/]+/[^@]+)(@(.+))?$ ]]; then
        pkg="${BASH_REMATCH[1]}"
        ver=$(_npm_install_version "${BASH_REMATCH[3]}")
      fi
    elif [[ "$tok" == *@* ]]; then
      pkg="${tok%@*}"
      ver=$(_npm_install_version "${tok##*@}")
    elif [[ "$tok" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
      pkg="$tok"
      ver="$VS_UNPINNED_VERSION"
    fi
    [[ -n "$pkg" && -n "$ver" ]] && printf 'npm\t%s\t%s\n' "$pkg" "$ver"
  done
}

_emit_pep508() {
  local manager="$1" rest="$2" tok skip_next=0 redir_kind=0
  for tok in $rest; do
    tok=$(_restore_install_token_chars "$tok")
    if [[ "$skip_next" -eq 1 ]]; then skip_next=0; continue; fi
    _redirection_kind "$tok"; redir_kind=$?
    [[ "$redir_kind" -eq 0 ]] && { skip_next=1; continue; }
    [[ "$redir_kind" -eq 1 ]] && continue
    _pip_option_takes_value "$manager" "$tok" && { skip_next=1; continue; }
    [[ "$tok" == -* ]] && continue
    _is_non_registry_install_target "$tok" && continue
    [[ "$tok" == *@* ]] && continue
    local requirement_part="${tok%%;*}"
    if [[ "$requirement_part" =~ ^([A-Za-z0-9][A-Za-z0-9._-]*)(\[[^]]+\])?([\<\>\=\!\~].*)$ ]]; then
      local pkg="${BASH_REMATCH[1]}" selector="${BASH_REMATCH[3]}" ver="$VS_UNPINNED_VERSION"
      if [[ "$selector" == ==* && "$selector" != ===* ]]; then
        ver=$(_normalize_exact_install_version "${selector#==}")
      fi
      printf 'pip\t%s\t%s\n' "$pkg" "$ver"
    elif [[ "$tok" =~ ^([A-Za-z0-9][A-Za-z0-9._-]*)(\[[^]]+\])?$ ]]; then
      printf 'pip\t%s\t%s\n' "${BASH_REMATCH[1]}" "$VS_UNPINNED_VERSION"
    fi
  done
}

_emit_poetry() {
  local rest="$1" tok skip_next=0 redir_kind=0
  for tok in $rest; do
    tok=$(_restore_install_token_chars "$tok")
    if [[ "$skip_next" -eq 1 ]]; then skip_next=0; continue; fi
    _redirection_kind "$tok"; redir_kind=$?
    [[ "$redir_kind" -eq 0 ]] && { skip_next=1; continue; }
    [[ "$redir_kind" -eq 1 ]] && continue
    _poetry_option_takes_value "$tok" && { skip_next=1; continue; }
    [[ "$tok" == -* ]] && continue
    _is_non_registry_install_target "$tok" && continue
    if [[ "$tok" == *@* ]]; then
      local p="${tok%@*}" v="${tok##*@}"
      _is_non_registry_install_target "$v" && continue
      v=$(_poetry_install_version "$v")
      printf 'pip\t%s\t%s\n' "$p" "$v"
    elif [[ "$tok" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
      printf 'pip\t%s\t%s\n' "$tok" "$VS_UNPINNED_VERSION"
    fi
  done
}

_emit_cargo_add() {
  local rest="$1" tok name="" ver="" take_ver=0 skip_next=0 non_registry=0 redir_kind=0
  for tok in $rest; do
    tok=$(_restore_install_token_chars "$tok")
    if [[ "$skip_next" -eq 1 ]]; then skip_next=0; continue; fi
    if [[ "$take_ver" -eq 1 ]]; then ver="$tok"; take_ver=0; continue; fi
    _redirection_kind "$tok"; redir_kind=$?
    [[ "$redir_kind" -eq 0 ]] && { skip_next=1; continue; }
    [[ "$redir_kind" -eq 1 ]] && continue
    if [[ "$tok" == "--vers" || "$tok" == "--version" ]]; then take_ver=1; continue; fi
    if [[ "$tok" == --vers=* || "$tok" == --version=* ]]; then ver="${tok#*=}"; continue; fi
    case "$tok" in
      --path|--git) skip_next=1; non_registry=1; continue ;;
      --path=*|--git=*) non_registry=1; continue ;;
    esac
    _cargo_option_takes_value "$tok" && { skip_next=1; continue; }
    [[ "$tok" == -* ]] && continue
    if [[ -z "$name" ]]; then
      if [[ "$tok" == *@* ]]; then name="${tok%@*}"; ver="${tok##*@}"; else name="$tok"; fi
    fi
  done
  [[ "$non_registry" -eq 1 ]] && return
  ver=$(_cargo_install_version "$ver")
  [[ -n "$name" ]] && printf 'cargo\t%s\t%s\n' "$name" "$ver"
}

_emit_dotnet_add() {
  local rest="$1" tok name="" ver="" take_ver=0 skip_next=0 redir_kind=0
  for tok in $rest; do
    tok=$(_restore_install_token_chars "$tok")
    if [[ "$skip_next" -eq 1 ]]; then skip_next=0; continue; fi
    if [[ "$take_ver" -eq 1 ]]; then ver="$tok"; take_ver=0; continue; fi
    _redirection_kind "$tok"; redir_kind=$?
    [[ "$redir_kind" -eq 0 ]] && { skip_next=1; continue; }
    [[ "$redir_kind" -eq 1 ]] && continue
    case "$tok" in
      --version|-v) take_ver=1 ;;
      *) _dotnet_option_takes_value "$tok" && { skip_next=1; continue; }
         if [[ "$tok" != -* && -z "$name" ]]; then
           if [[ "$tok" == *@* ]]; then
             name="${tok%@*}"
             ver="${tok##*@}"
           else
             name="$tok"
           fi
         fi ;;
    esac
  done
  [[ -z "$ver" || "$ver" == *"*"* ]] && ver="$VS_UNPINNED_VERSION"
  [[ -n "$name" ]] && printf 'csproj\t%s\t%s\n' "$name" "$ver"
}
