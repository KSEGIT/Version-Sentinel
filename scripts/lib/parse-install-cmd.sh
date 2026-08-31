#!/usr/bin/env bash
# parse_install_cmd <bash-command-string>
# Prints TAB-separated "ecosystem\tpkg\tversion" lines.

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

# The strip flag is threaded through as an argument rather than a global: a
# security boundary must not depend on which entry point ran last in the
# process. Absent, it defaults to 0 (strict) -- the direction that cannot
# fabricate.
_vs_parse_install_cmd() {
  local cmd="$1" strip="${2:-0}"
  local segment
  local segments
  local old_ifs="$IFS"
  # Use mapfile/readarray with command substitution instead of process substitution
  IFS=$'\n' mapfile -t segments < <(printf '%s\n' "$cmd" | tr ';&|' '\n') 2>/dev/null || {
    # Fallback for older bash or environments without /dev/fd support
    local temp_output
    temp_output=$(printf '%s\n' "$cmd" | tr ';&|' '\n')
    IFS=$'\n' read -r -d '' -a segments <<< "$temp_output" || true
  }
  IFS="$old_ifs"
  for segment in "${segments[@]}"; do
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
# COUPLED TO hooks/hooks.json: its `if` rules are shaped `Bash(*<mgr> *)`
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
_strip_cmd_prefix() {
  local seg="$1" prev="" _vs_wrapper="" _vs_optflags=""
  while [[ "$seg" != "$prev" ]]; do
    prev="$seg"
    while [[ "$seg" =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+(.*) ]]; do
      seg="${BASH_REMATCH[1]}"
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
        # --split-string=x). Abandon stripping rather than guess.
        #
        # env ONLY. `sudo -S` means "read the password from stdin", takes no
        # operand, and the next word IS the command: `echo pw | sudo -S <pm>
        # install <pkg>` is a standard idiom, and bailing on it skipped a real
        # install.
        if [[ "$_vs_wrapper" == "env" ]] &&
           { [[ "$seg" =~ ^(-S|--split-string)([=[:space:]]|$) ]] ||
             [[ "$seg" =~ ^-S[^[:space:]] ]]; }; then
          printf '%s' "$1"; return
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
    seg=$(_strip_cmd_prefix "$1")
  fi
  if [[ "$seg" =~ ^(npm|pnpm|yarn|bun)[[:space:]]+(add|install|i)[[:space:]]+(.*) ]]; then
    _emit_npm_packages "${BASH_REMATCH[3]}"; return
  fi
  if [[ "$seg" =~ ^pip3?[[:space:]]+install[[:space:]]+(.*) ]]; then
    _emit_pep508 "${BASH_REMATCH[1]}"; return
  fi
  if [[ "$seg" =~ ^poetry[[:space:]]+add[[:space:]]+(.*) ]]; then
    _emit_poetry "${BASH_REMATCH[1]}"; return
  fi
  if [[ "$seg" =~ ^uv[[:space:]]+(add|pip[[:space:]]+install)[[:space:]]+(.*) ]]; then
    _emit_pep508 "${BASH_REMATCH[2]}"; return
  fi
  if [[ "$seg" =~ ^cargo[[:space:]]+add[[:space:]]+(.*) ]]; then
    _emit_cargo_add "${BASH_REMATCH[1]}"; return
  fi
  if [[ "$seg" =~ ^dotnet[[:space:]]+add[[:space:]]+package[[:space:]]+(.*) ]]; then
    _emit_dotnet_add "${BASH_REMATCH[1]}"; return
  fi
}

_emit_npm_packages() {
  local rest="$1" tok
  for tok in $rest; do
    [[ "$tok" == -* ]] && continue
    if [[ "$tok" == @*/* ]]; then
      if [[ "$tok" =~ ^(@[^/]+/[^@]+)(@(.+))?$ ]]; then
        printf 'npm\t%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[3]}"
      fi
    elif [[ "$tok" == *@* ]]; then
      printf 'npm\t%s\t%s\n' "${tok%@*}" "${tok##*@}"
    else
      printf 'npm\t%s\t%s\n' "$tok" ""
    fi
  done
}

_emit_pep508() {
  local rest="$1" tok
  for tok in $rest; do
    [[ "$tok" == -* ]] && continue
    if [[ "$tok" =~ ^([A-Za-z0-9][A-Za-z0-9._-]*)(==|~=|\>=|\<=|\>|\<|!=)([A-Za-z0-9][A-Za-z0-9._*+-]*) ]]; then
      printf 'pip\t%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[3]}"
    else
      printf 'pip\t%s\t%s\n' "$tok" ""
    fi
  done
}

_emit_poetry() {
  local rest="$1" tok
  for tok in $rest; do
    [[ "$tok" == -* ]] && continue
    if [[ "$tok" == *@* ]]; then
      local p="${tok%@*}" v="${tok##*@}"
      v="${v#[v^~>=]}"
      v="${v#=}"
      printf 'pip\t%s\t%s\n' "$p" "$v"
    else
      printf 'pip\t%s\t%s\n' "$tok" ""
    fi
  done
}

_emit_cargo_add() {
  local rest="$1" tok name="" ver=""
  for tok in $rest; do
    if [[ "$tok" == "--vers" || "$tok" == "--version" ]]; then continue; fi
    if [[ "$tok" == --vers=* || "$tok" == --version=* ]]; then ver="${tok#*=}"; continue; fi
    [[ "$tok" == -* ]] && continue
    if [[ -z "$name" ]]; then
      if [[ "$tok" == *@* ]]; then name="${tok%@*}"; ver="${tok##*@}"; else name="$tok"; fi
    fi
  done
  [[ -n "$name" ]] && printf 'cargo\t%s\t%s\n' "$name" "$ver"
}

_emit_dotnet_add() {
  local rest="$1" tok name="" ver="" take_ver=0
  for tok in $rest; do
    if [[ "$take_ver" -eq 1 ]]; then ver="$tok"; take_ver=0; continue; fi
    case "$tok" in
      --version|-v) take_ver=1 ;;
      -*) ;;
      *) [[ -z "$name" ]] && name="$tok" ;;
    esac
  done
  [[ -n "$name" ]] && printf 'csproj\t%s\t%s\n' "$name" "$ver"
}