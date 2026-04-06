/**
 * app.js — Data-driven session viewer for Popcorn XP
 *
 * Listens for the "sessionloaded" CustomEvent fired by loader.js,
 * then renders all sections from window.sessionData.
 *
 * Sections:
 *   - Session overview / hero (team name, runtime mode, agent roster, counts)
 *   - Health dashboard (computed metrics)
 *   - Events timeline (chronological, filterable, show-more)
 *   - Task board (cards with expandable chat threads)
 *   - Advice ledger (open/resolved badges, type counts)
 *   - Log viewer (LOG.md sections by task)
 *   - Retro viewer (RETRO.md sections)
 *
 * Architecture: sidebar nav with IntersectionObserver scroll-spy.
 * No framework, no aria-live on bulk-replaced containers.
 */

// ─── DOM refs ────────────────────────────────────────────────────────────────

const heroTeamName     = document.getElementById("hero-team-name");
const heroSummary      = document.getElementById("hero-summary");
const heroRuntimeMode  = document.getElementById("hero-runtime-mode");
const summaryMetrics   = document.getElementById("summary-metrics");
const agentStateCards  = document.getElementById("agent-state-cards");
const healthGrid       = document.getElementById("health-grid");
const eventsFilters    = document.getElementById("events-filters");
const eventsList       = document.getElementById("events-list");
const eventsShowMore   = document.getElementById("events-show-more");
const taskBoard        = document.getElementById("task-board");
const adviceSummary    = document.getElementById("advice-summary");
const adviceList       = document.getElementById("advice-list");
const logViewer        = document.getElementById("log-viewer");
const retroViewer      = document.getElementById("retro-viewer");

// ─── Constants ───────────────────────────────────────────────────────────────

const EVENTS_INITIAL_CAP = 20;
const ADVICE_TYPES = ["OBJECTION", "SMELL", "STEER", "FYI"];

const ROLE_COLORS = {
  driver:    "driver",
  navigator: "navigator",
  advisor:   "advisor",
  lead:      "control",
};

// ─── Utilities ────────────────────────────────────────────────────────────────

function esc(str) {
  if (!str) return "";
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function fmtTimestamp(ts) {
  if (!ts) return "";
  // Show only time portion if it looks like ISO
  const match = String(ts).match(/T(\d{2}:\d{2}:\d{2})/);
  return match ? match[1] + "Z" : String(ts).slice(0, 19);
}

function pluralize(n, word) {
  return `${n} ${word}${n !== 1 ? "s" : ""}`;
}

// ─── Overview / Hero ─────────────────────────────────────────────────────────

function renderOverview(session) {
  heroTeamName.textContent = session.teamName || "Session";

  const taskCount   = Object.keys(session.tasks).length;
  const eventCount  = session.events.length;
  const adviceCount = session.advice.length;

  heroSummary.innerHTML =
    `Team <strong>${esc(session.teamName)}</strong> · ` +
    `${pluralize(taskCount, "task")} · ` +
    `${pluralize(eventCount, "event")} · ` +
    `${pluralize(adviceCount, "advice item")}`;

  heroRuntimeMode.textContent = session.runtimeMode;

  const openObj  = session.advice.filter(a => a.type === "OBJECTION" && a.status === "open").length;
  const taskIds  = Object.keys(session.tasks);
  const doneTasks = taskIds.filter(id => {
    const meta = session.tasks[id]?.meta;
    return meta && meta.status === "completed";
  }).length;

  summaryMetrics.innerHTML = [
    { label: "runtime mode",    value: session.runtimeMode,               note: "file bus transport" },
    { label: "tasks",           value: String(taskCount),                  note: `${doneTasks} completed` },
    { label: "events",          value: String(eventCount),                 note: "in events.jsonl" },
    { label: "advice items",    value: String(adviceCount),               note: `${openObj} open OBJECTION${openObj !== 1 ? "s" : ""}` },
    { label: "loaded",          value: session.loadedAt ? fmtTimestamp(session.loadedAt) : "—", note: "parse time" },
  ].map(m => `
    <div class="metric-row">
      <div>
        <span>${esc(m.label)}</span>
        <strong>${esc(m.value)}</strong>
      </div>
      <span>${esc(m.note)}</span>
    </div>
  `).join("");
}

// ─── Agent state cards ───────────────────────────────────────────────────────

function renderAgentCards(session) {
  const agents = Object.entries(session.agentStates);
  if (!agents.length) {
    agentStateCards.innerHTML = `<p class="empty-state">No agent state files found.</p>`;
    return;
  }

  agentStateCards.innerHTML = agents.map(([name, state]) => {
    const role  = state.role  || "—";
    const phase = state.phase || "—";
    const task  = state.task_id || "—";
    const colorClass = ROLE_COLORS[role.toLowerCase()] || "";
    return `
      <article class="agent-card">
        <div class="agent-card-top">
          <span class="stream-role ${colorClass}">${esc(role)}</span>
          <span class="agent-phase">${esc(phase.replace(/_/g, " "))}</span>
        </div>
        <strong class="agent-name">@${esc(name)}</strong>
        <div class="agent-meta">
          <span>task</span>
          <strong>${esc(task)}</strong>
        </div>
        ${state.next_action ? `<p class="agent-next">${esc(state.next_action)}</p>` : ""}
      </article>
    `;
  }).join("");
}

// ─── Health dashboard ─────────────────────────────────────────────────────────

function renderHealth(session) {
  const taskIds    = Object.keys(session.tasks);
  const doneTasks  = taskIds.filter(id => session.tasks[id]?.meta?.status === "completed").length;
  const totalTasks = taskIds.length;
  const pct        = totalTasks > 0 ? Math.round((doneTasks / totalTasks) * 100) : 0;

  const openObj    = session.advice.filter(a => a.type === "OBJECTION" && a.status === "open").length;
  const agentNames = Object.keys(session.agentStates);
  const activeAgents = agentNames.filter(n => {
    const s = session.agentStates[n];
    return s.phase && s.phase !== "completed" && s.phase !== "bench" && s.phase !== "shutdown";
  });

  const cards = [
    {
      label:  "Open OBJECTIONs",
      value:  String(openObj),
      detail: openObj === 0 ? "No blocking advice items." : `${openObj} item${openObj !== 1 ? "s" : ""} must be resolved before task completion.`,
      warn:   openObj > 0,
    },
    {
      label:  "Task completion",
      value:  `${pct}%`,
      detail: `${doneTasks} of ${totalTasks} task${totalTasks !== 1 ? "s" : ""} completed.`,
      warn:   false,
    },
    {
      label:  "Total events",
      value:  String(session.events.length),
      detail: "Events recorded in events.jsonl.",
      warn:   false,
    },
    {
      label:  "Agents active",
      value:  String(activeAgents.length),
      detail: activeAgents.length
        ? activeAgents.map(n => `@${n}`).join(", ")
        : "No agents in active phases.",
      warn:   false,
    },
    {
      label:  "Advice items",
      value:  String(session.advice.length),
      detail: `${session.advice.filter(a => a.status === "resolved").length} resolved.`,
      warn:   false,
    },
    {
      label:  "Parse errors",
      value:  String(session.errors.length),
      detail: session.errors.length ? session.errors.slice(0, 2).join("; ") : "Clean parse.",
      warn:   session.errors.length > 0,
    },
  ];

  healthGrid.innerHTML = cards.map(card => `
    <article class="health-card${card.warn ? " health-card--warn" : ""}">
      <span>${esc(card.label)}</span>
      <strong>${esc(card.value)}</strong>
      <p>${esc(card.detail)}</p>
    </article>
  `).join("");
}

// ─── Events timeline ──────────────────────────────────────────────────────────

const eventsState = {
  filter:  "all",
  cap:     EVENTS_INITIAL_CAP,
};

function getFilteredEvents(events) {
  if (eventsState.filter === "all") return events;
  return events.filter(e => {
    const agent = (e.payload?.agent || e.payload?.from || "").toLowerCase();
    const ev    = (e.event || "").toLowerCase();
    return agent === eventsState.filter || ev === eventsState.filter;
  });
}

function renderEventsFilters(events) {
  // Build unique agent names for filter chips
  const agents = [...new Set(
    events.map(e => e.payload?.agent || e.payload?.from || "").filter(Boolean)
  )].slice(0, 8);

  const chips = [
    { label: "All",    value: "all" },
    ...agents.map(a => ({ label: `@${a}`, value: a.toLowerCase() })),
  ];

  eventsFilters.innerHTML = chips.map(c => `
    <button
      class="filter-chip${eventsState.filter === c.value ? " is-active" : ""}"
      data-filter="${esc(c.value)}"
      type="button"
      aria-pressed="${eventsState.filter === c.value}"
    >${esc(c.label)}</button>
  `).join("");

  eventsFilters.querySelectorAll(".filter-chip").forEach(btn => {
    btn.addEventListener("click", () => {
      eventsState.filter = btn.dataset.filter;
      eventsState.cap    = EVENTS_INITIAL_CAP;
      renderEvents(window.sessionData.events);
    });
  });
}

function renderEvents(events) {
  const filtered = getFilteredEvents(events);
  const visible  = filtered.slice(0, eventsState.cap);

  if (!visible.length) {
    eventsList.innerHTML = `<li class="empty-state">No events match this filter.</li>`;
    eventsShowMore.hidden = true;
    return;
  }

  eventsList.innerHTML = visible.map(e => {
    const ts     = fmtTimestamp(e.recorded_at);
    const evName = e.event || "event";
    const agent  = e.payload?.agent || e.payload?.from || "";
    const detail = e.payload?.message || e.payload?.detail || "";
    const role   = (e.payload?.role || "").toLowerCase();
    const colorClass = ROLE_COLORS[role] || "";
    return `
      <li class="stream-item">
        <div class="stream-time">${esc(ts)}</div>
        <div class="stream-body">
          <div class="stream-headline">
            ${agent ? `<span class="stream-role ${colorClass}">${esc(agent)}</span>` : ""}
            <span class="stream-kind">${esc(evName)}</span>
            ${e.team ? `<span class="stream-kind">${esc(e.team)}</span>` : ""}
          </div>
          ${detail ? `<p class="stream-summary">${esc(detail)}</p>` : ""}
        </div>
      </li>
    `;
  }).join("");

  if (filtered.length > eventsState.cap) {
    eventsShowMore.hidden = false;
    eventsShowMore.textContent = `Show more (${filtered.length - eventsState.cap} remaining)`;
  } else {
    eventsShowMore.hidden = true;
  }
}

eventsShowMore.addEventListener("click", () => {
  eventsState.cap += EVENTS_INITIAL_CAP;
  if (window.sessionData) renderEvents(window.sessionData.events);
});

// ─── Task board ───────────────────────────────────────────────────────────────

function renderTasks(tasks) {
  const ids = Object.keys(tasks).sort((a, b) => {
    const n = s => parseInt(s.slice(1), 10);
    return n(a) - n(b);
  });

  if (!ids.length) {
    taskBoard.innerHTML = `<div class="empty-state">No tasks found in this session.</div>`;
    return;
  }

  taskBoard.innerHTML = ids.map(id => {
    const { meta, chat } = tasks[id];
    const status    = meta?.status   || "unknown";
    const driver    = meta?.driver   || "—";
    const navigator = meta?.navigator || "—";
    const advisor   = meta?.advisor  || "";
    const updated   = meta?.updated_at ? fmtTimestamp(meta.updated_at) : "";
    const statusClass = status === "completed" ? "status-done"
                      : status === "active"    ? "status-active"
                      : "status-other";

    const chatHtml = chat.length
      ? chat.map(m => `
          <div class="chat-message chat-message--${esc(m.kind)}">
            <div class="chat-meta">
              <span class="chat-from">${esc(m.from)}</span>
              <span class="chat-kind">${esc(m.kind)}</span>
              <span class="chat-time">${esc(fmtTimestamp(m.timestamp))}</span>
            </div>
            <p class="chat-body">${esc(m.message)}</p>
          </div>
        `).join("")
      : `<p class="empty-state">No chat messages.</p>`;

    return `
      <article class="task-card" id="task-${esc(id)}">
        <div class="task-card-head">
          <div class="task-title-row">
            <span class="task-id">${esc(id)}</span>
            <span class="task-status ${statusClass}">${esc(status)}</span>
          </div>
          <div class="task-roles">
            <span><span class="role-label">driver</span> <strong>${esc(driver)}</strong></span>
            <span><span class="role-label">navigator</span> <strong>${esc(navigator)}</strong></span>
            ${advisor ? `<span><span class="role-label">advisor</span> <strong>${esc(advisor)}</strong></span>` : ""}
          </div>
          ${updated ? `<div class="task-updated">Updated ${esc(updated)}</div>` : ""}
        </div>
        <details class="task-chat">
          <summary class="task-chat-toggle">
            Chat thread (${chat.length} message${chat.length !== 1 ? "s" : ""})
          </summary>
          <div class="task-chat-body">${chatHtml}</div>
        </details>
      </article>
    `;
  }).join("");
}

// ─── Advice ledger ────────────────────────────────────────────────────────────

function renderAdvice(advice) {
  // Type counts (open only)
  adviceSummary.innerHTML = ADVICE_TYPES.map(type => {
    const count = advice.filter(a => a.type === type && a.status === "open").length;
    return `
      <div class="advice-count">
        <span>${esc(type)}</span>
        <strong>${count}</strong>
      </div>
    `;
  }).join("");

  if (!advice.length) {
    adviceList.innerHTML = `<li class="empty-state">No advice items in this session.</li>`;
    return;
  }

  adviceList.innerHTML = advice.map(item => {
    const isResolved = item.status === "resolved";
    return `
      <li class="advice-item">
        <div class="advice-head">
          <span class="advice-type ${esc(item.type.toLowerCase())}">${esc(item.type)}</span>
          <span class="stream-kind">${esc(item.id)}</span>
          <span class="advice-badge ${isResolved ? "advice-badge--resolved" : "advice-badge--open"}">
            ${isResolved ? esc(item.resolution) : "open"}
          </span>
          ${item.author ? `<span class="advice-author">by ${esc(item.author)}</span>` : ""}
        </div>
        ${item.detail ? `<p>${esc(item.detail)}</p>` : ""}
        ${isResolved && item.resolutionDetail ? `
          <div class="advice-resolution">
            <span class="resolution-label">${esc(item.resolution)}</span>
            <span>${esc(item.resolutionDetail)}</span>
          </div>
        ` : ""}
      </li>
    `;
  }).join("");
}

// ─── Log viewer ───────────────────────────────────────────────────────────────

function renderLog(log) {
  if (!log.length) {
    logViewer.innerHTML = `<div class="empty-state">No log sections found. LOG.md may be empty or missing.</div>`;
    return;
  }

  logViewer.innerHTML = log.map(section => {
    const entries = section.entries.map(entry => `
      <div class="log-entry">
        <h4 class="log-entry-heading">${esc(entry.heading)}</h4>
        ${entry.body ? `<pre class="log-entry-body">${esc(entry.body)}</pre>` : ""}
      </div>
    `).join("");

    return `
      <section class="log-section">
        <div class="log-section-head">
          <span class="task-id">${esc(section.task)}</span>
          ${section.driver   ? `<span class="role-label">driver</span> <strong>${esc(section.driver)}</strong>` : ""}
          ${section.navigator ? `<span class="role-label">nav</span> <strong>${esc(section.navigator)}</strong>` : ""}
        </div>
        <div class="log-entries">${entries || '<p class="empty-state">No entries.</p>'}</div>
      </section>
    `;
  }).join("");
}

// ─── Retro viewer ─────────────────────────────────────────────────────────────

const RETRO_SECTION_LABELS = {
  team:                   "Team",
  what_worked:            "What Worked",
  what_didn_t_work:       "What Didn't Work",
  advice_system:          "Advice System",
  rotation:               "Rotation",
  process_observations:   "Process Observations",
  recommendations:        "Recommendations",
};

function renderRetro(retro) {
  if (!retro) {
    retroViewer.innerHTML = `<div class="empty-state">No RETRO.md found in this session.</div>`;
    return;
  }

  const preambleHtml = retro.preamble
    ? `<p class="retro-preamble">${esc(retro.preamble)}</p>`
    : "";

  const sectionsHtml = Object.entries(retro.sections || {}).map(([key, body]) => {
    const label = RETRO_SECTION_LABELS[key] || key.replace(/_/g, " ");
    return `
      <div class="retro-section">
        <h3 class="retro-section-title">${esc(label)}</h3>
        <p class="retro-section-body">${esc(body)}</p>
      </div>
    `;
  }).join("");

  retroViewer.innerHTML = preambleHtml + (sectionsHtml || `<p class="empty-state">No sections parsed.</p>`);
}

// ─── Main render ──────────────────────────────────────────────────────────────

function renderAll(session) {
  renderOverview(session);
  renderAgentCards(session);
  renderHealth(session);
  renderEventsFilters(session.events);
  renderEvents(session.events);
  renderTasks(session.tasks);
  renderAdvice(session.advice);
  renderLog(session.log);
  renderRetro(session.retro);
}

// ─── Scroll-spy (IntersectionObserver) ───────────────────────────────────────

function initScrollSpy() {
  const navLinks = document.querySelectorAll(".nav-link[data-section]");
  if (!navLinks.length) return;

  const sectionIds = Array.from(navLinks).map(l => l.dataset.section);
  const sections   = sectionIds.map(id => document.getElementById(id)).filter(Boolean);

  const observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          navLinks.forEach(link => {
            const isActive = link.dataset.section === entry.target.id;
            link.classList.toggle("nav-link--active", isActive);
          });
          break; // first intersecting section wins
        }
      }
    },
    { rootMargin: "-20% 0px -60% 0px", threshold: 0 }
  );

  sections.forEach(s => observer.observe(s));
}

// ─── Boot ─────────────────────────────────────────────────────────────────────

document.addEventListener("sessionloaded", (event) => {
  renderAll(event.detail);
});

// Re-render if session was already loaded before this script ran
if (window.sessionData) {
  renderAll(window.sessionData);
}

initScrollSpy();
