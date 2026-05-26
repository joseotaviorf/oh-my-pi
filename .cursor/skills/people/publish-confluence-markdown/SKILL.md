---
name: publish-confluence-markdown
description: >-
  Uploads a local Markdown file to Confluence via Atlassian MCP.
  Focuses on API interaction and compatibility (Draft status, Page Hierarchy, Title stripping).
---

# Publish Markdown to Confluence (MCP)

## Goal

Replace the body of a Confluence page with Markdown content, ensuring **draft-first** safety and correct **parent-child** hierarchy.

## Prerequisites

- **Atlassian MCP** (`plugin-atlassian-atlassian`) is enabled and authenticated.
- You have **`cloudId`**, **`pageId`**, **`spaceId`**, and the target **page title** when calling the API.
- For Markdown source files, use **`contentFormat: markdown`**.

## Confluence identifiers (People Data — single source of truth)

Do **not** copy long ID tables into this skill. For **`cloudId`**, numeric **`spaceId`**, **`parentId`** (**People Data Catalog**), hub URLs, and MCP notes, use **[`.cursor/rules/people/people_domain.mdc`](../../../rules/people/people_domain.mdc)** — section **Confluence — People Data space (Atlassian MCP)**.

## API compatibility & title hygiene

- **Avoid double titles:** Confluence shows the page title in the header. **Omit the leading `# H1` line** from the body passed to **`updateConfluencePage`** if the **`title`** argument matches that heading.
- **Draft-first (required):** always set **`status`** to **`draft`** unless the user explicitly asks otherwise.
- **Version message:** include a short description (e.g. `Sync from bi-etl-ejuice Git: docs/dw_compensation.md`).
- **Parent IDs:** new **People DW 2.0** pages use **`parentId: 4635951235`** (People Data Catalog) — confirm in **`people_domain.mdc`**. If hierarchy is unclear, ask the user before creating a page.

## Before overwriting wiki-only edits (optional)

If editors may have changed Confluence **without** git, optionally call **`getConfluencePage`** (`contentFormat: markdown`) and **diff** against the repo file **before** **`updateConfluencePage`**, so you do not blindly wipe manual narrative. **Catalog Database** cell values stay edited in Confluence — never paste them as a markdown table into git (see **`people_domain.mdc`**).

## People Data Catalog: Confluence Database

- **Manual restoration:** syncing Markdown **replaces the whole body**. Confluence-only UI (e.g. **Database** embeds) can be removed.
- **Step:** after sync, open the **draft** in Confluence and **manually restore** any Database embeds or Smart Links if they were dropped.

## Images and diagrams

- Prefer **PNG** under `docs/assets/` with **`https://raw.githubusercontent.com/quintoandar/bi-etl-ejuice/master/...`** URLs so Confluence loads the asset (after it exists on `master`).
- **`docs/data_model.md`** may stay **GitHub-only**; the wiki page can link with an absolute **github.com** URL. See **`sync-dw-documentation`** / **`REFERENCE_TEMPLATE.md`**.

## Steps (agent)

1. **Prepare payload:** from repo root, run **`packages/bietlejuice-compiler/scripts/confluence/build_confluence_mcp_update_payload.py`** (e.g. `python3 packages/bietlejuice-compiler/scripts/confluence/build_confluence_mcp_update_payload.py`) with **`--markdown`**, **`--cloud-id`**, **`--page-id`**, **`--space-id`**, **`--title`**, **`--version-message`**, and (by default) **draft** status; use **`--output`** under **`/tmp/`** when helpful.
2. **Title handling:** ensure the Markdown **body** does not duplicate the Confluence **`title`** (strip the leading `# …` line from the body when they match).
3. **Invoke MCP:** call **`updateConfluencePage`** on **`plugin-atlassian-atlassian`** with **`status: draft`**, **`contentFormat: markdown`**, and a clear **`versionMessage`**. For **new** pages, use **`createConfluencePage`** with the same hygiene and **`parentId`** when applicable.
4. **Verification:** confirm the page in the Confluence UI (draft vs current, embeds restored if needed).
5. **Cleanup:** delete temporary JSON / payload files under **`/tmp/`** (or other paths) after success.

## Large payloads & automation scope

- For very long bodies, prefer the **build script** + JSON payload to avoid truncation.
- **Promotion to `current`** is **manual** in Confluence after human review unless the user explicitly requests **`--status current`**.
- **Catalog Database rows** are **not** created or edited by MCP—maintain them in Confluence; see **`sync-dw-documentation`** for git vs Database boundaries.

## No MCP (CI or headless)

Outside Cursor, use the **Confluence Cloud REST API** with appropriate scopes; do not commit tokens or secrets.
