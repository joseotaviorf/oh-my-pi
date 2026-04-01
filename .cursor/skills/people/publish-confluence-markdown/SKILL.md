---
name: publish-confluence-markdown
description: >-
  People domain: uploads a local Markdown file to Confluence via Atlassian MCP ``updateConfluencePage``
  (or ``createConfluencePage``) with ``status: draft`` by default. New People DW 2.0 pages use
  ``parentId`` People Data Catalog (``4635951235``); ask the user if hierarchy is unclear. Use for
  ``dags/people/`` when syncing ``docs/dw_*.md`` or doc-to-wiki workflows. Full technical data models
  may live in ``docs/data_model.md`` on GitHub; the wiki page usually links there instead of embedding
  large diagrams.
---

# Publish Markdown to Confluence (MCP)

## Goal

Replace the body of a **known** Confluence page with the contents of a **Markdown file** in this repository, using the **Atlassian MCP** (`plugin-atlassian-atlassian`) tool **`updateConfluencePage`**.

## Draft-first publishing (required)

- Always set **`status`** to **`draft`** when calling **`updateConfluencePage`** or **`createConfluencePage`**, unless the user explicitly asks to publish as **`current`** (live).
- In Confluence Cloud, **`draft`** means the update is **not** the published version yet; readers with access still see the previous published version until someone **publishes** the draft from the Confluence UI.
- **Promotion to published is manual:** after a careful content review, the **owner or reviewer** opens the page in Confluence and uses **Publish** (or equivalent) so the new version becomes **`current`**. The agent must **not** assume the sync is production-ready without that step.
- The helper script `scripts/confluence/build_confluence_mcp_update_payload.py` defaults to **`--status draft`**; use **`--status current`** only when the user instructs an immediate publish.

## Prerequisites

- The **Atlassian MCP** is enabled in Cursor and authenticated (same session that can read Jira/Confluence).
- You have **`cloudId`**, **`pageId`**, **`spaceId`**, and the target **page title** (from Confluence or an existing doc link in the repo).
- Always set **`contentFormat`** to **`markdown`** when the source file is Markdown.

## People DW 2.0 — parent page for new wiki pages

- **Create** new Confluence pages for People **DW 2.0** DAG docs (`dags/people/dw_*/docs/dw_*.md`) **under [People Data Catalog](https://quintoandar.atlassian.net/wiki/spaces/team162449f9cca34903915bfe1c1c6c507e/pages/4635951235/People+Data+Catalog)**: use **`parentId`: `4635951235`** in **`createConfluencePage`** (with numeric **`spaceId`** — see `.cursor/rules/people_domain.mdc`).
- Do **not** use **Refining — DW 2.0** or other hubs as **`parentId`** unless the user explicitly instructs otherwise.
- If hierarchy is ambiguous (e.g. whether to nest under a subpage inside the Catalog), **ask the user** before creating the page.

## People Data Catalog: Confluence Database

- In repo Markdown, when pointing to a **catalog row** URL, use a **blank line** before the link line so Confluence and GitHub render it as its **own** paragraph (see **`create-dw-documentation`** / **REFERENCE_TEMPLATE.md**).
- The Atlassian **MCP does not create or edit Confluence Databases.** **Canonical catalog metadata** (**Scope**, **Progress**, **Document updated at**, etc.) lives in the **People Data Catalog** **Confluence Database** on the hub—not duplicated as a markdown table in `docs/dw_*.md` (see **`create-dw-documentation`** / **REFERENCE_TEMPLATE.md**).
- **People DW convention:** **Creating or updating** Catalog **database rows** (and any **embed / smart link** from the schema’s wiki page into that database) stays **manual** in Confluence—the same operator hygiene as other catalog edits.
- **`updateConfluencePage` replaces the whole body.** Database **embeds** and similar Confluence-only UI are **removed** on the next full sync from git **unless** someone **restores** them afterward.
- **On each publish (agent + human):**
  1. **Before sync (optional):** Call **`getConfluencePage`** with **`contentFormat`: `markdown`** and **`includeBody`: `true`** and note Confluence-only fragments (e.g. catalog database UI) that are **missing** from the repo Markdown.
  2. **After sync:** **Open the page in Confluence** and confirm the Catalog **database link or embed** is still present. If it was dropped by the replace, **restore it manually** in the editor (there is no MCP path to recreate Database rows or embeds today).
  3. Prefer **`status: draft`** for doc updates so a human can fix Catalog/database wiring **before** publishing **`current`**—this is the practical “do not wipe it” check.
- Do **not** expect automation to recreate Catalog database rows; treat them as **manually owned**, consistent with how the catalog is maintained elsewhere.

## Images and diagrams

- Relationship **diagrams** in Markdown often appear as **plain code** in Confluence, not as graphics. Prefer **PNG** under `docs/assets/` embedded with an **absolute** `https://raw.githubusercontent.com/quintoandar/bi-etl-ejuice/master/...` URL (after the asset exists on `master`), or attach images in Confluence manually.
- **GitHub companion for the full data model:** People DW docs may use a separate **`docs/data_model.md`** (entity relationships, join keys) for **GitHub** only. The **main** wiki page (`dw_*.md`) should link to it with an **absolute** URL, e.g. `https://github.com/quintoandar/bi-etl-ejuice/blob/master/dags/people/{dag}/docs/data_model.md`, so readers open the rendered diagram on GitHub. Use **plain-language** link text in the main doc (see `create-dw-documentation`). **Publish the main Confluence-target file** (`dw_*.md`); you do not need to duplicate `data_model.md` into Confluence unless the team wants both.
- Relative paths like `assets/diagram.png` may not resolve when the body is pasted into Confluence. Same-folder links like `data_model.md` may not resolve from Confluence; use the **github.com** URL for external readers.

## Avoid duplicating the page title

Confluence renders the **page title** in the header. If the Markdown body starts with an `#` heading that repeats the same text as **`title`** in the MCP call, users will see the title twice. For synced pages, **omit that leading `# …` line** in the Markdown so the title is not duplicated; the body should start at the first `##` section (often **`## People Data Catalog`** as a short hub pointer, otherwise **`## Contents`**). See `create-dw-documentation` / `REFERENCE_TEMPLATE.md` for the convention.

## Pull from Confluence, diff against Git, then update

Use this when someone edited the **wiki** (catalog database fields, wording) and you need to **reconcile** narrative in git before the next `updateConfluencePage`, or when you want to confirm Confluence matches the repo.

1. **Fetch the live page body** with **`getConfluencePage`** on **`plugin-atlassian-atlassian`**:
   - Required: **`cloudId`**, **`pageId`** (from the Confluence URL).
   - Set **`contentFormat`** to **`markdown`** so the tool returns a Markdown-oriented body you can compare to `docs/dw_*.md`.
2. **Save the returned body** to a temp file (e.g. `/tmp/confluence_page_body.md`). Parse the MCP response for the body field the tool returns (structure follows the Atlassian API wrapper).
3. **Compare** to the repo file:

   ```bash
   diff -u /tmp/confluence_page_body.md dags/people/<dag>/docs/<doc>.md
   ```

   Or use the editor’s diff view after pasting each side into a buffer.

4. **Decide the source of truth:**
   - **Git as canonical:** Copy missing **narrative** fixes from Confluence into the repo file (Description, scope, SQL examples, etc.), commit, then run **`build_confluence_mcp_update_payload.py`** and **`updateConfluencePage`** (`status: draft` unless the user asks otherwise). **Do not** treat exported catalog **Database** cells as something to paste back as a markdown table—those fields are edited **in Confluence** only.
   - **People Data Catalog Database:** **Progress**, **Confidence level**, **Document updated at**, and other catalog columns are **manual** in the **Confluence Database** on the hub (see **`create-dw-documentation`** / **REFERENCE_TEMPLATE.md**). They are **not** maintained in git.
   - **Confluence-only tweaks you do not want in Git:** Avoid relying on them — the next full-body sync from Git **overwrites** the page. Prefer moving that text into the repo Markdown first. **Confluence Database** embeds and similar macros **cannot** be represented in repo Markdown—**restore manually** after sync (see **People Data Catalog: Confluence Database**).

5. **Round-trip caveats:** Confluence may **normalize** Markdown (lists, tables, smart links). A **line-identical** match after export is not guaranteed even when content is equivalent. Macros and some widgets may **not** round-trip through **`markdown`** export; for those, treat Confluence as the editor of record for that fragment or simplify to plain Markdown in Git.

6. **Verify after publish:** Call **`getConfluencePage`** again with **`contentFormat`: `markdown`** and compare to what you intended (no `includeBody` flag is required in the MCP schema — the tool returns page content per its response shape).

## Steps (agent)

1. **Identify inputs**:
   - Path to the Markdown file (e.g. `dags/people/dw_demographics/docs/dw_demographics.md`).
   - Confluence identifiers: `cloudId`, `pageId`, `spaceId`, **`title`**, and a short `versionMessage` (e.g. `Sync from dw_demographics.md (bi-etl-ejuice)`). For **People DW** docs, set **`--title`** to the same string as the Markdown **H1** without the leading `#` (e.g. `DW Demographics - DE&I Data: dw_demographics`) so the wiki page title matches the repo pattern.

2. **Build the MCP arguments** (preferred):
   - From the repo root, run (draft is the default; omit `--status` unless you need `--status current`):

   ```bash
   python3 scripts/confluence/build_confluence_mcp_update_payload.py \
     --markdown "<path-to-markdown>" \
     --cloud-id "<cloud-uuid>" \
     --page-id "<page-id>" \
     --space-id "<space-id>" \
     --title "<page title>" \
     --version-message "<short message>" \
     --output /tmp/confluence_update_args.json
   ```

   - Optionally omit `--output` to print one line of JSON to stdout.

3. **Invoke MCP**:
   - Call **`updateConfluencePage`** on server **`plugin-atlassian-atlassian`** with **`arguments`** set to the **parsed JSON object** (same keys as in `updateConfluencePage.json`: required `cloudId`, `pageId`, `body`; optional `title`, `spaceId`, `contentFormat`, `versionMessage`, **`status`** (`draft` \| `current`), etc.).
   - **Always include `"status": "draft"`** in the object when building the payload by hand (the script emits this by default).
   - Do **not** send `arguments` as a file path string; the tool expects a JSON **object** with a string `body`.

4. **Verify**:
   - Call **`getConfluencePage`** with **`contentFormat`: `markdown`** and confirm the returned body matches expectations; confirm the page stays **draft** until the user publishes in the Confluence UI.

5. **Delete the payload file after success**:
   - If you used **`--output`** (or wrote a JSON file anywhere under the repo, e.g. `.cursor/confluence_update_args.json`), **remove that file** once `updateConfluencePage` has succeeded and you no longer need it for debugging.
   - Prefer writing payloads to **`/tmp/`** so they disappear on reboot; if the file lives in **`.cursor/skills/people/publish-confluence-markdown/`**, names matching **`_*.json`** are **gitignored** as a backup, but the agent should still **delete** them after a successful publish to avoid stale copies and noise in the workspace.

## Large payloads

For long documents (~15k+ characters JSON), generating the payload via the script and loading it in a controlled way avoids truncation. If the tool interface cannot embed the full object in one step, emit JSON to a temp file (`--output`), then pass the **full parsed object** to `updateConfluencePage` (schema matches the MCP tool descriptor for `updateConfluencePage`: required `cloudId`, `pageId`, `body`; optional `contentFormat`, `title`, `spaceId`, `versionMessage`, **`status`**, etc.).

## No MCP (CI or headless)

This skill targets **Cursor + Atlassian MCP**. For automation **outside** Cursor, use the **Confluence Cloud REST API** with an API token and scoped scopes (e.g. `write:page:confluence`); request body shapes differ from MCP. Do not commit tokens or secrets.

## What automation covers vs. what stays manual

- **Within Cursor**: the agent can run the script, call `updateConfluencePage` with **`status: draft`**, and verify—**no copy-paste** by the user—as long as the MCP is connected.
- **One-time setup** still applies: **MCP auth** and **Confluence permissions** must already work for the user’s account.
- **Publishing the draft** (making the new version visible as the live page) is **not** automated here: the user does that in Confluence after review.
- **People Data Catalog database:** **Row creation, row edits, and doc↔database embeds** are **manual** in Confluence. Full-body Markdown sync **can strip** those embeds—**restore in the UI** after sync when needed (see **People Data Catalog: Confluence Database** above).
