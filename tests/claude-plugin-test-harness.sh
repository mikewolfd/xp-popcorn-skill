#!/usr/bin/env bash
#
# Popcorn XP — Claude Code plugin layout checks
#
# Grounded in research/official/claude/ (read alongside this script):
#   plugin.md        — manifest schema, path rules (./ prefix), layout, hooks location,
#                      ${CLAUDE_PLUGIN_ROOT} / ${CLAUDE_PLUGIN_DATA}, MCP/LSP paths, CLI validate
#   hooks-ref.md     — hook event names, matcher groups, handler types (command|http|prompt|agent)
#   hooks-anthro.md  — exit codes, hook I/O, matcher behavior (user guide; cross-check ref)
#   agents-anthro.md — plugin agents: required frontmatter; hooks/mcpServers/permissionMode unsupported
#   subagent.md      — same agent rules as agents-anthro (duplicate upstream doc)
#   skills-anthro.md — skills/*/SKILL.md; description recommended; name optional; !`cmd` preprocessing
#   agent-teams-anthro.md — TeammateIdle / Task* hooks context (experimental teams)
#   env.md           — CLAUDE_CODE_PLUGIN_* and hook-related env (reference only)
#   tools.md         — tool names for hook matchers (reference)
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
DOC_REF="research/official/claude/plugin.md (+ userConfig/channels) + hooks-ref.md + agents-anthro.md + skills-anthro.md (+ bang-backtick preprocessing)"

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

# skills-anthro.md: SKILL.md may omit name (directory name used); description is recommended.
skill_frontmatter_block() {
  awk '/^---$/{c++; next} c==1{print} c>=2{exit}' "$1" 2>/dev/null
}

skill_has_opening_frontmatter() {
  [[ -f "$1" ]] && head -1 "$1" | grep -q '^---$'
}

skill_description_present() {
  echo "$1" | grep -q '^description:'
}

# skills-anthro.md: name lowercase letters, numbers, hyphens, max 64 chars (when set)
skill_name_valid() {
  local block="$1"
  local n
  n=$(echo "$block" | grep '^name:' | head -1 | sed 's/^name:[[:space:]]*//;s/[[:space:]]*$//;s/^["'\'']//;s/["'\'']$//')
  [[ -z "$n" ]] && return 0
  [[ ${#n} -le 64 ]] && [[ "$n" =~ ^[a-z0-9-]+$ ]]
}

# skills-anthro.md — markdown body after closing ---; !`command` runs before Claude sees skill text
skill_body_after_frontmatter() {
  awk '/^---$/{c++; next} c>=2{print}' "$1" 2>/dev/null
}

skill_uses_bang_backtick() {
  skill_body_after_frontmatter "$1" | grep -q '!`'
}

# plugin.md — collect mcp server keys from inline object or .mcp.json path(s)
mcp_server_names_list() {
  local pj="$1"
  local root="$2"
  local t mp k
  t=$(jq -r 'if .mcpServers == null then "null" else .mcpServers | type end' "$pj" 2>/dev/null) || return 0
  case "$t" in
    object)
      jq -r '.mcpServers | keys[]' "$pj" 2>/dev/null
      ;;
    string)
      mp=$(jq -r '.mcpServers' "$pj" 2>/dev/null)
      [[ "$mp" == ./* ]] && mp="${root}/${mp#./}"
      [[ -f "$mp" ]] && jq -r 'keys[]' "$mp" 2>/dev/null
      ;;
    array)
      while IFS= read -r mp; do
        [[ "$mp" == ./* ]] && mp="${root}/${mp#./}"
        [[ -f "$mp" ]] && jq -r 'keys[]' "$mp" 2>/dev/null
      done < <(jq -r '.mcpServers[]? | select(type == "string")' "$pj" 2>/dev/null)
      ;;
  esac
}

# agents-anthro.md / plugin.md: plugin agents require name + description; no hooks/mcpServers/permissionMode
agent_frontmatter_block() {
  skill_frontmatter_block "$1"
}

# plugin.md + hooks-ref.md — lifecycle hook event keys under .hooks
hook_event_is_known() {
  case "$1" in
    SessionStart|UserPromptSubmit|PreToolUse|PermissionRequest|PermissionDenied|PostToolUse|PostToolUseFailure|Notification|SubagentStart|SubagentStop|TaskCreated|TaskCompleted|Stop|StopFailure|TeammateIdle|InstructionsLoaded|ConfigChange|CwdChanged|FileChanged|WorktreeCreate|WorktreeRemove|PreCompact|PostCompact|Elicitation|ElicitationResult|SessionEnd) return 0 ;;
    *) return 1 ;;
  esac
}

# hooks-ref.md — handler types
hook_handler_type_ok() {
  local t="${1:-command}"
  case "$t" in
    command|http|prompt|agent) return 0 ;;
    *) return 1 ;;
  esac
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
        [.agents?, .skills?, .hooks?, .commands?, .outputStyles?, .mcpServers?, .lspServers?]
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

      # userConfig (plugin.md — User configuration)
      UC_FAIL=0
      if jq -e '.userConfig != null' "$PLUGIN_JSON" >/dev/null 2>&1; then
        if ! jq -e '.userConfig | type == "object"' "$PLUGIN_JSON" >/dev/null 2>&1; then
          log_failure "plugin.json userConfig must be an object (plugin.md)"
          UC_FAIL=1
        else
          while IFS= read -r uerr; do
            [[ -z "$uerr" ]] && continue
            log_failure "plugin.json userConfig: $uerr (plugin.md)"
            UC_FAIL=1
          done < <(jq -r '
            .userConfig | to_entries[] |
            if (.key | test("^[A-Za-z_][A-Za-z0-9_]*$") | not) then "invalid key (must be identifier): \(.key)"
            elif (.value | type) != "object" then "\(.key): value must be object with description / optional sensitive"
            elif (.value | has("description") | not) then "\(.key): missing description"
            elif (.value.sensitive != null and (.value.sensitive | type) != "boolean") then "\(.key): sensitive must be boolean"
            else empty end
          ' "$PLUGIN_JSON")
        fi
        if [[ "$UC_FAIL" -eq 0 ]]; then
          log_success "plugin.json userConfig shape OK (plugin.md)"
          add_result "plugin_user_config" "passed" "valid"
        else
          add_result "plugin_user_config" "failed" "schema"
        fi
      else
        log_info "plugin.json: no userConfig (optional; plugin.md)"
        add_result "plugin_user_config" "skipped" "omitted"
      fi

      # channels (plugin.md — Channels)
      CH_FAIL=0
      if jq -e '.channels != null' "$PLUGIN_JSON" >/dev/null 2>&1; then
        if ! jq -e '.channels | type == "array"' "$PLUGIN_JSON" >/dev/null 2>&1; then
          log_failure "plugin.json channels must be an array (plugin.md)"
          CH_FAIL=1
        else
          _MCP_KEYS=()
          while IFS= read -r _k; do
            [[ -n "$_k" ]] && _MCP_KEYS+=("$_k")
          done < <(mcp_server_names_list "$PLUGIN_JSON" "$PLUGIN_ROOT" | sort -u)
          CH_MCP_UNRESOLVED=0
          ci=0
          while IFS= read -r ch; do
            srv=$(echo "$ch" | jq -r '.server // empty')
            if [[ -z "$srv" ]]; then
              log_failure "plugin.json channels[$ci] missing required server (plugin.md)"
              CH_FAIL=1
            elif [[ ${#_MCP_KEYS[@]} -gt 0 ]]; then
              found=0
              for mk in "${_MCP_KEYS[@]}"; do
                [[ "$mk" == "$srv" ]] && found=1 && break
              done
              if [[ "$found" -eq 0 ]]; then
                log_failure "plugin.json channels[$ci].server \"$srv\" must match an mcpServers key (plugin.md)"
                CH_FAIL=1
              fi
            else
              if [[ "$CH_MCP_UNRESOLVED" -eq 0 ]]; then
                log_warning "channels: could not resolve mcpServers keys (use inline mcpServers object or readable path); cannot verify channel.server (plugin.md)"
                CH_MCP_UNRESOLVED=1
              fi
            fi
            cuc=$(echo "$ch" | jq -c '.userConfig // null')
            if [[ "$cuc" != "null" ]]; then
              if ! echo "$cuc" | jq -e 'type == "object"' >/dev/null 2>&1; then
                log_failure "plugin.json channels[$ci].userConfig must be an object (plugin.md)"
                CH_FAIL=1
              else
                while IFS= read -r uerr; do
                  [[ -z "$uerr" ]] && continue
                  log_failure "plugin.json channels[$ci].userConfig: $uerr (plugin.md)"
                  CH_FAIL=1
                done < <(echo "$cuc" | jq -r '
                  to_entries[] |
                  if (.key | test("^[A-Za-z_][A-Za-z0-9_]*$") | not) then "invalid key: \(.key)"
                  elif (.value | type) != "object" then "\(.key): value must be object"
                  elif (.value | has("description") | not) then "\(.key): missing description"
                  elif (.value.sensitive != null and (.value.sensitive | type) != "boolean") then "\(.key): sensitive must be boolean"
                  else empty end
                ')
              fi
            fi
            ci=$((ci + 1))
          done < <(jq -c '.channels[]' "$PLUGIN_JSON")
        fi
        if [[ "$CH_FAIL" -eq 0 ]]; then
          log_success "plugin.json channels shape OK (plugin.md)"
          add_result "plugin_channels" "passed" "valid"
        else
          add_result "plugin_channels" "failed" "schema"
        fi
      else
        log_info "plugin.json: no channels (optional; plugin.md)"
        add_result "plugin_channels" "skipped" "omitted"
      fi
    else
      log_failure "plugin.json invalid JSON"
      add_result "plugin_json_valid" "failed" "Parse error"
      add_result "plugin_user_config" "skipped" "parse error"
      add_result "plugin_channels" "skipped" "parse error"
    fi
  else
    log_warning "jq not installed; skipping plugin.json validation"
    add_result "plugin_json_valid" "skipped" "no jq"
    add_result "plugin_user_config" "skipped" "no jq"
    add_result "plugin_channels" "skipped" "no jq"
  fi
else
  log_failure "Missing $PLUGIN_JSON (optional in spec, but required for stable popcorn-xp id)"
  add_result "plugin_json_exists" "failed" "Not found"
  add_result "plugin_user_config" "skipped" "no manifest"
  add_result "plugin_channels" "skipped" "no manifest"
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

# --- Test 4: agents/ default location + plugin agent frontmatter (agents-anthro.md, plugin.md) ---
log_info "Test 4: agents/*.md (default location + frontmatter)..."

AGENTS_DIR="$PLUGIN_ROOT/agents"
AGENT_FM_FAIL=0
if [[ -d "$AGENTS_DIR" ]]; then
  AGENT_COUNT=$(find "$AGENTS_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  if [[ "${AGENT_COUNT:-0}" -gt 0 ]]; then
    while IFS= read -r -d '' agent_md; do
      ablock=$(agent_frontmatter_block "$agent_md")
      if ! skill_has_opening_frontmatter "$agent_md"; then
        log_failure "Agent missing YAML frontmatter: $agent_md"
        AGENT_FM_FAIL=$((AGENT_FM_FAIL + 1))
      elif echo "$ablock" | grep -qE '^(hooks|mcpServers|permissionMode):'; then
        log_failure "Plugin agent must not set hooks/mcpServers/permissionMode (agents-anthro.md): $agent_md"
        AGENT_FM_FAIL=$((AGENT_FM_FAIL + 1))
      elif ! echo "$ablock" | grep -q '^name:' || ! echo "$ablock" | grep -q '^description:'; then
        log_failure "Agent frontmatter needs name: and description: (agents-anthro.md): $agent_md"
        AGENT_FM_FAIL=$((AGENT_FM_FAIL + 1))
      fi
    done < <(find "$AGENTS_DIR" -maxdepth 1 -type f -name '*.md' -print0 2>/dev/null)
    if [[ "$AGENT_FM_FAIL" -eq 0 ]]; then
      log_success "Agent definitions: $AGENT_COUNT; name+description; no disallowed plugin fields"
      add_result "agents" "passed" "count=$AGENT_COUNT"
    else
      add_result "agents" "failed" "frontmatter=$AGENT_FM_FAIL"
    fi
  else
    log_failure "No .md files in $AGENTS_DIR"
    add_result "agents" "failed" "Empty agents/"
  fi
else
  log_failure "Missing directory: $AGENTS_DIR"
  add_result "agents" "failed" "agents/ missing"
fi

# --- Test 5: skills/<name>/SKILL.md + frontmatter (plugin.md, skills-anthro.md) ---
log_info "Test 5: skills/<name>/SKILL.md (plugin.md + skills-anthro.md)..."

SKILLS_DIR="$PLUGIN_ROOT/skills"
SKILL_COUNT=0
SKILL_FM_FAIL=0
SKILL_BANG_COUNT=0
if [[ -d "$SKILLS_DIR" ]]; then
  while IFS= read -r -d '' skill_md; do
    SKILL_COUNT=$((SKILL_COUNT + 1))
    sblock=$(skill_frontmatter_block "$skill_md")
    if ! skill_has_opening_frontmatter "$skill_md"; then
      log_failure "SKILL.md must start with YAML frontmatter (---): $skill_md"
      SKILL_FM_FAIL=$((SKILL_FM_FAIL + 1))
      continue
    fi
    if ! skill_description_present "$sblock"; then
      log_warning "SKILL.md should include description: in frontmatter (skills-anthro.md recommends): $skill_md"
    fi
    if ! skill_name_valid "$sblock"; then
      log_failure "Skill name: must be lowercase [a-z0-9-] max 64 chars when set (skills-anthro.md): $skill_md"
      SKILL_FM_FAIL=$((SKILL_FM_FAIL + 1))
    fi
    if skill_uses_bang_backtick "$skill_md"; then
      log_warning "SKILL.md uses !\`...\` shell preprocessing (runs before model sees content; skills-anthro.md): $skill_md"
      SKILL_BANG_COUNT=$((SKILL_BANG_COUNT + 1))
    fi
  done < <(find "$SKILLS_DIR" -mindepth 2 -maxdepth 2 -type f -name 'SKILL.md' -print0 2>/dev/null)
  if [[ "$SKILL_COUNT" -gt 0 && "$SKILL_FM_FAIL" -eq 0 ]]; then
    log_success "Skills with SKILL.md: $SKILL_COUNT; frontmatter valid (description recommended)"
    add_result "skills" "passed" "count=$SKILL_COUNT"
    if [[ "$SKILL_BANG_COUNT" -gt 0 ]]; then
      add_result "skill_bang_preprocess" "warning" "$SKILL_BANG_COUNT SKILL.md use !\`...\`"
    else
      add_result "skill_bang_preprocess" "passed" "no !\`...\` blocks"
    fi
  elif [[ "$SKILL_COUNT" -eq 0 ]]; then
    log_failure "No skills/*/SKILL.md under $SKILLS_DIR"
    add_result "skills" "failed" "No SKILL.md"
    add_result "skill_bang_preprocess" "skipped" "no skills"
  else
    add_result "skills" "failed" "frontmatter issues"
    if [[ "$SKILL_BANG_COUNT" -gt 0 ]]; then
      add_result "skill_bang_preprocess" "warning" "$SKILL_BANG_COUNT SKILL.md use !\`...\`"
    else
      add_result "skill_bang_preprocess" "skipped" "skills failed first"
    fi
  fi
else
  log_failure "Missing directory: $SKILLS_DIR"
  add_result "skills" "failed" "skills/ missing"
  add_result "skill_bang_preprocess" "skipped" "no skills dir"
fi

# --- Test 6: hooks/hooks.json — events, handler types, ${CLAUDE_PLUGIN_ROOT|DATA}, scripts ---
log_info "Test 6: hooks/hooks.json + bundled scripts (plugin.md, hooks-ref.md)..."

HOOK_SRC_JSON=""
HOOK_SRC_LABEL=""
if [[ -f "$HOOKS_JSON" ]]; then
  HOOK_SRC_JSON="$HOOKS_JSON"
  HOOK_SRC_LABEL="hooks/hooks.json"
elif [[ -f "$PLUGIN_JSON" ]] && command -v jq &>/dev/null && jq -e '.hooks | type == "object"' "$PLUGIN_JSON" >/dev/null 2>&1; then
  HOOK_SRC_JSON="$PLUGIN_JSON"
  HOOK_SRC_LABEL="plugin.json (inline hooks)"
  log_info "Using inline hooks from plugin.json (plugin.md: hooks may be inline)"
fi

if [[ -n "$HOOK_SRC_JSON" ]]; then
  log_success "Hook config found: $HOOK_SRC_LABEL"
  add_result "hooks_json_exists" "passed" "$HOOK_SRC_LABEL"
  if command -v jq &>/dev/null; then
    if jq -e '.hooks | type == "object"' "$HOOK_SRC_JSON" >/dev/null 2>&1; then
      log_success "Top-level .hooks object present"
      add_result "hooks_json_shape" "passed" "Valid shape"
    else
      log_failure "Hook config missing top-level .hooks object"
      add_result "hooks_json_shape" "failed" "Bad shape"
    fi
    HOOK_EVENT_FAIL=0
    while IFS= read -r ev; do
      [[ -z "$ev" ]] && continue
      if ! hook_event_is_known "$ev"; then
        log_failure "Unknown hook event key (plugin.md / hooks-ref.md): $ev"
        HOOK_EVENT_FAIL=$((HOOK_EVENT_FAIL + 1))
      fi
    done < <(jq -r '.hooks | keys[]' "$HOOK_SRC_JSON" 2>/dev/null)
    if [[ "$HOOK_EVENT_FAIL" -eq 0 ]]; then
      log_success "All .hooks event keys are documented lifecycle events"
      add_result "hooks_events" "passed" "known events"
    else
      add_result "hooks_events" "failed" "unknown=$HOOK_EVENT_FAIL"
    fi
    HOOK_TYPE_FAIL=0
    while IFS= read -r ht; do
      [[ -z "$ht" ]] && continue
      if ! hook_handler_type_ok "$ht"; then
        log_failure "Unknown hook handler type (hooks-ref.md: command|http|prompt|agent): $ht"
        HOOK_TYPE_FAIL=$((HOOK_TYPE_FAIL + 1))
      fi
    done < <(jq -r '.hooks | to_entries[] | .value[] | .hooks[]? | .type // "command"' "$HOOK_SRC_JSON" 2>/dev/null | sort -u)
    if [[ "$HOOK_TYPE_FAIL" -eq 0 ]]; then
      log_success "Hook handler types are valid"
      add_result "hooks_handler_types" "passed" "OK"
    else
      add_result "hooks_handler_types" "failed" "bad=$HOOK_TYPE_FAIL"
    fi
    HOOK_CMD_FAIL=0
    HOOK_REL_FAIL=0
    HOOK_X_FAIL=0
    while IFS= read -r cmd; do
      [[ -z "$cmd" ]] && continue
      if [[ "$cmd" != *'${CLAUDE_PLUGIN_ROOT}'* && "$cmd" != *'${CLAUDE_PLUGIN_DATA}'* ]]; then
        log_failure "Plugin hook command must use \${CLAUDE_PLUGIN_ROOT} or \${CLAUDE_PLUGIN_DATA} for paths (plugin.md): ${cmd:0:120}..."
        HOOK_CMD_FAIL=$((HOOK_CMD_FAIL + 1))
        continue
      fi
      if [[ "$cmd" == *'${CLAUDE_PLUGIN_ROOT}'* ]]; then
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
      fi
    done < <(jq -r '[.hooks | to_entries[] | .value[] | .hooks[]? | select((.type // "command") == "command") | .command] | unique | .[]' "$HOOK_SRC_JSON" 2>/dev/null)
    if [[ "$HOOK_CMD_FAIL" -eq 0 && "$HOOK_REL_FAIL" -eq 0 ]]; then
      log_success "Command hooks use plugin path vars and resolve under plugin root"
      add_result "hooks_commands" "passed" "CLAUDE_PLUGIN_ROOT|DATA + files"
    else
      add_result "hooks_commands" "failed" "cmd=$HOOK_CMD_FAIL missing=$HOOK_REL_FAIL"
    fi
    if [[ "$HOOK_X_FAIL" -gt 0 ]]; then
      add_result "hooks_executable" "warning" "$HOOK_X_FAIL not executable"
    else
      log_success "Referenced hook scripts are executable"
      add_result "hooks_executable" "passed" "chmod +x OK"
    fi
  else
    log_warning "jq not installed; skipping hooks.json event/type/command checks"
    add_result "hooks_json_shape" "skipped" "no jq"
    add_result "hooks_events" "skipped" "no jq"
    add_result "hooks_handler_types" "skipped" "no jq"
    add_result "hooks_commands" "skipped" "no jq"
    add_result "hooks_executable" "skipped" "no jq"
  fi
  HOOK_SCRIPT_COUNT=$(find "$PLUGIN_ROOT/hooks/scripts" -type f -name '*.sh' 2>/dev/null | wc -l | tr -d ' ')
  if [[ "${HOOK_SCRIPT_COUNT:-0}" -gt 0 ]]; then
    log_success "hooks/scripts/*.sh count: $HOOK_SCRIPT_COUNT"
    add_result "hook_scripts" "passed" "count=$HOOK_SCRIPT_COUNT"
    SHB_WARN=0
    while IFS= read -r -d '' hs; do
      first=$(head -1 "$hs")
      if [[ "$first" != '#!/bin/bash' && "$first" != '#!/usr/bin/env bash' && "$first" != '#!/usr/bin/bash' ]]; then
        log_warning "Hook script shebang should be #!/bin/bash or #!/usr/bin/env bash (hooks-anthro.md): $hs"
        SHB_WARN=$((SHB_WARN + 1))
      fi
    done < <(find "$PLUGIN_ROOT/hooks/scripts" -type f -name '*.sh' -print0 2>/dev/null)
    if [[ "$SHB_WARN" -gt 0 ]]; then
      add_result "hooks_shebang" "warning" "$SHB_WARN scripts"
    else
      add_result "hooks_shebang" "passed" "bash shebangs"
    fi
  else
    log_failure "No .sh under $PLUGIN_ROOT/hooks/scripts"
    add_result "hook_scripts" "failed" "No scripts"
  fi
else
  log_failure "No hook config: add hooks/hooks.json or inline \"hooks\" in plugin.json (plugin.md)"
  add_result "hooks_json_exists" "failed" "Not found"
fi

# --- Test 6b: optional .mcp.json / .lsp.json (plugin.md) ---
log_info "Test 6b: optional .mcp.json / .lsp.json..."

MCP_JSON="$PLUGIN_ROOT/.mcp.json"
LSP_JSON="$PLUGIN_ROOT/.lsp.json"
if [[ -f "$MCP_JSON" ]]; then
  if command -v jq &>/dev/null && jq empty "$MCP_JSON" 2>/dev/null; then
    log_success ".mcp.json valid JSON (plugin.md: use \${CLAUDE_PLUGIN_ROOT} in bundled server paths)"
    add_result "mcp_json" "passed" "valid JSON"
  else
    log_failure ".mcp.json missing or invalid JSON"
    add_result "mcp_json" "failed" "parse"
  fi
else
  add_result "mcp_json" "skipped" "no file"
fi
if [[ -f "$LSP_JSON" ]]; then
  if command -v jq &>/dev/null && jq empty "$LSP_JSON" 2>/dev/null; then
    log_success ".lsp.json valid JSON (plugin.md: install language server binary separately)"
    add_result "lsp_json" "passed" "valid JSON"
  else
    log_failure ".lsp.json invalid JSON"
    add_result "lsp_json" "failed" "parse"
  fi
else
  add_result "lsp_json" "skipped" "no file"
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
