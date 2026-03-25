# DBP Jira — reference cache (Data People)

**Purpose:** Stable, reusable facts about Jira for the Data People squad (project **DBP**): IDs, URLs, API quirks, kickoff policies, branch/slug/Jira summary norms, and workflow — usually learned once via Jira/API or squad norms. **Read this file before** opening a Jira/MCP call for the same fact. After you discover something durable (field name, issue type string, cloud id), **add it here** in the same delivery so the next run skips the lookup. If Atlassian configuration changes, update this file when you adjust the process.

**Location:** `.cursor/rules/people/dbp-jira-reference.md` — People rules companion; **delivery procedures** live under **`.cursor/skills/people/*/`** (see **Related delivery skills** below).

---

## Project and URLs

| Item | Value |
|------|--------|
| **Project key** | `DBP` |
| **Issue key pattern** | `DBP-<number>` (e.g. `DBP-1234`) |
| **Site** | https://quintoandar.atlassian.net/ |
| **Cloud ID** (REST / MCP `cloudId`) | `8a4667b7-87a1-4c6c-805c-fc0d6e60a7a0` |

---

## MCP (Cursor workspace)

| Item | Note |
|------|------|
| **Server** (typical) | `plugin-atlassian-atlassian` |
| **Parameters** | Pass **`cloudId`** from **Project and URLs** above, project **DBP**, and obey **API and automation quirks** below (issue types, `parent`, description format). |
| **Rule file** | For create/edit payloads (e.g. markdown `description`, DBP field conventions), use the **Atlassian Jira MCP** rule under **`.cursor/rules/`** for this repository — do not re-derive from scratch each session. |

---

## API and automation quirks

| Topic | Note |
|--------|------|
| **Issue type on create** | Use **English** API names (e.g. **`Sub-task`**). Localized UI labels (e.g. “Subtarefa”) often **fail** create validation. |
| **Sub-tasks** | Creating a sub-task requires a valid **`parent`** (parent issue key). |
| **Descriptions** | Prefer the format your Atlassian integration expects (often **Atlassian Document Format** or **markdown**, depending on tool); if a write fails, check the tool’s schema rather than guessing. |

_Add rows to this table when you hit a repeatable API gotcha._

---

## Team conventions (not enforced by Jira schema)

| Topic | Convention |
|--------|------------|
| **Buffer / unplanned work** | **`[buffer]`** at the **start** of the issue **summary**; **no story points**. Meaning and cadence → **Sprints and buffer (DBP)** below. |
| **PR title (later)** | `DBP-xxxx \| short description` — same brevity as branch slug; body template in **`.cursor/rules/pr_template.mdc`**. |

### Sprints and buffer (DBP)

- **Cadence:** The **DBP** Jira project runs **two-week sprints**.
- **Planning:** Before each sprint, **Sprint planning** defines which **Stories** are in scope and their **story points** (estimation).
- **Execution:** During the sprint, those Stories are worked and usually **broken down into Sub-tasks** (the typical unit for day-to-day implementation).
- **Buffer (unplanned work):** Work that enters the sprint **without having been planned** in that sprint’s planning. For any such issue (usually a **Story**):
  - put the **`[buffer]`** prefix at the **beginning** of the **summary** (e.g. `[buffer] Add logging to pin_core sync`);
  - **do not** assign story points — buffer items are **never** pointed.
- **Who decides:** Whether work is **planned vs buffer** comes from the **team / PM / sprint board**, not from the agent. The reference documents the rule; the user confirms the issue type when creating or labeling work.

### Language (Jira content)

Jira **summary**, **description**, and **comments** → **English**. Chat with the user may be any language.

### Kickoff policies (before branch)

- **Ticketed work:** A DBP **Story** or **Sub-task** must exist or be created **before** creating a Git branch. Do **not** create a branch without a linked issue.
- **Sub-task:** The user must provide the **parent** issue key (Story/Epic). The agent **must not** guess the parent.
- **Duplicate issues:** Whether a Jira issue already exists for the topic is the **user’s responsibility**; the agent creates/updates only after user confirmation.
- **Local-only:** If the user explicitly declares **local-only** work, skip Jira/branch kickoff (always-applied workspace rules may still apply — do not run the full People delivery workflow unless asked).

### Branch, slug, and Jira summary

- **Branch key (segment before `/`):** Use the **most specific** issue you are executing — the **narrowest** key in scope. Example: work is **Sub-task DBP-1268** under Story DBP-1267 → branch **`DBP-1268/...`**, not `DBP-1267/...`, unless the team explicitly tracks work only on the Story.
- **Branch shape:** `{KEY}/{slug}` — **slug** = English **kebab-case** after `KEY/` (typically **2–4** hyphen-separated words). First chunk = **imperative verb** + main object; add another chunk only if two domains are clearly in scope. Example: `DBP-1268/add-cursor-skills`.
- **Slug + Jira summary:** Short labels only; details go in the Jira **description**. **Jira summary** aligns with the slug (verb + object), **one line**; unplanned sprint work → **`[buffer]`** + no points per **Sprints and buffer (DBP)** above.

**Preferred first verbs for slug/summary:** `Add`, `Update`, `Fix`, `Remove`, `Refactor`, `Align`, `Extend`, `Migrate`, `Document`.

---

## Workflow snapshot (status names)

DBP uses a standard sequence; exact transition IDs vary by issue type/workflow — use **`getTransitionsForJiraIssue`** when you need the live transition list, not the label text alone.

**Typical path:** `ABERTO` → `READY FOR SPRINT` → `TAREFAS PENDENTES` → `EM ANDAMENTO` → (`IN BLOCK` / `IN TEST` / `IN CODE REVIEW`) → `READY TO PROD` → `CONCLUÍDA`. **Other:** `ROLLED OVER`, `CANCELADA`.

**Delivery hints (squad):** coding start → **`EM ANDAMENTO`**; validation before PR → **`IN TEST`**; PR in review → **`IN CODE REVIEW`**.

**Status labels vs language:** DBP workflow names are **not** all English in the UI — you may see Portuguese (e.g. **Em andamento**) mixed with English (**In Code Review**). Squad docs use the **canonical transition/status strings** above for alignment with internal process. **What matters for automation** is the **transition id/name returned by the API** (`getTransitionsForJiraIssue` / MCP), not guessing from English-only labels. Issue **content** (summary, description, comments) stays **English** per **Language (Jira content)**.

---

## Extending this cache

Add subsections or tables for **custom field IDs**, **components**, **labels**, **priority names**, **board/JQL filters**, or **parent epic keys** once confirmed — only facts that stay true across tickets until config changes.

---

## When a Jira/API call is still required

Authoritative **current** assignee, description, comments, **today’s** status, available **transitions**, or anything **ticket-specific**. This file is a **cache of stable context**, not a substitute for reading an issue you are actively working.

---

## Related delivery skills

Read **this reference** before Jira/MCP steps in any of these (each skill lives under **`.cursor/skills/people/<folder>/SKILL.md`** with YAML **`name`**):

| Skill `name` | Role |
|----------------|------|
| **`people-jira-branch-setup`** | Jira + Git: branch from `origin/master` / `origin/HEAD` — **procedural** steps in the skill; **`.cursor/temp/`** layout → **`people/people_domain.mdc`** (**Delivery artifact folder**); policies and naming → **this file**. |

Other People skills added later under **`.cursor/skills/people/*/`** should still read **this reference** before Jira/MCP steps.
