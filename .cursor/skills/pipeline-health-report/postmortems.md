# Postmortems (Google Drive)

Canonical folder: [Postmortems](https://drive.google.com/drive/folders/1-Hxx5YPtJmeKhoNe2zW5P9Iohf7Cg_Oi)  
`folderId`: `1-Hxx5YPtJmeKhoNe2zW5P9Iohf7Cg_Oi`

MCP: `plugin-google-drive-google-drive`. Call `mcp_auth` `{}` if `needsAuth`. Then `search_files` / `read_file_content`. Never invent a `fileId`.

## Layout

| Item | Role |
|------|------|
| Year folders (`2026`, `2025`, …) | Real PMs live here. Resolve the folder for `YEAR(dt_from)` (and previous year if the window crosses 1 Jan). |
| `PostmortemSummary` spreadsheet | Optional index (huge). Do **not** `read_file_content` the whole sheet. Prefer listing the year folder. |
| `Postmortem - Template`, `Copy of …`, `🧯 Post Mortem - Process Guideline` | Skip. |
| `Zombie PMs`, `Oncall Monthly`, `AttachedFiles` | Skip for the ritual. |

Year folder example (2026): `1-yazfhow9fvl8KTCCyGMT_OkpPJZs7jm` — **look up by title** each year; do not hardcode forever.

```
parentId = '1-Hxx5YPtJmeKhoNe2zW5P9Iohf7Cg_Oi' and mimeType = 'application/vnd.google-apps.folder' and title = '2026'
```

## Title convention

`YYYYMMDD - Team - Postmortem - Title`  
also `YYYYMMDD_HHMMSS - Postmortem - …` and `DDMMYYYY - Postmortem - …`.

Parse the **incident date** from the leading `YYYYMMDD` (or `YYYYMMDD_HHMMSS`). `DDMMYYYY` only when the first 8 digits are not a valid ISO date.

PMs are often **written 0–2 days after** the SLA miss. Keep files whose parsed date is in `[dt_from - 1, dt_to + 2]`.

## Search (after missed-DAG list exists)

1. List Docs in the year folder (`excludeContentSnippets: true`, paginate `nextPageToken`):

```
parentId = '<YEAR_FOLDER_ID>' and mimeType = 'application/vnd.google-apps.document'
```

2. Drop titles containing `Template`, `Copy of`, or `Process Guideline`. Keep `[WIP]` only if the title names a missed DAG.

3. Keep a file if **any** of:
   - Parsed date overlaps the ritual window (with +2 day slack).
   - Title or snippet mentions a missed `id_dag` / bare DAG name, `bietlejuice`, `Airflow`, `Databricks`, `Glue`, `Trino`, `SLA`, or the team `line_name`.
   - Title is a platform outage that can explain a multi-DAG miss day (Salesforce, Glue, Trino, Databricks, Amplitude, Hubspot, Luigi Jr).

4. Cap **reads** at ~8 files. Prefer: (a) title contains a missed DAG, (b) Data / Data Platform / Data Growth (or the target line), (c) platform outage on a day with `sla < 95`.

5. `read_file_content` those IDs. Extract **Summary**, **Impact**, **Causes**, **Trigger**, **Timeline (UTC -3)**. Ignore Owner/Contributors tables (do not copy people names into the report).

## Match to SLA misses

A PM **covers** a DAG×day when:

- Timeline or title date equals `dt_snapshot` (or the previous calendar day for overnight incidents), **and**
- Body/title names that DAG, an upstream producer, or a shared platform that would delay many DAGs.

Then overlay the technical bucket from `SKILL.md` §2:

| PM kind | Primary cause |
|---------|----------------|
| Platform / shared infra (Databricks, Airflow, Glue, Trino, Salesforce, Amplitude, …) | **Postmortem (plataforma)** — even if upstreams also missed (that is the cascade *symptom*) |
| This team's DAG or pipeline | **Postmortem (time)** — even if classified as falha/duração própria |
| Other team's product (not in our upstream set) | Cite as **context only**; do not steal the primary bucket |

Always link `viewUrl`. One PM may explain many DAGs on the same day — say so once, then reference it.

If Drive MCP fails, continue the ritual without PMs and note the gap.
