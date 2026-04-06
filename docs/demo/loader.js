/**
 * loader.js — Folder picker glue for the session viewer
 *
 * Wires up both <input webkitdirectory> elements (empty-state + toolbar)
 * to parseSessionFolder(), then exposes the result on window.sessionData
 * and fires a "sessionloaded" CustomEvent so app.js can react.
 *
 * State machine (body[data-loaded]):
 *   absent  → show .loader-empty, hide .page-shell
 *   present → hide .loader-empty, show .loader-toolbar + .page-shell
 */

import { parseSessionFolder } from "./parser.js";

const loaderEmpty = document.getElementById("loader-empty");
const loaderToolbar = document.getElementById("loader-toolbar");
const toolbarTeamName = document.getElementById("toolbar-team-name");
const toolbarMeta = document.getElementById("toolbar-meta");
const loaderHint = document.getElementById("loader-hint");
const loaderErrors = document.getElementById("loader-errors");
const pageShell = document.getElementById("page-shell");

// ─── State transition helpers ─────────────────────────────────────────────────

function showLoading(hint) {
  loaderHint.textContent = hint || "Loading…";
}

function showError(message) {
  loaderHint.textContent = message;
}

function transitionToLoaded(session) {
  // Update toolbar
  toolbarTeamName.textContent = session.teamName;

  const taskCount = Object.keys(session.tasks).length;
  const eventCount = session.events.length;
  const adviceCount = session.advice.length;
  toolbarMeta.textContent =
    `${taskCount} task${taskCount !== 1 ? "s" : ""} · ${eventCount} event${eventCount !== 1 ? "s" : ""} · ${adviceCount} advice item${adviceCount !== 1 ? "s" : ""}`;

  // Surface non-fatal parse errors
  if (session.errors.length > 0) {
    loaderErrors.removeAttribute("hidden");
    loaderErrors.innerHTML = session.errors
      .map((e) => `<span>${e}</span>`)
      .join("");
  } else {
    loaderErrors.setAttribute("hidden", "");
  }

  // Swap UI states
  document.body.setAttribute("data-loaded", "true");
  loaderEmpty.setAttribute("aria-hidden", "true");
  loaderToolbar.removeAttribute("hidden");
  loaderToolbar.setAttribute("aria-hidden", "false");
  pageShell.removeAttribute("hidden");
  pageShell.setAttribute("aria-hidden", "false");
}

// ─── Session loading ──────────────────────────────────────────────────────────

async function loadFromFileList(fileList) {
  if (!fileList || fileList.length === 0) return;

  showLoading("Parsing session artifacts…");

  try {
    const session = await parseSessionFolder(fileList);

    // Make the data model globally available for app.js and the console
    window.sessionData = session;

    transitionToLoaded(session);

    // Notify app.js (or any other listener) that fresh data is ready
    document.dispatchEvent(
      new CustomEvent("sessionloaded", { detail: session, bubbles: false }),
    );
  } catch (err) {
    showError(`Parse failed: ${err.message}`);
    console.error("[loader] parseSessionFolder error:", err);
  }
}

// ─── Input wiring ─────────────────────────────────────────────────────────────

function wireInput(input) {
  if (!input) return;
  input.addEventListener("change", (event) => {
    loadFromFileList(event.target.files);
    // Reset input so the same folder can be re-selected if needed
    event.target.value = "";
  });
}

wireInput(document.getElementById("folder-picker"));
wireInput(document.getElementById("folder-picker-toolbar"));
