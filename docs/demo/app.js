const lanes = [
  {
    role: "driver",
    label: "Current",
    agent: "implementer",
    task: "T7",
    phase: "driving",
    summary: "Building the static replay surface in docs/demo while holding the only write seat.",
    channel: "tasks/T7/back-forth.md",
    status: "Owns the in-flight implementation.",
  },
  {
    role: "navigator",
    label: "Future",
    agent: "designer",
    task: "T8",
    phase: "waiting_on_driver",
    summary: "READY published with hierarchy, role clarity, and responsive-stream guidance.",
    channel: "navigator-ready-designer-T8.md",
    status: "Read-ahead is already done.",
  },
  {
    role: "advisor",
    label: "Past",
    agent: "verifier",
    task: "T9",
    phase: "reviewing",
    summary: "Tracking terminology and preparing lightweight local verification for the final artifact.",
    channel: "ADVICE.md + review cursor",
    status: "Checks that landed work matches the repo language.",
  },
];

const advice = [
  {
    type: "STEER",
    id: "STR-7-01",
    status: "open",
    from: "designer",
    task: "T7",
    detail:
      "Make subagent mode and file-bus coordination explicit; do not imply native live peer chat or team-mode transport.",
  },
  {
    type: "FYI",
    id: "FYI-9-01",
    status: "open",
    from: "verifier",
    task: "T9",
    detail:
      "Keep mocked/live labeling visible so the replay reads as a believable demonstration rather than a hooked runtime console.",
  },
  {
    type: "SMELL",
    id: "SML-7-01",
    status: "noted",
    from: "designer",
    task: "T7",
    detail:
      "If the stream becomes too dashboard-like, collapse chrome and let the activity list carry the hierarchy.",
  },
];

const feed = [
  {
    time: "04:13:20Z",
    role: "control",
    kind: "brief",
    task: "T7",
    agent: "lead",
    summary: "Lead opens a demo slice for watching active subagent streams.",
    note: "Writes stay isolated to docs/demo/*.",
    path: "tasks/T7/back-forth.md",
  },
  {
    time: "04:14:30Z",
    role: "navigator",
    kind: "assignment",
    task: "T8",
    agent: "designer",
    summary: "Navigator assigned to visual hierarchy, stream readability, and role-lane semantics.",
    note: "Poster-like first impression; avoid card-grid filler.",
    path: "tasks/T8/back-forth.md",
  },
  {
    time: "04:14:50Z",
    role: "navigator",
    kind: "ready",
    task: "T8",
    agent: "designer",
    summary: "READY published with a calm operations-console direction and explicit mock/live labeling.",
    note: "Three lanes, one central stream, durable file-bus cues.",
    path: "navigator-ready-designer-T8.md",
  },
  {
    time: "04:15:07Z",
    role: "advisor",
    kind: "plan",
    task: "T9",
    agent: "verifier",
    summary: "Verification lane activates against README terminology and local-open behavior.",
    note: "Role semantics are treated as real defects if wrong.",
    path: "tasks/T9/back-forth.md",
  },
  {
    time: "04:17:02Z",
    role: "driver",
    kind: "claim",
    task: "T7",
    agent: "implementer",
    summary: "Drive seat corrected to implementer and the task bus marks T7 active.",
    note: "Only one write seat remains live.",
    path: "tasks/T7/meta.json",
  },
  {
    time: "04:17:31Z",
    role: "driver",
    kind: "checkpoint",
    task: "T7",
    agent: "implementer",
    summary: "The demo splits into static HTML, CSS, and JavaScript to stay framework-free and reviewable.",
    note: "The artifact remains self-contained for lightweight verification.",
    path: "docs/demo/",
  },
  {
    time: "04:17:45Z",
    role: "navigator",
    kind: "steer",
    task: "T7",
    agent: "designer",
    summary: "The navigator pushes the surface toward explicit subagent semantics rather than faux realtime chat.",
    note: "Current/future/past must read in one glance.",
    path: "ADVICE.md",
  },
  {
    time: "04:18:12Z",
    role: "driver",
    kind: "checkpoint",
    task: "T7",
    agent: "implementer",
    summary: "The live stream begins replaying task chat, typed advice, and session-health shifts.",
    note: "Replay is mocked but grounded in current repo vocabulary.",
    path: "docs/demo/app.js",
  },
  {
    time: "04:18:32Z",
    role: "advisor",
    kind: "review",
    task: "T9",
    agent: "verifier",
    summary: "The advisor confirms that driver=current work, navigator=read-ahead, advisor=review of landed work.",
    note: "README terms stay intact.",
    path: "README.md",
  },
  {
    time: "04:18:54Z",
    role: "driver",
    kind: "handoff",
    task: "T7",
    agent: "implementer",
    summary: "The artifact settles into a verification-ready state for a local browser pass.",
    note: "Next step is to load the static files and confirm the replay controls.",
    path: "docs/demo/index.html",
  },
];

const state = {
  filter: "all",
  paused: false,
  visibleCount: 6,
};

const roleTitles = {
  control: "Lead",
  driver: "Driver",
  navigator: "Navigator",
  advisor: "Advisor",
};

const summaryMetrics = document.querySelector("#summary-metrics");
const roleLanes = document.querySelector("#role-lanes");
const streamList = document.querySelector("#stream-list");
const adviceSummary = document.querySelector("#advice-summary");
const adviceList = document.querySelector("#advice-list");
const healthGrid = document.querySelector("#health-grid");
const streamStatus = document.querySelector("#stream-status");
const headlineStatus = document.querySelector("#headline-status");

function renderSummary() {
  const visible = feed.slice(0, state.visibleCount);
  const liveCount = visible.filter((entry) => entry.role !== "control").length;
  const latest = visible[visible.length - 1];
  const metrics = [
    {
      label: "runtime",
      value: "subagent",
      note: "file bus + session files",
    },
    {
      label: "visible entries",
      value: String(visible.length).padStart(2, "0"),
      note: `${liveCount} teammate updates in replay`,
    },
    {
      label: "latest lane",
      value: latest ? roleTitles[latest.role] : "Lead",
      note: latest ? `${latest.agent} on ${latest.task}` : "waiting",
    },
  ];

  summaryMetrics.innerHTML = metrics
    .map(
      (metric) => `
        <div class="metric-row">
          <div>
            <span>${metric.label}</span>
            <strong>${metric.value}</strong>
          </div>
          <span>${metric.note}</span>
        </div>
      `,
    )
    .join("");

  headlineStatus.textContent = `sweep-v85-v95 / ${state.paused ? "replay paused" : "mocked live replay"}`;
}

function renderLanes() {
  const visible = feed.slice(0, state.visibleCount);
  roleLanes.innerHTML = lanes
    .map((lane) => {
      const latest = [...visible].reverse().find((entry) => entry.role === lane.role);
      return `
        <article class="lane-card" data-role="${lane.role}">
          <div class="lane-topline">
            <span class="lane-label">${lane.label}</span>
            <span class="lane-pill ${lane.role}">${lane.phase.replaceAll("_", " ")}</span>
          </div>
          <h3>${roleTitles[lane.role]}</h3>
          <p class="lane-agent">@${lane.agent} / ${lane.task}</p>
          <p class="lane-summary">${lane.summary}</p>
          <div class="lane-meta">
            <div class="lane-meta-row">
              <span>channel</span>
              <strong>${lane.channel}</strong>
            </div>
            <div class="lane-meta-row">
              <span>latest</span>
              <strong>${latest ? latest.kind : "waiting"}</strong>
            </div>
            <div class="lane-meta-row">
              <span>role job</span>
              <strong>${lane.status}</strong>
            </div>
          </div>
        </article>
      `;
    })
    .join("");
}

function renderStream() {
  const visible = feed
    .slice(0, state.visibleCount)
    .filter((entry) => state.filter === "all" || entry.role === state.filter);

  streamList.innerHTML = visible
    .map(
      (entry) => `
        <li class="stream-item">
          <div class="stream-time">${entry.time}</div>
          <div class="stream-body">
            <div class="stream-headline">
              <span class="stream-role ${entry.role}">${roleTitles[entry.role]}</span>
              <span class="stream-kind">${entry.kind}</span>
              <span class="stream-kind">${entry.task}</span>
            </div>
            <p class="stream-summary">${entry.summary}</p>
            <div class="stream-meta">
              <span><code>${entry.path}</code></span>
              <span>${entry.note}</span>
            </div>
          </div>
        </li>
      `,
    )
    .join("");
}

function renderAdvice() {
  const types = ["OBJECTION", "SMELL", "STEER", "FYI"];
  adviceSummary.innerHTML = types
    .map((type) => {
      const count = advice.filter((item) => item.type === type && item.status === "open").length;
      return `
        <div class="advice-count">
          <span>${type}</span>
          <strong>${count}</strong>
        </div>
      `;
    })
    .join("");

  adviceList.innerHTML = advice
    .map(
      (item) => `
        <li class="advice-item">
          <div class="advice-head">
            <span class="advice-type ${item.type.toLowerCase()}">${item.type}</span>
            <span class="stream-kind">${item.id}</span>
            <span class="stream-kind">${item.status}</span>
          </div>
          <p>${item.detail}</p>
          <div class="advice-meta">
            <span>@${item.from}</span>
            <span>${item.task}</span>
          </div>
        </li>
      `,
    )
    .join("");
}

function renderHealth() {
  const visible = feed.slice(0, state.visibleCount);
  const openAdvice = advice.filter((item) => item.status === "open").length;
  const latestDriver = [...visible].reverse().find((entry) => entry.role === "driver");
  const health = [
    {
      label: "Task bus",
      value: "T7 · T8 · T9",
      detail: "drive, navigate, and verify stay in separate lanes.",
    },
    {
      label: "Open advice",
      value: String(openAdvice),
      detail: "No open OBJECTIONs; guidance remains non-blocking.",
    },
    {
      label: "Driver seat",
      value: latestDriver ? `@${latestDriver.agent}` : "unclaimed",
      detail: "One active write surface keeps the pair legible.",
    },
    {
      label: "Review cursor",
      value: `${Math.min(21, 13 + state.visibleCount)} / 21`,
      detail: "Advisor review nearly catches up as the replay advances.",
    },
    {
      label: "Durable files",
      value: "LOG.md + ADVICE.md",
      detail: "Checkpoints and typed advice stay append-only.",
    },
    {
      label: "Mock/live label",
      value: "always on",
      detail: "The replay never pretends to be wired to live hooks.",
    },
  ];

  healthGrid.innerHTML = health
    .map(
      (item) => `
        <article class="health-card">
          <span>${item.label}</span>
          <strong>${item.value}</strong>
          <p>${item.detail}</p>
        </article>
      `,
    )
    .join("");
}

function render() {
  renderSummary();
  renderLanes();
  renderStream();
  renderAdvice();
  renderHealth();
  streamStatus.textContent = state.paused ? "Replay paused" : "Replay running";
}

function setFilter(nextFilter) {
  state.filter = nextFilter;
  document.querySelectorAll(".filter-chip").forEach((button) => {
    const isActive = button.dataset.filter === nextFilter;
    button.classList.toggle("is-active", isActive);
    button.setAttribute("aria-pressed", String(isActive));
  });
  renderStream();
}

function advanceReplay() {
  if (state.paused || state.visibleCount >= feed.length) {
    return;
  }
  state.visibleCount += 1;
  render();
}

document.querySelectorAll(".filter-chip").forEach((button) => {
  button.addEventListener("click", () => setFilter(button.dataset.filter));
});

document.querySelector("#pause-toggle").addEventListener("click", (event) => {
  state.paused = !state.paused;
  event.currentTarget.setAttribute("aria-pressed", String(state.paused));
  event.currentTarget.textContent = state.paused ? "Resume replay" : "Pause replay";
  render();
});

document.querySelector("#replay-feed").addEventListener("click", () => {
  state.visibleCount = 4;
  state.paused = false;
  document.querySelector("#pause-toggle").setAttribute("aria-pressed", "false");
  document.querySelector("#pause-toggle").textContent = "Pause replay";
  render();
});

render();
window.setInterval(advanceReplay, 2600);
