#!/usr/bin/env bash
# parse-manifest.sh — per-ecosystem manifest parsers.
# Each parser prints TAB-separated "pkg\tversion" lines, one per dependency.
# Version prefixes (^ ~ >= <= = v) are stripped.
# Local/git/workspace refs are skipped.
# Missing/invalid file → empty output, exit 0 (fail-open).

_strip_version_prefix() {
  sed -E 's/^[v^~><= ]+//' <<< "$1"
}

_is_registry_version() {
  local raw="$1"
  case "$raw" in
    file:*|git+*|git:*|github:*|workspace:*|link:*|portal:*|npm:*|"*"|""|latest|next) return 1 ;;
  esac
  return 0
}

parse_npm() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  jq -r '[.dependencies, .devDependencies, .peerDependencies, .optionalDependencies]
         | map(select(. != null)) | add // {} | to_entries[] | "\(.key)\t\(.value)"' \
    "$file" 2>/dev/null | while IFS=$'\t' read -r pkg raw; do
      [[ -z "$pkg" ]] && continue
      _is_registry_version "$raw" || continue
      local ver
      ver=$(_strip_version_prefix "$raw")
      [[ "$ver" =~ [[:space:]] ]] && continue
      printf '%s\t%s\n' "$pkg" "$ver"
    done
}

parse_pip() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    case "$line" in
      -*|*://*|./*|../*|/*) continue ;;
    esac
    line="${line%%;*}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ "$line" == *@* && "$line" != *==* ]] && continue
    if [[ "$line" =~ ^([A-Za-z0-9][A-Za-z0-9._-]*)[[:space:]]*(==|~=|\>=|\<=|\>|\<|!=)[[:space:]]*([A-Za-z0-9][A-Za-z0-9._*+-]*) ]]; then
      local pkg="${BASH_REMATCH[1]}" ver="${BASH_REMATCH[3]}"
      printf '%s\t%s\n' "$pkg" "$ver"
    fi
  done < "$file"
}

parse_pyproject() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  python3 - "$file" <<'PY' 2>/dev/null | tr -d '\r'
import tomllib, sys, re
with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)

VER_RE = re.compile(r"(?:==|~=|>=|<=|>|<|!=|\^|~)?\s*([A-Za-z0-9][A-Za-z0-9._*+-]*)")

def emit(name, raw):
    name = name.strip()
    raw = (raw or "").strip()
    if ";" in raw: raw = raw.split(";", 1)[0].strip()
    if not raw or raw in ("*", "latest"): return
    if raw.startswith(("file:", "git+", "http://", "https://", "./", "../", "/")): return
    if " @ " in raw: return
    m = VER_RE.match(raw)
    if not m: return
    ver = m.group(1)
    if " " in ver: return
    print(f"{name}\t{ver}")

def pep508(spec):
    spec = spec.split(";", 1)[0].strip()
    m = re.match(r"([A-Za-z0-9][A-Za-z0-9._-]*)(?:\[[^\]]*\])?\s*(.*)", spec)
    if m: emit(m.group(1), m.group(2))

for s in (data.get("project", {}).get("dependencies") or []): pep508(s)
for _g, specs in (data.get("project", {}).get("optional-dependencies") or {}).items():
    for s in specs: pep508(s)

def poetry_deps(d):
    for name, spec in (d or {}).items():
        if name == "python": continue
        if isinstance(spec, str): emit(name, spec)
        elif isinstance(spec, dict) and "version" in spec: emit(name, spec["version"])

poetry_deps(data.get("tool", {}).get("poetry", {}).get("dependencies"))
for _g, gd in (data.get("tool", {}).get("poetry", {}).get("group", {}) or {}).items():
    poetry_deps(gd.get("dependencies"))

for s in (data.get("tool", {}).get("uv", {}).get("dev-dependencies") or []): pep508(s)
PY
}

parse_cargo() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  python3 - "$file" <<'PY' 2>/dev/null | tr -d '\r'
import tomllib, sys
with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)

def walk(section):
    for name, spec in (section or {}).items():
        if isinstance(spec, str):
            print(f"{name}\t{spec.lstrip('^~v= ')}")
        elif isinstance(spec, dict):
            if "path" in spec or "git" in spec:
                continue
            ver = spec.get("version")
            if isinstance(ver, str):
                print(f"{name}\t{ver.lstrip('^~v= ')}")

walk(data.get("dependencies"))
walk(data.get("dev-dependencies"))
walk(data.get("build-dependencies"))
PY
}

parse_csproj() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  grep -oE '<PackageReference[^/>]*(/>|>)' "$file" 2>/dev/null | while IFS= read -r tag; do
    local inc ver
    if [[ "$tag" =~ Include=\"([^\"]+)\" ]]; then
      inc="${BASH_REMATCH[1]}"
    else
      continue
    fi
    if [[ "$tag" =~ Version=\"([^\"]+)\" ]]; then
      ver="${BASH_REMATCH[1]}"
    else
      continue
    fi
    printf '%s\t%s\n' "$inc" "$ver"
  done
}
