#!/usr/bin/env bash
#
# Popcorn XP — Claude Code plugin layout checks
#
# Grounded in research/official/claude/plugin.md:
# - File locations reference (agents/, skills/, hooks/hooks.json at plugin root;
#   only plugin.json inside .claude-plugin/)
# - Plugin manifest schema (name required if manifest present; version optional)
# - Hook commands should use ${CLAUDE_PLUGIN_ROOT} for bundled paths
# - Optional: claude plugin validate <path> (marketplace + plugin roots)
#

set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_ROOT="$REPO_ROOT/platforms/claude/subagent"
MARKETPLACE_JSON="$REPO_ROOT/.claude-plugin/marketplace.json"
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"
PLUGIN_META_DIR="$PLUGIN_ROOT/.claude-plugin"
HOOKS_JSON="$PLUGIN_ROOT/hooks/hooks.json"
RESULTS_FILE="$SCRIPT_DIR/test-results.json"
DOC_REF="research/official/claude/plugin.md"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0
WARNINGS=0

echo '{"tests": [], "timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"}' > "$RESULTS_FILE"

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; PASSED=$((PASSED + 1)); }
log_failure() { echo -e "${RED}❌ $1${NC}"; FAILED=$((FAILED + 1)); }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; WARNINGS=$((WARNINGS + 1)); }

run_limited_60() {
  if command -v timeout &>/dev/null; then
    timeout 60 "$@"
  elif command -v gtimeout &>/dev/null; then
    gtimeout 60 "$@"
  else
    "$@"
  fi
}

add_result() {
  local name="$1" status="$2" message="$3"
  if command -v jq &>/dev/null; then
    local temp_file
    temp_file="$(mktemp)"
    jq --arg name "$name" --arg status "$status" --arg message "$message" \
      '.tests += [{"name": $name, "status": $status, "message": $message}]' \
      "$RESULTS_FILE" >"$temp_file" && mv "$temp_file" "$RESULTS_FILE"
  fi
}

# First YAML frontmatter block must include name: and description: (skills reference)
skill_frontmatter_ok() {
  local f="$1"
  local block
  block=$(awk '/^---$/{c++; next} c==1{print} c>=2{exit}' "$f" 2>/dev/null)
  echo "$block" | grep -q '^name:' && echo "$block" | grep -q '^description:'
}

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Popcorn XP — Claude plugin harness${NC}"
echo -e "${BLUE}  ($DOC_REF)${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
log_info "REPO_ROOT=$REPO_ROOT"
log_info "PLUGIN_ROOT=$PLUGIN_ROOT"
echo ""

# --- Test 1: Repo marketplace file ---
log_info "Test 1: .claude-plugin/marketplace.json (repo root)..."

if [[ -f "$MARKETPLACE_JSON" ]]; then
  log_success "Marketplace file exists"
  add_result "marketplace_exists" "passed" "Found .claude-plugin/marketplace.json"
  if command -v jq &>/dev/null; then
    if jq empty "$MARKETPLACE_JSON" 2>/dev/null; then
      log_success "Marketplace JSON is valid"
      add_result "marketplace_json" "passed" "Valid JSON"
      MP_NAME=$(jq -r '.name // empty' "$MARKETPLACE_JSON")
      SRC=$(jq -r '.plugins[0].source // empty' "$MARKETPLACE_JSON")
      if [[ -n "$MP_NAME" ]]; then
        log_success "Marketplace name: $MP_NAME"
        add_result "marketplace_name" "passed" "name=$MP_NAME"
      else
        log_failure "Marketplace .name missing"
        add_result "marketplace_name" "failed" "Missing .name"
      fi
      if [[ -n "$SRC" ]]; then
        case "$SRC" in
          ./*) RESOLVED="$REPO_ROOT/${SRC#./}" ;;
          /*) RESOLVED="$SRC" ;;
          *) RESOLVED="$REPO_ROOT/$SRC" ;;
        esac
        if [[ -d "$RESOLVED" ]]; then
          log_success "plugins[0].source resolves: $SRC -> $RESOLVED"
          add_result "marketplace_source" "passed" "source exists"
        else
          log_failure "plugins[0].source path missing: $SRC (resolved: $RESOLVED)"
          add_result "marketplace_source" "failed" "Directory not found"
        fi
      else
        log_failure "plugins[0].source missing"
        add_result "marketplace_source" "failed" "Empty source"
      fi
    else
      log_failure "Invalid marketplace JSON"
      add_result "marketplace_json" "failed" "jq parse error"
    fi
  else
    log_warning "jq not installed; skipping marketplace JSON checks"
    add_result "marketplace_json" "skipped" "no jq"
  fi
else
  log_failure "Missing $MARKETPLACE_JSON"
  add_result "marketplace_exists" "failed" "File not found"
fi

# --- Test 2: plugin.json (manifest: name required; version optional) ---
log_info "Test 2: .claude-plugin/plugin.json under plugin root (manifest schema)..."

if [[ -f "$PLUGIN_JSON" ]]; then
  log_success "plugin.json exists"
  add_result "plugin_json_exists" "passed" "Found manifest"
  if command -v jq &>/dev/null; then
    if jq empty "$PLUGIN_JSON" 2>/dev/null; then
      log_success "plugin.json is valid JSON"
      add_result "plugin_json_valid" "passed" "Valid JSON"
      PN=$(jq -r '.name // empty' "$PLUGIN_JSON")
      PV=$(jq -r '.version // empty' "$PLUGIN_JSON")
      if [[ -n "$PN" ]]; then
        log_success "Plugin name: $PN (required when manifest is present)"
        add_result "plugin_name" "passed" "name=$PN"
        if [[ "$PN" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
          log_success "Plugin name matches kebab-case pattern (plugin.md)"
          add_result "plugin_name_kebab" "passed" "kebab-case"
        else
          log_failure "Plugin name should be kebab-case (no spaces): $PN"
          add_result "plugin_name_kebab" "failed" "Bad pattern"
        fi
      else
        log_failure "plugin.json .name missing (required if manifest present)"
        add_result "plugin_name" "failed" "Missing name"
      fi
      if [[ -n "$PV" ]]; then
        log_success "Plugin version: $PV"
        add_result "plugin_version" "passed" "version=$PV"
      else
        log_warning "No version in plugin.json (optional; marketplace may supply per plugin.md)"
        add_result "plugin_version" "warning" "Omitted"
      fi
      # Component path fields must be relative and start with ./ (plugin.md — Path behavior rules)
      BAD_PATH=0
      while IFS= read -r p; do
        [[ -z "$p" || "$p" == "null" ]] && continue
        if [[ "$p" != ./* ]]; then
          log_failure "plugin.json path must start with ./ (plugin.md): $p"
          BAD_PATH=$((BAD_PATH + 1))
        fi
      done < <(jq -r '
        [.agents?, .skills?, .hooks?, .commands?, .outputStyles?]
        | flatten
        | map(select(type == "string"))
        | .[]
      ' "$PLUGIN_JSON" 2>/dev/null)
      if [[ "$BAD_PATH" -eq 0 ]]; then
        log_success "No invalid component paths in plugin.json (or none declared — defaults apply)"
        add_result "plugin_paths" "passed" "./ prefix OK"
      else
        add_result "plugin_paths" "failed" "$BAD_PATH bad path(s)"
      fi
    else
      log_failure "plugin.json invalid JSON"
      add_result "plugin_json_valid" "failed" "Parse error"
    fi
  else
    log_warning "jq not installed; skipping plugin.json validation"
    add_result "plugin_json_valid" "skipped" "no jq"
  fi
else
  log_failure "Missing $PLUGIN_JSON (optional in spec, but required for stable popcorn-xp id)"
  add_result "plugin_json_exists" "failed" "Not found"
fi

# --- Test 3: Only plugin.json lives under .claude-plugin/ (plugin.md — Warning box) ---
log_info "Test 3: .claude-plugin/ contains only plugin.json..."

if [[ -d "$PLUGIN_META_DIR" ]]; then
  EXTRA=$(find "$PLUGIN_META_DIR" -mindepth 1 -maxdepth 1 ! -name 'plugin.json' 2>/dev/null | wc -l | tr -d ' ')
  if [[ "${EXTRA:-0}" -eq 0 ]]; then
    log_success "Only plugin.json under .claude-plugin/ (agents/skills/hooks stay at plugin root)"
    add_result "plugin_meta_dir" "passed" "layout OK"
  else
    log_failure "Unexpected files under .claude-plugin/ (plugin.md: only manifest belongs there)"
    find "$PLUGIN_META_DIR" -mindepth 1 -maxdepth 1 ! -name 'plugin.json' 2>/dev/null
    add_result "plugin_meta_dir" "failed" "extra entries"
  fi
else
  log_failure "Missing directory: $PLUGIN_META_DIR"
  add_result "plugin_meta_dir" "failed" "no .claude-plugin"
fi

# --- Test 4: agents/ default location ---
log_info "Test 4: agents/*.md (default location)..."

AGENTS_DIR="$PLUGIN_ROOT/agents"
if [[ -d "$AGENTS_DIR" ]]; then
  AGENT_COUNT=$(find "$AGENTS_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  if [[ "${AGENT_COUNT:-0}" -gt 0 ]]; then
    log_success "Agent definitions: $AGENT_COUNT markdown file(s)"
    add_result "agents" "passed" "count=$AGENT_COUNT"
  else
    log_failure "No .md files in $AGENTS_DIR"
    add_result "agents" "failed" "Empty agents/"
  fi
else
  log_failure "Missing directory: $AGENTS_DIR"
  add_result "agents" "failed" "agents/ missing"
fi

# --- Test 5: skills/<name>/SKILL.md + frontmatter ---
log_info "Test 5: skills/<name>/SKILL.md (plugin.md skill structure)..."

SKILLS_DIR="$PLUGIN_ROOT/skills"
SKILL_COUNT=0
SKILL_FM_FAIL=0
if [[ -d "$SKILLS_DIR" ]]; then
  while IFS= read -r -d '' skill_md; do
    SKILL_COUNT=$((SKILL_COUNT + 1))
    if skill_frontmatter_ok "$skill_md"; then
      :
    else
      log_failure "SKILL.md missing name/description in frontmatter: $skill_md"
      SKILL_FM_FAIL=$((SKILL_FM_FAIL + 1))
    fi
  done < <(find "$SKILLS_DIR" -mindepth 2 -maxdepth 2 -type f -name 'SKILL.md' -print0 2>/dev/null)
  if [[ "$SKILL_COUNT" -gt 0 && "$SKILL_FM_FAIL" -eq 0 ]]; then
    log_success "Skills with SKILL.md: $SKILL_COUNT; frontmatter has name + description"
    add_result "skills" "passed" "count=$SKILL_COUNT"
  elif [[ "$SKILL_COUNT" -eq 0 ]]; then
    log_failure "No skills/*/SKILL.md under $SKILLS_DIR"
    add_result "skills" "failed" "No SKILL.md"
  else
    add_result "skills" "failed" "frontmatter issues"
  fi
else
  log_failure "Missing directory: $SKILLS_DIR"
  add_result "skills" "failed" "skills/ missing"
fi

# --- Test 6: hooks/hooks.json — shape, ${CLAUDE_PLUGIN_ROOT}, scripts exist + executable ---
log_info "Test 6: hooks/hooks.json + bundled scripts (plugin.md — Hooks, env vars)..."

if [[ -f "$HOOKS_JSON" ]]; then
  log_success "hooks.json exists at hooks/hooks.json"
  add_result "hooks_json_exists" "passed" "Found"
  if command -v jq &>/dev/null; then
    if jq -e '.hooks | type == "object"' "$HOOKS_JSON" >/dev/null 2>&1; then
      log_success "Top-level .hooks object present"
      add_result "hooks_json_shape" "passed" "Valid shape"
    else
      log_failure "hooks.json missing .hooks object"
      add_result "hooks_json_shape" "failed" "Bad shape"
    fi
    HOOK_CMD_FAIL=0
    HOOK_REL_FAIL=0
    HOOK_X_FAIL=0
    while IFS= read -r cmd; do
      [[ -z "$cmd" ]] && continue
      if [[ "$cmd" != *'${CLAUDE_PLUGIN_ROOT}'* ]]; then
        log_failure "Hook command must use \${CLAUDE_PLUGIN_ROOT} for bundled paths (plugin.md): ${cmd:0:120}..."
        HOOK_CMD_FAIL=$((HOOK_CMD_FAIL + 1))
        continue
      fi
      rel=$(echo "$cmd" | sed -n 's/.*\${CLAUDE_PLUGIN_ROOT}\///p')
      [[ -z "$rel" ]] && continue
      rel="${rel%% *}"
      target="$PLUGIN_ROOT/$rel"
      if [[ ! -f "$target" ]]; then
        log_failure "Hook script missing: $target"
        HOOK_REL_FAIL=$((HOOK_REL_FAIL + 1))
      elif [[ ! -x "$target" ]]; then
        log_warning "Hook script not executable (plugin.md troubleshooting): $rel"
        HOOK_X_FAIL=$((HOOK_X_FAIL + 1))
      fi
    done < <(jq -r '[.hooks | to_entries[] | .value[] | .hooks[]? | select(.type == "command") | .command] | unique | .[]' "$HOOKS_JSON" 2>/dev/null)
    if [[ "$HOOK_CMD_FAIL" -eq 0 && "$HOOK_REL_FAIL" -eq 0 ]]; then
      log_success "All command hooks use \${CLAUDE_PLUGIN_ROOT} and resolve to existing files"
      add_result "hooks_commands" "passed" "CLAUDE_PLUGIN_ROOT + files"
    else
      add_result "hooks_commands" "failed" "cmd=$HOOK_CMD_FAIL missing=$HOOK_REL_FAIL"
    fi
    if [[ "$HOOK_X_FAIL" -gt 0 ]]; then
      add_result "hooks_executable" "warning" "$HOOK_X_FAIL not executable"
    else
      log_success "Referenced hook scripts are executable"
      add_result "hooks_executable" "passed" "chmod +x OK"
    fi
  fi
  HOOK_SCRIPT_COUNT=$(find "$PLUGIN_ROOT/hooks/scripts" -type f -name '*.sh' 2>/dev/null | wc -l | tr -d ' ')
  if [[ "${HOOK_SCRIPT_COUNT:-0}" -gt 0 ]]; then
    log_success "hooks/scripts/*.sh count: $HOOK_SCRIPT_COUNT"
    add_result "hook_scripts" "passed" "count=$HOOK_SCRIPT_COUNT"
  else
    log_failure "No .sh under $PLUGIN_ROOT/hooks/scripts"
    add_result "hook_scripts" "failed" "No scripts"
  fi
else
  log_failure "Missing $HOOKS_JSON"
  add_result "hooks_json_exists" "failed" "Not found"
fi

# --- Test 7: Official claude plugin validate (plugin.md — Debugging) ---
log_info "Test 7: claude plugin validate (official CLI)..."

if command -v claude &>/dev/null; then
  VAL_OUT=$(claude plugin validate "$PLUGIN_ROOT" 2>&1)
  VAL_EC=$?
  if [[ $VAL_EC -eq 0 ]]; then
    log_success "claude plugin validate \"$PLUGIN_ROOT\" exited 0"
    add_result "claude_validate_plugin" "passed" "OK"
    if echo "$VAL_OUT" | grep -qi warning; then
      log_warning "Validate reported warnings (version/author etc. per upstream — see output above)"
      echo "$VAL_OUT" | head -15
      add_result "claude_validate_plugin_warnings" "warning" "see log"
    fi
  else
    log_failure "claude plugin validate plugin root failed (ec=$VAL_EC)"
    echo "$VAL_OUT" | head -20
    add_result "claude_validate_plugin" "failed" "exit $VAL_EC"
  fi

  VALM_OUT=$(claude plugin validate "$REPO_ROOT" 2>&1)
  VALM_EC=$?
  if [[ $VALM_EC -eq 0 ]]; then
    log_success "claude plugin validate \"$REPO_ROOT\" (marketplace) exited 0"
    add_result "claude_validate_marketplace" "passed" "OK"
    if echo "$VALM_OUT" | grep -qi warning; then
      log_warning "Marketplace validate warnings (e.g. description)"
      echo "$VALM_OUT" | head -10
      add_result "claude_validate_marketplace_warnings" "warning" "see log"
    fi
  else
    log_failure "claude plugin validate repo root failed (ec=$VALM_EC)"
    echo "$VALM_OUT" | head -20
    add_result "claude_validate_marketplace" "failed" "exit $VALM_EC"
  fi
else
  log_warning "claude CLI not in PATH; skipping claude plugin validate"
  add_result "claude_validate_plugin" "skipped" "no CLI"
  add_result "claude_validate_marketplace" "skipped" "no CLI"
fi

# --- Test 8: Shared runtime (outside plugin cache — document dependency) ---
log_info "Test 8: shared/runtime/bin/session (runtime dependency outside plugin root)..."

SESSION_BIN="$REPO_ROOT/shared/runtime/bin/session"
if [[ -f "$SESSION_BIN" ]] && [[ -x "$SESSION_BIN" ]]; then
  log_success "Session helper present (plugin.md: external deps live outside copied cache)"
  add_result "session_bin" "passed" "shared/runtime/bin/session"
else
  log_warning "shared/runtime/bin/session missing or not executable"
  add_result "session_bin" "warning" "needed at runtime"
fi

# --- Test 9–11: Optional Claude smoke (--plugin-dir = plugin root per install model) ---
log_info "Test 9: Claude Code CLI smoke (optional)..."

CLAUDE_AVAILABLE=false
if command -v claude &>/dev/null; then
  CLAUDE_VERSION=$(claude --version 2>/dev/null || echo "unknown")
  log_success "claude CLI: $CLAUDE_VERSION"
  add_result "claude_cli" "passed" "$CLAUDE_VERSION"
  CLAUDE_AVAILABLE=true
else
  log_warning "claude CLI not in PATH"
  add_result "claude_cli" "skipped" "Not installed"
fi

if [[ "$CLAUDE_AVAILABLE" == true ]]; then
  log_info "Test 10: Plugin load smoke (--plugin-dir=$PLUGIN_ROOT)..."

  LOAD_OUTPUT=$(run_limited_60 claude \
    --print "Reply with exactly PLUGIN_LOAD_OK and nothing else." \
    --max-turns 1 \
    --plugin-dir "$PLUGIN_ROOT" </dev/null 2>&1) || true

  if echo "$LOAD_OUTPUT" | grep -q "PLUGIN_LOAD_OK"; then
    log_success "Claude responded with PLUGIN_LOAD_OK"
    add_result "claude_plugin_load" "passed" "Smoke OK"
  else
    log_warning "Load smoke inconclusive"
    echo "$LOAD_OUTPUT" | head -8
    add_result "claude_plugin_load" "warning" "No PLUGIN_LOAD_OK"
  fi

  log_info "Test 11: Popcorn-xp context hint..."

  SK_OUT=$(run_limited_60 claude \
    --print "Name one skill or capability related to pair programming, popcorn-xp, or XP sessions if you see it. One short phrase only." \
    --max-turns 1 \
    --plugin-dir "$PLUGIN_ROOT" </dev/null 2>&1) || true

  if echo "$SK_OUT" | grep -qiE 'popcorn|pair|xp|advice|navigator|driver|scout|craftsman'; then
    log_success "Output mentions popcorn-xp–related terms"
    add_result "claude_plugin_context" "passed" "Keyword match"
  else
    log_warning "Could not confirm plugin context from model reply"
    add_result "claude_plugin_context" "warning" "No keyword match"
  fi
else
  add_result "claude_plugin_load" "skipped" "No CLI"
  add_result "claude_plugin_context" "skipped" "No CLI"
fi

# Summary
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${GREEN}Passed:   $PASSED${NC}"
echo -e "${RED}Failed:   $FAILED${NC}"
echo -e "${YELLOW}Warnings: $WARNINGS${NC}"
echo ""

if command -v jq &>/dev/null; then
  temp_file=$(mktemp)
  jq --arg passed "$PASSED" --arg failed "$FAILED" --arg warnings "$WARNINGS" \
    '. + {"summary": {"passed": ($passed|tonumber), "failed": ($failed|tonumber), "warnings": ($warnings|tonumber)}}' \
    "$RESULTS_FILE" >"$temp_file" && mv "$temp_file" "$RESULTS_FILE"
fi

log_info "Results: $RESULTS_FILE"

if [[ $FAILED -gt 0 ]]; then
  echo ""
  log_failure "Some checks failed."
  exit 1
fi

echo ""
log_success "No failing checks (warnings may still apply)."
exit 0
