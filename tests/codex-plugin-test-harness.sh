#!/usr/bin/env bash
#
# Popcorn XP — Codex integration layout checks
#
# research/official/codex/plugin.md (full page):
# - Curated marketplace: $REPO_ROOT/.agents/plugins/marketplace.json (or ~/.agents/...); plugins[],
#   source.source + source.path (./-prefixed, resolved from marketplace/repo root per doc),
#   policy.installation, policy.authentication, category; optional interface.displayName.
# - Plugin package: .codex-plugin/plugin.json only inside .codex-plugin/; skills/, .mcp.json, .app.json,
#   assets/ at plugin root; manifest name kebab-case; minimal name+version+description+skills;
#   path fields relative to plugin root, start with ./ (skills, mcpServers, apps, interface assets).
# - Install/cache behavior is product-side; we validate on-disk layout only.
#
# research/official/codex/hooks.md (full page):
# - Feature flag [features] codex_hooks = true; hooks.json beside config (~/.codex or <repo>/.codex).
# - Shape: .hooks.<Event> -> array of matcher groups; each group has optional matcher + .hooks[] handlers.
# - Command handlers: type "command", command string; optional timeout|timeoutSec (seconds), statusMessage.
# - Repo-local commands: prefer git root in path (not bare .codex/...) per hooks.md.
# - SessionStart: matcher filters source (startup|resume). Stop/UserPromptSubmit: matcher ignored.
#
# research/official/codex/skills.md (full page):
# - Skill dir: SKILL.md required; name + description in frontmatter; optional scripts/, references/, assets/, agents/openai.yaml.
# - Repo discovery: $REPO_ROOT/.agents/skills (among other scopes); symlink targets followed.
# - [[skills.config]] in ~/.codex/config.toml for enable/disable (we spot-check agent TOMLs reference paths).
#
# research/official/codex/subagents.md (full page):
# - Custom agents: standalone TOML under .codex/agents/ (project) or ~/.codex/agents/ (personal).
# - Required per agent file: name, description, developer_instructions (name field is source of truth vs filename).
# - Optional: nickname_candidates (non-empty, unique; ASCII letters, digits, spaces, hyphens, underscores),
#   model, sandbox_mode, mcp_servers, [[skills.config]], etc.
# - Global [agents] in config.toml: max_threads, max_depth, job_max_runtime_seconds (non-negative integers when set;
#   defaults 6 / 1 / unset per doc).
#

set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CODEX_ROOT="$REPO_ROOT/platforms/codex/subagent"
MANIFESTS="$CODEX_ROOT/manifests"
HOOKS_MANIFEST="$MANIFESTS/hooks.json"
CONFIG_MANIFEST="$MANIFESTS/config.toml"
GEN_CODEX="$REPO_ROOT/.codex"
GEN_SCRIPT="$REPO_ROOT/install/codex/generate.sh"
RESULTS_FILE="$SCRIPT_DIR/codex-plugin-test-results.json"
AGENTS_MARKETPLACE="$REPO_ROOT/.agents/plugins/marketplace.json"
REPO_AGENTS_SKILLS="$REPO_ROOT/.agents/skills"
PLUGIN_MANIFEST="$CODEX_ROOT/.codex-plugin/plugin.json"
PLUGIN_DOT_DIR="$CODEX_ROOT/.codex-plugin"

DOC_REFS="research/official/codex/plugin.md (full), hooks.md (full), skills.md (full), subagents.md"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0
WARNINGS=0

echo '{"tests": [], "timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"}' >"$RESULTS_FILE"

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; PASSED=$((PASSED + 1)); }
log_failure() { echo -e "${RED}❌ $1${NC}"; FAILED=$((FAILED + 1)); }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; WARNINGS=$((WARNINGS + 1)); }

add_result() {
  local name="$1" status="$2" message="$3"
  if command -v jq &>/dev/null; then
    local t
    t="$(mktemp)"
    jq --arg name "$name" --arg status "$status" --arg message "$message" \
      '.tests += [{"name": $name, "status": $status, "message": $message}]' \
      "$RESULTS_FILE" >"$t" && mv "$t" "$RESULTS_FILE"
  fi
}

skill_frontmatter_ok() {
  local f="$1"
  local block
  block=$(awk '/^---$/{c++; next} c==1{print} c>=2{exit}' "$f" 2>/dev/null)
  echo "$block" | grep -q '^name:' && echo "$block" | grep -q '^description:'
}

skill_frontmatter_name() {
  local f="$1"
  local block
  block=$(awk '/^---$/{c++; next} c==1{print} c>=2{exit}' "$f" 2>/dev/null)
  echo "$block" | awk '/^name:/{sub(/^name:[[:space:]]+/, ""); gsub(/^["\047]|["\047]$/, ""); print; exit}'
}

# plugin.md: stable plugin name in kebab-case
kebab_case_ok() {
  [[ "$1" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]
}

# plugin.md Path rules: relative to plugin root, start with ./
rel_plugin_path_ok() {
  local v="$1"
  [[ "$v" == ./* ]]
}

# skills.md: example uses kebab-case skill name in frontmatter (name: skill-name)
skill_name_kebab_ok() {
  local v="$1"
  [[ "$v" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]
}

# hooks.md: event -> matcher groups[] -> each group .hooks[] command handlers
hooks_command_handlers_ok() {
  local jf="$1"
  command -v jq &>/dev/null || return 0
  jq -e '
    (.hooks | type == "object") and
    ([.hooks | to_entries[] | .value | type == "array"] | all(.)) and
    ([.hooks | to_entries[] | .value[] | has("hooks") and (.hooks | type == "array")] | all(.)) and
    ([.hooks | to_entries[] | .value[] | .hooks[]] | all(
      .type == "command" and
      (.command | type == "string") and ((.command | length) > 0) and
      (if has("timeout") then (.timeout | type == "number") else true end) and
      (if has("timeoutSec") then (.timeoutSec | type == "number") else true end)
    ))
  ' "$jf" >/dev/null 2>&1
}

# subagents.md: optional nickname_candidates on a single line — non-empty, unique, [A-Za-z0-9 _-]+
check_nickname_candidates_in_toml() {
  local f="$1"
  grep -qE '^nickname_candidates[[:space:]]*=' "$f" || return 0
  local line
  line=$(grep -m1 -E '^nickname_candidates[[:space:]]*=' "$f")
  if [[ "$line" != *'['* || "$line" != *']'* ]]; then
    log_warning "subagents.md: nickname_candidates not on one line — verify non-empty, unique ASCII nicknames: $f"
    return 0
  fi
  if [[ "$line" =~ =[[:space:]]*\[\][[:space:]]*(\#.*)?$ ]]; then
    log_failure "subagents.md: nickname_candidates must be non-empty: $f"
    return 1
  fi
  local inner
  inner=$(sed -n 's/^[^[]*\[\([^]]*\)\].*/\1/p' <<<"$line")
  if [[ -z "$inner" ]]; then
    log_warning "subagents.md: could not parse nickname_candidates array: $f"
    return 0
  fi
  local -a nicks=()
  local IFS=,
  local tok trimmed
  for tok in $inner; do
    trimmed=$(echo "$tok" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//;s/^'"'"'//;s/'"'"'$//')
    [[ -z "$trimmed" ]] && continue
    nicks+=("$trimmed")
  done
  if [[ ${#nicks[@]} -eq 0 ]]; then
    log_failure "subagents.md: nickname_candidates has no entries: $f"
    return 1
  fi
  local dup
  dup=$(printf '%s\n' "${nicks[@]}" | sort | uniq -d)
  if [[ -n "$dup" ]]; then
    log_failure "subagents.md: nickname_candidates must be unique: $f"
    return 1
  fi
  local n rest
  for n in "${nicks[@]}"; do
    rest=$(printf '%s' "$n" | tr -d 'A-Za-z0-9_ -')
    if [[ -n "$rest" ]]; then
      log_failure "subagents.md: nickname must use ASCII letters, digits, spaces, hyphens, underscores: '$n' in $f"
      return 1
    fi
  done
  return 0
}

# subagents.md required custom agent keys ($2 set = skip [[skills.config]] warning; used when re-checking .codex copy)
validate_custom_agent_toml_subagents() {
  local f="$1"
  local skip_skills_warn="${2:-}"
  local e=0
  if ! grep -qE '^name[[:space:]]*=' "$f"; then
    log_failure "subagents.md: missing required name in $f"
    e=1
  fi
  if ! grep -qE '^description[[:space:]]*=' "$f"; then
    log_failure "subagents.md: missing required description in $f"
    e=1
  fi
  if ! grep -qE '^developer_instructions[[:space:]]*=' "$f"; then
    log_failure "subagents.md: missing required developer_instructions in $f"
    e=1
  fi
  if ! check_nickname_candidates_in_toml "$f"; then
    e=1
  fi
  if [[ -z "$skip_skills_warn" ]] && ! grep -q '^\[\[skills\.config\]\]' "$f"; then
    log_warning "No [[skills.config]] in $f (subagents.md optional — often used for skill paths)"
  fi
  return "$e"
}

# subagents.md [agents] table: numeric keys must be non-negative integers when present
validate_toml_agents_section_numbers() {
  local cf="$1"
  local ag_fail=0
  local in_agents=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    if [[ "$line" =~ ^\[[[:alnum:]_.]+\][[:space:]]*(\#.*)?$ ]]; then
      if [[ "$line" =~ ^\[agents\][[:space:]]* ]]; then
        in_agents=1
      else
        in_agents=0
      fi
      continue
    fi
    if [[ "$in_agents" -eq 1 ]] && [[ "$line" =~ ^[[:space:]]*(max_threads|max_depth|job_max_runtime_seconds)[[:space:]]*=[[:space:]]*([^#]+) ]]; then
      local val="${BASH_REMATCH[2]}"
      val=$(echo "$val" | sed 's/[[:space:]]*$//;s/#.*//')
      if [[ ! "$val" =~ ^[0-9]+$ ]]; then
        log_failure "subagents.md: [agents] ${BASH_REMATCH[1]} must be a non-negative integer in $cf (got: $val)"
        ag_fail=1
      fi
    fi
  done <"$cf"
  return "$ag_fail"
}

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Popcorn XP — Codex harness${NC}"
echo -e "${BLUE}  ($DOC_REFS)${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
log_info "REPO_ROOT=$REPO_ROOT"
log_info "CODEX_ROOT=$CODEX_ROOT"
echo ""

# --- Test 1: Canonical tree exists ---
log_info "Test 1: platforms/codex/subagent/ (canonical Codex source tree)..."

if [[ -d "$CODEX_ROOT" ]]; then
  log_success "Canonical tree directory exists"
  add_result "codex_root" "passed" "platforms/codex/subagent"
else
  log_failure "Missing $CODEX_ROOT"
  add_result "codex_root" "failed" "missing"
fi

# --- Test 2: Formal plugin bundle (plugin.md — Plugin structure / Manifest fields / Path rules) ---
log_info "Test 2: .codex-plugin/plugin.json (plugin.md required entry for a Codex plugin package)..."

if [[ -f "$PLUGIN_MANIFEST" ]]; then
  log_success "Found $PLUGIN_MANIFEST"
  add_result "codex_plugin_json" "passed" "present"
  # Only plugin.json belongs in .codex-plugin/ (plugin.md)
  EXTRAS=0
  if [[ -d "$PLUGIN_DOT_DIR" ]]; then
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      base=$(basename "$f")
      if [[ "$base" != "plugin.json" ]]; then
        log_failure "plugin.md: only plugin.json belongs in .codex-plugin/ — unexpected: $f"
        EXTRAS=$((EXTRAS + 1))
      fi
    done < <(find "$PLUGIN_DOT_DIR" -mindepth 1 -maxdepth 1 2>/dev/null)
  fi
  if [[ "$EXTRAS" -eq 0 ]]; then
    log_success ".codex-plugin/ contains only plugin.json"
    add_result "codex_plugin_dot_dir" "passed" "clean"
  else
    add_result "codex_plugin_dot_dir" "failed" "extra files"
  fi
  if command -v jq &>/dev/null; then
    if jq -e '.name and .version and .description' "$PLUGIN_MANIFEST" >/dev/null 2>&1; then
      log_success "plugin.json has name, version, description (plugin.md minimal manifest)"
      add_result "codex_plugin_required_fields" "passed" "OK"
    else
      log_failure "plugin.json missing name, version, or description"
      add_result "codex_plugin_required_fields" "failed" "incomplete"
    fi
    PN=$(jq -r '.name // empty' "$PLUGIN_MANIFEST" 2>/dev/null)
    if kebab_case_ok "$PN"; then
      log_success "plugin name is kebab-case: $PN"
      add_result "codex_plugin_name_kebab" "passed" "$PN"
    else
      log_failure "plugin.md: plugin name must be stable kebab-case identifier: $PN"
      add_result "codex_plugin_name_kebab" "failed" "$PN"
    fi
    # Path rules: skills, mcpServers, apps — relative to plugin root, start with ./
    SK_PATH=$(jq -r '.skills // empty' "$PLUGIN_MANIFEST" 2>/dev/null)
    if [[ -n "$SK_PATH" ]]; then
      if rel_plugin_path_ok "$SK_PATH"; then
        # Resolve from CODEX_ROOT (plugin root when manifest lives under platforms/codex/subagent)
        SK_RES="$CODEX_ROOT/${SK_PATH#./}"
        if [[ -d "$SK_RES" ]]; then
          log_success "skills path exists: $SK_PATH -> $SK_RES"
          add_result "codex_plugin_skills_path" "passed" "OK"
        else
          log_failure "plugin.json skills directory missing: $SK_RES"
          add_result "codex_plugin_skills_path" "failed" "missing dir"
        fi
      else
        log_failure "plugin.md Path rules: skills must be relative to plugin root and start with ./ (got: $SK_PATH)"
        add_result "codex_plugin_skills_path" "failed" "bad prefix"
      fi
    else
      log_warning "plugin.json has no skills field (optional for some bundles; plugin.md quick-start includes it)"
      add_result "codex_plugin_skills_field" "warning" "absent"
    fi
    for key in mcpServers apps; do
      P=$(jq -r ".[\"$key\"] // empty" "$PLUGIN_MANIFEST" 2>/dev/null)
      [[ -z "$P" ]] && continue
      if ! rel_plugin_path_ok "$P"; then
        log_failure "plugin.md Path rules: $key must start with ./ (got: $P)"
        add_result "codex_plugin_path_$key" "failed" "prefix"
      elif [[ ! -e "$CODEX_ROOT/${P#./}" ]]; then
        log_failure "plugin.json $key points to missing path: $CODEX_ROOT/${P#./}"
        add_result "codex_plugin_path_$key" "failed" "missing"
      else
        log_success "plugin.json $key resolves: $P"
        add_result "codex_plugin_path_$key" "passed" "OK"
      fi
    done
    # interface asset paths (plugin.md — composerIcon, logo, screenshots[])
    while IFS= read -r ap; do
      [[ -z "$ap" || "$ap" == "null" ]] && continue
      if ! rel_plugin_path_ok "$ap"; then
        log_failure "plugin.md: interface asset path must start with ./ (got: $ap)"
        add_result "codex_plugin_interface_asset" "failed" "$ap"
      elif [[ ! -e "$CODEX_ROOT/${ap#./}" ]]; then
        log_warning "interface references missing asset: $ap"
        add_result "codex_plugin_interface_asset" "warning" "missing"
      fi
    done < <(jq -r '.interface // {} | .composerIcon // empty, .logo // empty, .screenshots[]? // empty' "$PLUGIN_MANIFEST" 2>/dev/null)
  else
    log_warning "jq not installed; skipping plugin.json field and path validation"
    add_result "codex_plugin_json_jq" "skipped" "no jq"
  fi
else
  log_warning "No $PLUGIN_MANIFEST — plugin.md plugin package not present; repo may use project .codex/ + marketplace or npx skills only"
  add_result "codex_plugin_json" "warning" "absent"
fi

# --- Test 2b: Repo Codex marketplace (plugin.md — Marketplace metadata) ---
log_info "Test 2b: .agents/plugins/marketplace.json (optional repo marketplace)..."

if [[ -f "$AGENTS_MARKETPLACE" ]]; then
  if command -v jq &>/dev/null; then
    if jq -e '.name and (.plugins | type == "array")' "$AGENTS_MARKETPLACE" >/dev/null 2>&1; then
      log_success "marketplace.json has top-level name and plugins[]"
      add_result "codex_marketplace_shape" "passed" "OK"
    else
      log_failure "marketplace.json missing .name or .plugins array"
      add_result "codex_marketplace_shape" "failed" "bad shape"
    fi
    MP_FAIL=0
    while IFS= read -r line; do
      IFS='|' read -r pname spath pinst pauth cat <<<"$line"
      [[ -z "$pname" ]] && continue
      if [[ -z "$spath" || "$spath" == "null" ]]; then
        log_failure "marketplace plugin $pname: missing source.path"
        MP_FAIL=$((MP_FAIL + 1))
        continue
      fi
      if [[ "$spath" != ./* ]]; then
        log_failure "marketplace plugin $pname: source.path must start with ./ (plugin.md): $spath"
        MP_FAIL=$((MP_FAIL + 1))
      fi
      if [[ -z "$pinst" || "$pinst" == "null" ]]; then
        log_failure "marketplace plugin $pname: missing policy.installation"
        MP_FAIL=$((MP_FAIL + 1))
      fi
      if [[ -z "$pauth" || "$pauth" == "null" ]]; then
        log_failure "marketplace plugin $pname: missing policy.authentication"
        MP_FAIL=$((MP_FAIL + 1))
      fi
      if [[ -z "$cat" || "$cat" == "null" ]]; then
        log_failure "marketplace plugin $pname: missing category"
        MP_FAIL=$((MP_FAIL + 1))
      fi
      # Resolve from repo root (plugin.md: path relative to marketplace root; examples use ./plugins/ under repo)
      RES="$REPO_ROOT/${spath#./}"
      if [[ ! -d "$RES" ]]; then
        log_failure "marketplace plugin $pname: source.path not a directory: $RES"
        MP_FAIL=$((MP_FAIL + 1))
      fi
    done < <(jq -r '.plugins[]? | "\(.name)|\(.source.path // "")|\(.policy.installation // "")|\(.policy.authentication // "")|\(.category // "")"' "$AGENTS_MARKETPLACE" 2>/dev/null)
    if [[ "$MP_FAIL" -eq 0 ]]; then
      log_success "marketplace plugins[] entries: path prefix, policy, category, resolvable dirs"
      add_result "codex_marketplace_plugins" "passed" "OK"
    else
      add_result "codex_marketplace_plugins" "failed" "errors=$MP_FAIL"
    fi
  else
    log_warning "jq not installed; skipping marketplace.json validation"
    add_result "codex_marketplace" "skipped" "no jq"
  fi
else
  log_info "No $AGENTS_MARKETPLACE (optional; plugin.md — add for curated Plugin Directory style install)"
  add_result "codex_marketplace" "skipped" "absent"
fi

# --- Test 3: install/codex/generate.sh ---
log_info "Test 3: install/codex/generate.sh..."

if [[ -f "$GEN_SCRIPT" ]] && [[ -x "$GEN_SCRIPT" ]]; then
  log_success "generate.sh exists and is executable"
  add_result "generate_sh" "passed" "OK"
  if bash -n "$GEN_SCRIPT" 2>/dev/null; then
    log_success "generate.sh passes bash -n"
    add_result "generate_sh_syntax" "passed" "OK"
  else
    log_failure "generate.sh bash syntax error"
    add_result "generate_sh_syntax" "failed" "bash -n"
  fi
else
  log_failure "Missing or non-executable $GEN_SCRIPT"
  add_result "generate_sh" "failed" "missing"
fi

# --- Test 4: manifests/config.toml — codex_hooks (hooks.md) ---
log_info "Test 4: manifests/config.toml ([features] codex_hooks)..."

if [[ -f "$CONFIG_MANIFEST" ]]; then
  if grep -q '^\[features\]' "$CONFIG_MANIFEST"; then
    log_success "[features] section present (hooks.md)"
    add_result "config_features_section" "passed" "OK"
  else
    log_failure "hooks.md: enable hooks via [features] — missing [features] in config.toml"
    add_result "config_features_section" "failed" "missing"
  fi
  if grep -q '^[[:space:]]*codex_hooks[[:space:]]*=[[:space:]]*true' "$CONFIG_MANIFEST"; then
    log_success "codex_hooks = true (hooks.md feature flag)"
    add_result "config_codex_hooks" "passed" "true"
  else
    log_failure "config.toml should set codex_hooks = true"
    add_result "config_codex_hooks" "failed" "missing or false"
  fi
  if grep -q '^\[agents\]' "$CONFIG_MANIFEST"; then
    log_success "[agents] section present (subagents.md limits)"
    add_result "config_agents_section" "passed" "OK"
    if validate_toml_agents_section_numbers "$CONFIG_MANIFEST"; then
      log_success "[agents] max_threads / max_depth / job_max_runtime_seconds are integers when set (subagents.md)"
      add_result "config_agents_numeric" "passed" "OK"
    else
      add_result "config_agents_numeric" "failed" "invalid"
    fi
  else
    log_warning "No [agents] section in sample config.toml"
    add_result "config_agents_section" "warning" "missing"
  fi
else
  log_failure "Missing $CONFIG_MANIFEST"
  add_result "config_toml" "failed" "missing"
fi

# --- Test 5: manifests/hooks.json (hooks.md config shape) ---
log_info "Test 5: manifests/hooks.json (hooks.md)..."

if [[ -f "$HOOKS_MANIFEST" ]]; then
  if command -v jq &>/dev/null; then
    if jq -e '.hooks | type == "object"' "$HOOKS_MANIFEST" >/dev/null 2>&1; then
      log_success "hooks.json has top-level .hooks object"
      add_result "hooks_json_shape" "passed" "OK"
    else
      log_failure "hooks.json missing .hooks object"
      add_result "hooks_json_shape" "failed" "bad shape"
    fi
    for ev in SessionStart Stop; do
      if jq -e --arg ev "$ev" '.hooks[$ev] | type == "array"' "$HOOKS_MANIFEST" >/dev/null 2>&1; then
        log_success "hooks.json defines event: $ev"
        add_result "hooks_event_$ev" "passed" "OK"
      else
        log_failure "hooks.json missing or invalid event: $ev"
        add_result "hooks_event_$ev" "failed" "missing"
      fi
    done
    if hooks_command_handlers_ok "$HOOKS_MANIFEST"; then
      log_success "hooks.md: each handler is type=command with non-empty command; timeout/timeoutSec numeric if set"
      add_result "hooks_command_handlers" "passed" "OK"
    else
      log_failure "hooks.json malformed: expected matcher groups with .hooks[] of {type, command, ...}"
      add_result "hooks_command_handlers" "failed" "shape"
    fi
    SS_M=$(jq -r '.hooks.SessionStart[0].matcher // empty' "$HOOKS_MANIFEST" 2>/dev/null)
    if [[ -n "$SS_M" ]]; then
      if [[ "$SS_M" == *startup* && "$SS_M" == *resume* ]]; then
        log_success "SessionStart matcher covers startup and resume (hooks.md)"
        add_result "hooks_sessionstart_matcher" "passed" "$SS_M"
      else
        log_warning "SessionStart matcher should filter source startup|resume (hooks.md); got: $SS_M"
        add_result "hooks_sessionstart_matcher" "warning" "$SS_M"
      fi
    else
      log_info "SessionStart has no matcher (hooks.md: omit or * matches all sources)"
      add_result "hooks_sessionstart_matcher" "skipped" "no matcher"
    fi
  else
    log_warning "jq not installed; skipping hooks.json structure checks"
    add_result "hooks_json_shape" "skipped" "no jq"
  fi
  # Resolve script paths referenced as .../platforms/codex/subagent/hooks/*.sh
  PATH_FAIL=0
  while IFS= read -r rel; do
    [[ -z "$rel" ]] && continue
    if [[ ! -f "$REPO_ROOT/$rel" ]]; then
      log_failure "Hook script path from hooks.json not found: $rel"
      PATH_FAIL=$((PATH_FAIL + 1))
    fi
  done < <(grep -oE 'platforms/codex/subagent/hooks/[a-zA-Z0-9_.-]+\.sh' "$HOOKS_MANIFEST" 2>/dev/null | sort -u)
  if [[ "$PATH_FAIL" -eq 0 ]]; then
    log_success "All paths under platforms/codex/subagent/hooks/ in hooks.json exist"
    add_result "hooks_paths" "passed" "resolved"
  else
    add_result "hooks_paths" "failed" "$PATH_FAIL missing"
  fi
  # command hooks should use git-toplevel pattern (hooks.md examples)
  if grep -q 'git rev-parse --show-toplevel' "$HOOKS_MANIFEST"; then
    log_success "hooks.json uses \$(git rev-parse --show-toplevel) (stable repo-root resolution)"
    add_result "hooks_git_root" "passed" "OK"
  else
    log_warning "hooks.json does not reference git rev-parse --show-toplevel"
    add_result "hooks_git_root" "warning" "pattern"
  fi
else
  log_failure "Missing $HOOKS_MANIFEST"
  add_result "hooks_json" "failed" "missing"
fi

# --- Test 6: Hook entrypoint scripts ---
log_info "Test 6: hooks/*.sh executable (hooks.md command hooks)..."

HOOK_SH=0
HOOK_XFAIL=0
for f in "$CODEX_ROOT"/hooks/*.sh; do
  [[ -e "$f" ]] || continue
  HOOK_SH=$((HOOK_SH + 1))
  if [[ ! -x "$f" ]]; then
    log_warning "Not executable: $f"
    HOOK_XFAIL=$((HOOK_XFAIL + 1))
  fi
done
if [[ "$HOOK_SH" -gt 0 ]]; then
  log_success "Codex hook scripts found: $HOOK_SH"
  add_result "codex_hook_files" "passed" "count=$HOOK_SH"
  if [[ "$HOOK_XFAIL" -eq 0 ]]; then
    log_success "All Codex hook scripts are executable"
    add_result "codex_hook_executable" "passed" "OK"
  else
    add_result "codex_hook_executable" "warning" "$HOOK_XFAIL not +x"
  fi
else
  log_failure "No .sh hooks under $CODEX_ROOT/hooks/"
  add_result "codex_hook_files" "failed" "none"
fi

# --- Test 7: Custom agents TOML (subagents.md — .codex/agents/ project scope) ---
log_info "Test 7: agents/*.toml (subagents.md: name, description, developer_instructions)..."

AGENTS_DIR="$CODEX_ROOT/agents"
AG_TOML=0
AG_FAIL=0
if [[ -d "$AGENTS_DIR" ]]; then
  for f in "$AGENTS_DIR"/*.toml; do
    [[ -e "$f" ]] || continue
    AG_TOML=$((AG_TOML + 1))
    if ! validate_custom_agent_toml_subagents "$f"; then
      AG_FAIL=$((AG_FAIL + 1))
    fi
  done
  if [[ "$AG_TOML" -gt 0 && "$AG_FAIL" -eq 0 ]]; then
    log_success "Agent TOMLs: $AG_TOML (subagents.md required fields + optional nickname_candidates)"
    add_result "codex_agents" "passed" "count=$AG_TOML"
  elif [[ "$AG_TOML" -eq 0 ]]; then
    log_failure "No .toml in $AGENTS_DIR"
    add_result "codex_agents" "failed" "empty"
  else
    add_result "codex_agents" "failed" "validation errors"
  fi
else
  log_failure "Missing $AGENTS_DIR"
  add_result "codex_agents" "failed" "no dir"
fi

# --- Test 8: Skills (plugin.md + skills.md) ---
log_info "Test 8: skills/<name>/SKILL.md (name, description; kebab-case names)..."

SKILLS_DIR="$CODEX_ROOT/skills"
SKILL_N=0
SK_BAD=0
if [[ -d "$SKILLS_DIR" ]]; then
  while IFS= read -r -d '' md; do
    SKILL_N=$((SKILL_N + 1))
    if ! skill_frontmatter_ok "$md"; then
      log_failure "skills.md: SKILL.md must include name and description in frontmatter: $md"
      SK_BAD=$((SK_BAD + 1))
    fi
    sn=$(skill_frontmatter_name "$md")
    if [[ -n "$sn" ]] && skill_name_kebab_ok "$sn"; then
      :
    else
      log_warning "skills.md: frontmatter name should be a stable kebab-case id (e.g. skill-name): $md -> '$sn'"
      SK_BAD=$((SK_BAD + 1))
    fi
    bn=$(basename "$(dirname "$md")")
    if [[ "$bn" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
      :
    else
      log_warning "Skill directory not kebab-case (plugin.md / skills.md layout): $bn"
      SK_BAD=$((SK_BAD + 1))
    fi
    skill_root=$(dirname "$md")
    oy="$skill_root/agents/openai.yaml"
    if [[ -f "$oy" ]]; then
      if [[ ! -s "$oy" ]]; then
        log_warning "skills.md: optional agents/openai.yaml is empty: $oy"
        SK_BAD=$((SK_BAD + 1))
      else
        log_info "Optional agents/openai.yaml present (skills.md): $oy"
        # skills.md example uses ./ for icon paths under interface
        if grep -qE 'icon_(small|large):' "$oy" 2>/dev/null; then
          bad_icon=0
          while IFS= read -r line; do
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            val=$(echo "$line" | sed -E 's/^[[:space:]]*icon_(small|large):[[:space:]]*//;s/^["'\'']//;s/["'\'']$//')
            [[ -z "$val" ]] && continue
            [[ "$val" == ./* ]] || bad_icon=$((bad_icon + 1))
          done < <(grep -E 'icon_(small|large):' "$oy" 2>/dev/null)
          if [[ "$bad_icon" -eq 0 ]]; then
            log_success "openai.yaml icon paths use ./ prefix (skills.md)"
          else
            log_warning "skills.md: prefer ./-relative paths for icon_small/icon_large in $oy"
          fi
        fi
      fi
    fi
  done < <(find "$SKILLS_DIR" -mindepth 2 -maxdepth 2 -type f -name 'SKILL.md' -print0 2>/dev/null)
  if [[ "$SKILL_N" -gt 0 && "$SK_BAD" -eq 0 ]]; then
    log_success "Skills: $SKILL_N (SKILL.md + kebab dir names)"
    add_result "codex_skills" "passed" "count=$SKILL_N"
  elif [[ "$SKILL_N" -eq 0 ]]; then
    log_failure "No skills/*/SKILL.md"
    add_result "codex_skills" "failed" "none"
  else
    add_result "codex_skills" "failed" "issues"
  fi
else
  log_failure "Missing $SKILLS_DIR"
  add_result "codex_skills" "failed" "no dir"
fi

# --- Test 8b: Repo-level skill discovery (skills.md — $REPO_ROOT/.agents/skills) ---
log_info "Test 8b: .agents/skills at repo root (skills.md REPO discovery)..."

if [[ -d "$REPO_AGENTS_SKILLS" ]]; then
  RS=$(find "$REPO_AGENTS_SKILLS" -type f -name 'SKILL.md' 2>/dev/null | wc -l | tr -d ' ')
  log_success ".agents/skills exists with $RS SKILL.md file(s) (skills.md)"
  add_result "codex_repo_agents_skills" "passed" "count=$RS"
else
  log_info "No .agents/skills at repo root (optional; skills.md — use [[skills.config]] paths or npx skills install)"
  add_result "codex_repo_agents_skills" "skipped" "absent"
fi

# --- Test 9: Generated .codex/ sync (optional) ---
log_info "Test 9: .codex/ vs manifests (after generate.sh)..."

if [[ -f "$GEN_CODEX/hooks.json" ]] && command -v jq &>/dev/null; then
  if hooks_command_handlers_ok "$GEN_CODEX/hooks.json"; then
    log_success ".codex/hooks.json command handlers match hooks.md nested shape"
    add_result "gen_hooks_command_handlers" "passed" "OK"
  else
    log_failure ".codex/hooks.json: invalid hooks.md handler shape (matcher groups + .hooks[])"
    add_result "gen_hooks_command_handlers" "failed" "shape"
  fi
fi

if [[ -f "$GEN_CODEX/hooks.json" ]] && [[ -f "$GEN_CODEX/config.toml" ]]; then
  if cmp -s "$HOOKS_MANIFEST" "$GEN_CODEX/hooks.json" 2>/dev/null; then
    log_success ".codex/hooks.json matches manifests/hooks.json"
    add_result "gen_hooks_sync" "passed" "identical"
  else
    log_warning ".codex/hooks.json differs from manifests/hooks.json — run install/codex/generate.sh"
    add_result "gen_hooks_sync" "warning" "drift"
  fi
  if cmp -s "$CONFIG_MANIFEST" "$GEN_CODEX/config.toml" 2>/dev/null; then
    log_success ".codex/config.toml matches manifests/config.toml"
    add_result "gen_config_sync" "passed" "identical"
  else
    log_warning ".codex/config.toml differs from manifests/config.toml"
    add_result "gen_config_sync" "warning" "drift"
  fi
  GEN_AG=$(find "$GEN_CODEX/agents" -maxdepth 1 -name '*.toml' 2>/dev/null | wc -l | tr -d ' ')
  SRC_AG=$(find "$AGENTS_DIR" -maxdepth 1 -name '*.toml' 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$GEN_AG" == "$SRC_AG" ]] && [[ "${GEN_AG:-0}" -gt 0 ]]; then
    log_success ".codex/agents TOML count matches canonical ($GEN_AG)"
    add_result "gen_agents_count" "passed" "count=$GEN_AG"
  else
    log_warning ".codex/agents count ($GEN_AG) vs canonical ($SRC_AG) — run generate.sh"
    add_result "gen_agents_count" "warning" "mismatch"
  fi
  if [[ -f "$GEN_CODEX/config.toml" ]] && grep -q '^\[agents\]' "$GEN_CODEX/config.toml"; then
    if validate_toml_agents_section_numbers "$GEN_CODEX/config.toml"; then
      log_success ".codex/config.toml [agents] numeric keys OK (subagents.md)"
      add_result "gen_config_agents_numeric" "passed" "OK"
    else
      add_result "gen_config_agents_numeric" "failed" "invalid"
    fi
  fi
  if [[ -d "$GEN_CODEX/agents" ]]; then
    GEN_SUB_FAIL=0
    GEN_SUB_N=0
    for gf in "$GEN_CODEX/agents"/*.toml; do
      [[ -e "$gf" ]] || continue
      GEN_SUB_N=$((GEN_SUB_N + 1))
      if ! validate_custom_agent_toml_subagents "$gf" 1; then
        GEN_SUB_FAIL=$((GEN_SUB_FAIL + 1))
      fi
    done
    if [[ "$GEN_SUB_N" -gt 0 && "$GEN_SUB_FAIL" -eq 0 ]]; then
      log_success ".codex/agents/*.toml match subagents.md required fields ($GEN_SUB_N)"
      add_result "gen_agents_subagents_md" "passed" "count=$GEN_SUB_N"
    elif [[ "$GEN_SUB_N" -gt 0 ]]; then
      add_result "gen_agents_subagents_md" "failed" "errors=$GEN_SUB_FAIL"
    fi
  fi
else
  log_warning "No generated .codex/hooks.json or config.toml — run ./install/codex/generate.sh once"
  add_result "gen_codex" "warning" "absent or incomplete"
fi

# --- Test 10: shared/runtime session (Codex / vendored session helper) ---
log_info "Test 10: shared/runtime/bin/session..."

SESS="$REPO_ROOT/shared/runtime/bin/session"
if [[ -x "$SESS" ]]; then
  log_success "shared/runtime/bin/session executable"
  add_result "session_bin" "passed" "OK"
else
  log_warning "shared/runtime/bin/session missing or not executable"
  add_result "session_bin" "warning" "check"
fi

# --- Test 11: Codex CLI presence (optional) ---
log_info "Test 11: codex CLI (optional)..."

if command -v codex &>/dev/null; then
  CV=$(codex --version 2>/dev/null || echo unknown)
  log_success "codex in PATH: $CV"
  add_result "codex_cli" "passed" "$CV"
else
  log_warning "codex CLI not in PATH"
  add_result "codex_cli" "skipped" "not found"
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
  t=$(mktemp)
  jq --arg passed "$PASSED" --arg failed "$FAILED" --arg warnings "$WARNINGS" \
    '. + {"summary": {"passed": ($passed|tonumber), "failed": ($failed|tonumber), "warnings": ($warnings|tonumber)}}' \
    "$RESULTS_FILE" >"$t" && mv "$t" "$RESULTS_FILE"
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
