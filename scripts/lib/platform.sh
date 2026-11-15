#!/usr/bin/env bash
# platform.sh — tool-name normalization across agent platforms.
# Source from any hook script right after options.sh, then run
#   tool_name=$(normalize_tool_name "$tool_name")
# immediately after extracting tool_name from the hook payload.
#
# Canonical names are the Claude Code ones (Bash, Edit, Write, MultiEdit).
# Anything unrecognized passes through unchanged.

if [[ -z "${_VS_PLATFORM_LOADED:-}" ]]; then
  _VS_PLATFORM_LOADED=1

  normalize_tool_name() {
    local name="${1:-}"
    case "$name" in
      # Gemini: run_shell_command; Codex: exec_command; VS Code Copilot: runTerminalCommand
      run_shell_command|exec_command|runTerminalCommand|terminal) echo "Bash" ;;
      # Gemini: write_file; VS Code Copilot: createFile
      write_file|createFile|save_file) echo "Write" ;;
      # Gemini: replace; VS Code Copilot: editFiles
      replace|editFiles|edit_file) echo "Edit" ;;
      [Mm][Uu][Ll][Tt][Ii][Ee][Dd][Ii][Tt]) echo "MultiEdit" ;;
      *) printf '%s\n' "$name" ;;
    esac
  }
fi
