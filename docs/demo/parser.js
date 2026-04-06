/**
 * parser.js — Session artifact parser for Popcorn XP session viewer
 *
 * Reads a FileList from a <input webkitdirectory> picker and reconstructs
 * the session data model from real .popcorn-xp/{team}/ artifacts.
 *
 * All parse functions are exported for unit testing and incremental loading.
 * The single public entry point is parseSessionFolder(fileList).
 */

// ─── Low-level helpers ───────────────────────────────────────────────────────

/**
 * Read a File as text, resolving with the string or null on error.
 */
function readText(file) {
  return new Promise((resolve) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = () => resolve(null);
    reader.readAsText(file);
  });
}

/**
 * Build a lookup map from a FileList keyed by webkitRelativePath.
 * The root prefix (everything up to and including the first path segment)
 * is stripped so keys are relative to the team folder.
 *
 * .popcorn-xp/demo-v2/LOG.md → "LOG.md"
 * .popcorn-xp/demo-v2/tasks/T1/meta.json → "tasks/T1/meta.json"
 */
function buildFileMap(fileList) {
  const map = new Map();
  for (const file of fileList) {
    const parts = file.webkitRelativePath.split("/");
    // Strip root segment (the selected directory name)
    const key = parts.slice(1).join("/");
    map.set(key, file);
  }
  return map;
}

// ─── Format parsers ──────────────────────────────────────────────────────────

/**
 * Parse events.jsonl — newline-delimited JSON events.
 *
 * Returns an array of event objects:
 *   { event, team, recorded_at, payload }
 */
export function parseEventsJsonl(text) {
  if (!text) return [];
  return text
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .flatMap((line) => {
      try {
        return [JSON.parse(line)];
      } catch {
        return [];
      }
    });
}

/**
 * Parse tasks/T{n}/meta.json — task metadata object.
 *
 * Returns the parsed object or null on failure.
 */
export function parseTaskMeta(text) {
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

/**
 * Parse tasks/T{n}/back-forth.md — task chat log.
 *
 * Lines follow the pattern:
 *   ### 2026-04-06T17:57:17Z | from=lead | kind=brief
 *   Message text on one or more following lines.
 *
 * Returns an array of chat message objects:
 *   { timestamp, from, kind, message }
 */
export function parseBackForth(text) {
  if (!text) return [];

  const messages = [];
  // Match header lines: ### {iso-timestamp} | from={name} | kind={kind}
  const headerRe = /^###\s+(\S+)\s+\|\s+from=(\S+)\s+\|\s+kind=(\S+)/;
  const lines = text.split("\n");

  let current = null;
  for (const line of lines) {
    const match = line.match(headerRe);
    if (match) {
      if (current) messages.push(current);
      current = {
        timestamp: match[1],
        from: match[2],
        kind: match[3],
        message: "",
      };
    } else if (current) {
      // Accumulate message body lines (trim leading blank line)
      const appended = current.message ? current.message + "\n" + line : line;
      current.message = appended;
    }
  }
  if (current) messages.push(current);

  // Trim trailing whitespace from accumulated messages
  return messages.map((m) => ({ ...m, message: m.message.trim() }));
}

/**
 * Parse ADVICE.md — append-only typed advice ledger.
 *
 * Advice entry format:
 *   ### TYPE ID — open [(by author)]
 *   Detail text
 *
 * Resolution entry format:
 *   ### ID — OUTCOME
 *   Detail
 *
 * Strategy: single pass, collect all entries, then resolve status by
 * checking for matching resolution lines. This handles the append-only
 * pattern where open headers appear before their resolution entries.
 *
 * Returns an array of advice objects:
 *   { type, id, status, author, detail, resolution, resolutionDetail }
 */
export function parseAdvice(text) {
  if (!text) return [];

  // Match advice opening lines: ### TYPE ID — open [(by author)]
  const adviceRe =
    /^###\s+(OBJECTION|SMELL|STEER|FYI)\s+((?:OBJ|SML|STR|FYI)-\S+)\s+—\s+open(?:\s+\(by\s+([^)]+)\))?/i;

  // Match resolution lines: ### ID — OUTCOME
  const resolveRe =
    /^###\s+((?:OBJ|SML|STR|FYI)-\S+)\s+—\s+(FIXED|REJECTED|INCORPORATED|NOTED)/i;

  const lines = text.split("\n");
  const items = new Map(); // id → advice object
  const resolutions = new Map(); // id → { outcome, detail }

  let currentId = null;
  let currentLines = [];
  let mode = null; // "advice" | "resolution"

  function flush() {
    if (!currentId) return;
    const detail = currentLines.join("\n").trim();
    if (mode === "advice") {
      const item = items.get(currentId);
      if (item) item.detail = detail;
    } else if (mode === "resolution") {
      const res = resolutions.get(currentId);
      if (res) res.detail = detail;
    }
    currentId = null;
    currentLines = [];
    mode = null;
  }

  for (const line of lines) {
    const adviceMatch = line.match(adviceRe);
    const resolveMatch = line.match(resolveRe);

    if (adviceMatch) {
      flush();
      const [, type, id, author] = adviceMatch;
      currentId = id.toUpperCase();
      mode = "advice";
      // Only record first occurrence (append-only; later entries are resolutions)
      if (!items.has(currentId)) {
        items.set(currentId, {
          type: type.toUpperCase(),
          id: currentId,
          status: "open",
          author: author || null,
          detail: "",
          resolution: null,
          resolutionDetail: "",
        });
      }
    } else if (resolveMatch) {
      flush();
      const [, id, outcome] = resolveMatch;
      currentId = id.toUpperCase();
      mode = "resolution";
      if (!resolutions.has(currentId)) {
        resolutions.set(currentId, { outcome: outcome.toUpperCase(), detail: "" });
      }
    } else if (currentId) {
      // Skip the "# Advice" document header
      if (line.startsWith("# ")) {
        flush();
      } else {
        currentLines.push(line);
      }
    }
  }
  flush();

  // Apply resolutions back to advice items
  for (const [id, res] of resolutions) {
    if (items.has(id)) {
      const item = items.get(id);
      item.status = "resolved";
      item.resolution = res.outcome;
      item.resolutionDetail = res.detail;
    }
  }

  return Array.from(items.values());
}

/**
 * Parse LOG.md — append-only checkpoint log.
 *
 * Recognises:
 *   ## Task T{n} — Driver @{name}, Navigator @{name}
 *   ### Checkpoint [N]
 *   ### Navigator READY
 *   ### Task Complete
 *
 * Returns an array of log section objects:
 *   { task, driver, navigator, entries: [{ heading, body }] }
 */
export function parseLog(text) {
  if (!text) return [];

  const taskHeaderRe = /^##\s+Task\s+(T\d+)\s+—\s+Driver\s+@(\S+),\s+Navigator\s+@(\S+)/i;
  // More permissive fallback for lines with "(pending claim)" etc.
  const taskHeaderLooseRe = /^##\s+Task\s+(T\d+)/i;
  const entryHeaderRe = /^###\s+(.+)/;

  const sections = [];
  let currentSection = null;
  let currentEntry = null;

  function flushEntry() {
    if (currentEntry && currentSection) {
      currentEntry.body = currentEntry.body.trim();
      currentSection.entries.push(currentEntry);
      currentEntry = null;
    }
  }

  function flushSection() {
    flushEntry();
    if (currentSection) sections.push(currentSection);
    currentSection = null;
  }

  for (const line of text.split("\n")) {
    const taskMatch = line.match(taskHeaderRe);
    if (taskMatch) {
      flushSection();
      currentSection = {
        task: taskMatch[1],
        driver: taskMatch[2],
        navigator: taskMatch[3],
        entries: [],
      };
      continue;
    }

    // Loose match for task headers that don't have full role info yet
    const looseTaskMatch = !taskMatch && line.match(taskHeaderLooseRe);
    if (looseTaskMatch) {
      flushSection();
      currentSection = {
        task: looseTaskMatch[1],
        driver: null,
        navigator: null,
        entries: [],
      };
      continue;
    }

    const entryMatch = line.match(entryHeaderRe);
    if (entryMatch && currentSection) {
      flushEntry();
      currentEntry = { heading: entryMatch[1].trim(), body: "" };
      continue;
    }

    if (currentEntry) {
      currentEntry.body += line + "\n";
    }
  }

  flushSection();
  return sections;
}

/**
 * Parse RETRO.md — retrospective document.
 *
 * Returns an object with named sections. Section keys are derived from
 * the markdown heading text (lowercased, spaces → underscores).
 * Each value is the trimmed text body of that section.
 */
export function parseRetro(text) {
  if (!text) return null;

  const retro = { raw: text, sections: {} };
  const sectionRe = /^###\s+(.+)/;
  let currentKey = null;
  let currentLines = [];

  function flush() {
    if (currentKey) {
      retro.sections[currentKey] = currentLines.join("\n").trim();
    }
    currentKey = null;
    currentLines = [];
  }

  for (const line of text.split("\n")) {
    const match = line.match(sectionRe);
    if (match) {
      flush();
      currentKey = match[1]
        .trim()
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, "_")
        .replace(/^_|_$/g, "");
    } else if (currentKey) {
      currentLines.push(line);
    } else {
      // Before first section — treat as preamble
      if (!retro.preamble) retro.preamble = "";
      retro.preamble += line + "\n";
    }
  }
  flush();

  if (retro.preamble) retro.preamble = retro.preamble.trim();
  return retro;
}

/**
 * Parse agent-state/{agent}.json — per-agent state.
 *
 * Returns the parsed object or null on failure.
 */
export function parseAgentState(text) {
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

/**
 * Parse .runtime-mode — plain text "subagent" or "team".
 *
 * Returns "subagent" | "team" | "subagent" (default when missing).
 */
export function parseRuntimeMode(text) {
  if (!text) return "subagent";
  const trimmed = text.trim().toLowerCase();
  return trimmed === "team" ? "team" : "subagent";
}

// ─── Task discovery ──────────────────────────────────────────────────────────

/**
 * Given a file map, discover all task IDs by scanning for
 * paths matching tasks/T{n}/meta.json.
 */
function discoverTaskIds(fileMap) {
  const ids = new Set();
  const taskRe = /^tasks\/(T\d+)\//i;
  for (const key of fileMap.keys()) {
    const match = key.match(taskRe);
    if (match) ids.add(match[1].toUpperCase());
  }
  return Array.from(ids).sort((a, b) => {
    const n = (s) => parseInt(s.slice(1), 10);
    return n(a) - n(b);
  });
}

/**
 * Given a file map, discover all agent state file names under agent-state/.
 */
function discoverAgentStateFiles(fileMap) {
  const names = [];
  const agentRe = /^agent-state\/(.+\.json)$/i;
  for (const key of fileMap.keys()) {
    const match = key.match(agentRe);
    if (match) names.push({ key, filename: match[1] });
  }
  return names;
}

// ─── Main entry point ────────────────────────────────────────────────────────

/**
 * Parse a directory picked via <input webkitdirectory> into a session data model.
 *
 * @param {FileList} fileList — the FileList from the input's change event
 * @returns {Promise<SessionData>}
 *
 * SessionData shape:
 * {
 *   teamName: string,          // derived from the root folder name
 *   runtimeMode: "subagent"|"team",
 *   events: Event[],
 *   tasks: {
 *     [taskId]: {
 *       meta: TaskMeta | null,
 *       chat: ChatMessage[],
 *     }
 *   },
 *   advice: AdviceItem[],
 *   log: LogSection[],
 *   retro: RetroData | null,
 *   agentStates: { [agentName]: AgentState },
 *   loadedAt: string,          // ISO timestamp
 *   errors: string[],          // non-fatal parse warnings
 * }
 */
export async function parseSessionFolder(fileList) {
  const errors = [];
  const fileMap = buildFileMap(fileList);

  // Team name comes from the root segment of any path in the FileList
  const firstFile = fileList[0];
  const teamName = firstFile ? firstFile.webkitRelativePath.split("/")[0] : "unknown";

  // Helper: read a file by key, return null if not found
  async function read(key) {
    const file = fileMap.get(key);
    if (!file) return null;
    const text = await readText(file);
    if (text === null) {
      errors.push(`Failed to read: ${key}`);
    }
    return text;
  }

  // Core session files
  const [
    eventsText,
    adviceText,
    logText,
    retroText,
    runtimeModeText,
  ] = await Promise.all([
    read("events.jsonl"),
    read("ADVICE.md"),
    read("LOG.md"),
    read("RETRO.md"),
    read(".runtime-mode"),
  ]);

  // Tasks
  const taskIds = discoverTaskIds(fileMap);
  const tasks = {};
  await Promise.all(
    taskIds.map(async (id) => {
      const lc = id.toLowerCase();
      const [metaText, chatText] = await Promise.all([
        read(`tasks/${id}/meta.json`),
        // Task IDs in the file system may be mixed case; try both
        read(`tasks/${id}/back-forth.md`),
      ]);

      tasks[id] = {
        meta: parseTaskMeta(metaText),
        chat: parseBackForth(chatText),
      };

      if (!tasks[id].meta) {
        errors.push(`Could not parse tasks/${id}/meta.json`);
      }
    }),
  );

  // Agent states
  const agentStateFiles = discoverAgentStateFiles(fileMap);
  const agentStates = {};
  await Promise.all(
    agentStateFiles.map(async ({ key, filename }) => {
      const text = await read(key);
      const state = parseAgentState(text);
      if (state) {
        // Key by agent name field if present, otherwise by filename stem
        const agentName = state.agent || filename.replace(/\.json$/, "");
        agentStates[agentName] = state;
      } else {
        errors.push(`Could not parse ${key}`);
      }
    }),
  );

  return {
    teamName,
    runtimeMode: parseRuntimeMode(runtimeModeText),
    events: parseEventsJsonl(eventsText),
    tasks,
    advice: parseAdvice(adviceText),
    log: parseLog(logText),
    retro: parseRetro(retroText),
    agentStates,
    loadedAt: new Date().toISOString(),
    errors,
  };
}
