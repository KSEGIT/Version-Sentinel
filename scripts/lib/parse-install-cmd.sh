#!/usr/bin/env bash
# parse_install_cmd <bash-command-string>
# Prints TAB-separated "ecosystem\tpkg\tversion" lines.

parse_install_cmd() {
  local cmd="$1"
  local segment
  local IFS=$'\n'
  for segment in $(printf '%s\n' "$cmd" | tr ';&|' '\n'); do
    segment="${segment#"${segment%%[![:space:]]*}"}"
    [[ -z "$segment" ]] && continue
    _parse_install_segment "$segment"
  done
}

_parse_install_segment() {
  local seg="$1"
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