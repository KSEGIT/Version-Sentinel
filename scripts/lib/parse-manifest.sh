#!/usr/bin/env bash
# parse-manifest.sh — per-ecosystem manifest parsers.
# Each parser prints TAB-separated "pkg\tversion" lines, one per dependency.
# Version prefixes (^ ~ >= <= = v) are stripped.
# Local/git/workspace refs are skipped.
# Missing/invalid file → empty output, exit 0 (fail-open).

VS_UNPINNED_VERSION="__version_sentinel_unpinned__"

_strip_version_prefix() {
  sed -E 's/^[v^~><= ]+//' <<< "$1"
}

_is_non_registry_version() {
  local raw="$1"
  case "$raw" in
    file:*|git+*|git:*|git@*|github:*|gitlab:*|bitbucket:*|workspace:*|link:*|portal:*|npm:*|http://*|https://*|ssh://*|./*|../*|/*|*/*) return 0 ;;
  esac
  return 1
}

_npm_manifest_version() {
  local raw="$1"
  _is_non_registry_version "$raw" && return
  case "$raw" in
    ""|"*"|latest|next) printf '%s' "$VS_UNPINNED_VERSION"; return ;;
  esac
  # A dist-tag such as beta or canary is a floating registry selector.
  if [[ ! "$raw" =~ ^[v=\^~\<\>]*[0-9] ]]; then
    printf '%s' "$VS_UNPINNED_VERSION"
  else
    _strip_version_prefix "$raw"
  fi
}

_emit_npm_manifest_dependency() {
  local pkg="$1" raw="$2" target ver
  if [[ "$raw" == npm:* ]]; then
    target="${raw#npm:}"
    if [[ "$target" == @*/* ]]; then
      if [[ "$target" =~ ^(@[^/]+/[^@]+)(@(.+))?$ ]]; then
        pkg="${BASH_REMATCH[1]}"
        ver=$(_npm_manifest_version "${BASH_REMATCH[3]}")
      else
        return
      fi
    elif [[ "$target" == *@* ]]; then
      pkg="${target%@*}"
      ver=$(_npm_manifest_version "${target##*@}")
    elif [[ "$target" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
      pkg="$target"
      ver="$VS_UNPINNED_VERSION"
    else
      return
    fi
  else
    ver=$(_npm_manifest_version "$raw")
  fi
  [[ -z "$ver" ]] && return
  [[ "$ver" =~ [[:space:]] ]] && return
  printf '%s\t%s\n' "$pkg" "$ver"
}

parse_npm() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  jq -r '[.dependencies, .devDependencies, .peerDependencies, .optionalDependencies]
         | map(select(. != null))[] | to_entries[] | "\(.key)\t\(.value)"' \
    "$file" 2>/dev/null | while IFS=$'\t' read -r pkg raw; do
      [[ -z "$pkg" ]] && continue
      _emit_npm_manifest_dependency "$pkg" "$raw"
    done
}

parse_pip() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    case "$line" in
      -*|*://*|./*|../*|/*) continue ;;
    esac
    line="${line%%;*}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ "$line" == *@* && "$line" != *==* ]] && continue
    if [[ "$line" =~ ^([A-Za-z0-9][A-Za-z0-9._-]*)(\[[^]]+\])?[[:space:]]*(==|~=|\>=|\<=|\>|\<|!=)[[:space:]]*([A-Za-z0-9][A-Za-z0-9._*+-]*) ]]; then
      local pkg="${BASH_REMATCH[1]}" ver="${BASH_REMATCH[4]}"
      [[ "$ver" == "*" ]] && ver="$VS_UNPINNED_VERSION"
      printf '%s\t%s\n' "$pkg" "$ver"
    elif [[ "$line" =~ ^([A-Za-z0-9][A-Za-z0-9._-]*)(\[[^]]+\])?[[:space:]]*$ ]]; then
      printf '%s\t%s\n' "${BASH_REMATCH[1]}" "$VS_UNPINNED_VERSION"
    fi
  done < "$file"
}

parse_pyproject() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  python3 - "$file" "$VS_UNPINNED_VERSION" <<'PY' 2>/dev/null | tr -d '\r'
import tomllib, sys, re
with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)
UNPINNED = sys.argv[2]

VER_RE = re.compile(r"(?:==|~=|>=|<=|>|<|!=|\^|~)?\s*([A-Za-z0-9][A-Za-z0-9._*+-]*)")

def emit(name, raw):
    name = name.strip()
    raw = (raw or "").strip()
    if ";" in raw: raw = raw.split(";", 1)[0].strip()
    if not raw or raw in ("*", "latest", "next"):
        print(f"{name}\t{UNPINNED}")
        return
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
        elif isinstance(spec, dict):
            if any(k in spec for k in ("path", "git", "url")): continue
            emit(name, spec.get("version", ""))

poetry_deps(data.get("tool", {}).get("poetry", {}).get("dependencies"))
for _g, gd in (data.get("tool", {}).get("poetry", {}).get("group", {}) or {}).items():
    poetry_deps(gd.get("dependencies"))

for s in (data.get("tool", {}).get("uv", {}).get("dev-dependencies") or []): pep508(s)
PY
}

parse_cargo() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  python3 - "$file" "$VS_UNPINNED_VERSION" <<'PY' 2>/dev/null | tr -d '\r'
import tomllib, sys
with open(sys.argv[1], "rb") as f:
    data = tomllib.load(f)
UNPINNED = sys.argv[2]

def walk(section):
    for name, spec in (section or {}).items():
        if isinstance(spec, str):
            ver = spec.lstrip('^~v= ')
            print(f"{name}\t{UNPINNED if not ver or ver == '*' else ver}")
        elif isinstance(spec, dict):
            if "path" in spec or "git" in spec or spec.get("workspace") is True:
                continue
            ver = spec.get("version")
            if isinstance(ver, str):
                ver = ver.lstrip('^~v= ')
                print(f"{name}\t{UNPINNED if not ver or ver == '*' else ver}")
            else:
                print(f"{name}\t{UNPINNED}")

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
      # An omitted Version may be supplied by NuGet Central Package
      # Management in an ancestor Directory.Packages.props. The post-image
      # parser cannot inspect that file safely, so keep this out of scope.
      continue
    fi
    [[ -z "$ver" || "$ver" == *"*"* ]] && ver="$VS_UNPINNED_VERSION"
    printf '%s\t%s\n' "$inc" "$ver"
  done
}

ecosystem_for_path() {
  local path="$1"
  local base
  base=$(basename "$path")
  case "$base" in
    package.json) echo "npm" ;;
    requirements*.txt|constraints*.txt) echo "pip" ;;
    pyproject.toml) echo "pyproject" ;;
    Cargo.toml) echo "cargo" ;;
    *.csproj|*.fsproj|*.vbproj) echo "csproj" ;;
    *) echo "" ;;
  esac
}

parse_manifest_by_path() {
  local path="$1"
  local eco
  eco=$(ecosystem_for_path "$path")
  case "$eco" in
    npm) parse_npm "$path" ;;
    pip) parse_pip "$path" ;;
    pyproject) parse_pyproject "$path" ;;
    cargo) parse_cargo "$path" ;;
    csproj) parse_csproj "$path" ;;
    *) return 0 ;;
  esac
}

diff_manifest_sets() {
  local pre="$1" post="$2"
  local tmp_pre tmp_post
  tmp_pre=$(mktemp); tmp_post=$(mktemp)
  printf '%s\n' "$pre" | sort -u > "$tmp_pre"
  printf '%s\n' "$post" | sort -u > "$tmp_post"
  while IFS=$'\t' read -r pkg ver; do
    [[ -z "$pkg" ]] && continue
    if awk -F '\t' -v p="$pkg" -v v="$ver" \
      '$1==p && $2==v { found=1 } END { exit(found ? 0 : 1) }' "$tmp_pre"; then
      continue
    fi
    if awk -F '\t' -v p="$pkg" '$1==p { found=1 } END { exit(found ? 0 : 1) }' "$tmp_pre"; then
      printf 'changed\t%s\t%s\n' "$pkg" "$ver"
    else
      printf 'added\t%s\t%s\n' "$pkg" "$ver"
    fi
  done < "$tmp_post"
  rm -f "$tmp_pre" "$tmp_post"
}
