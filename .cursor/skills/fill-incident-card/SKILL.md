---
name: fill-incident-card
description: Fill DEI (Data Engineering Incidents) Jira incident cards with Problem, Cause, Solution, and all structured fields (Root Cause Resolution, Incident Status, Incident Category, Incident Owner, SLA affected, Failed Task). Use when the user shares DEI Jira URLs, says "fill the incident card", "preencha o card de incidente", or needs to document an on-call incident.
---

# Fill Incident Card

Fills one or more DEI board incident cards via Atlassian MCP.

## Atlassian Config

- **cloudId:** `8a4667b7-87a1-4c6c-805c-fc0d6e60a7a0`
- **MCP server:** `plugin-atlassian-atlassian`
- **Tool:** `editJiraIssue`

## Field IDs & Allowed Values

### `customfield_11194` — Root Cause Resolution
| Value | ID |
|---|---|
| Discovery | `12401` |
| Fixed | `12403` |
| Not Fixed | `12404` |

### `customfield_21698` — Incident Status
| Value | ID |
|---|---|
| Under investigation | `69333` |
| Hot Fixed | `69334` |
| Bypass | `69335` |

### `customfield_11195` — Incident Category
| Value | ID |
|---|---|
| Airflow | `12406` |
| Coding | `12408` |
| Authentication issue | `12416` |
| Third-party service failure | `74075` |
| Third-party data issue | `74074` |
| Pipeline Performance | `69338` |
| Delta | `68072` |
| Databricks availability | `69337` |
| CDC | `68073` |
| Data Quality | `69290` |
| Hive Metastore | `14884` |
| Mediator | `17331` |
| Trino metadata propagator | `15720` |
| Unity Catalog | `69336` |
| Not an incident | `13168` |

### `customfield_12078` — Incident Owner
| Value | ID |
|---|---|
| Data People | `62530` |
| Data For Rent | `14714` |
| Data For Sale | `14715` |
| Data Fintech | `16955` |
| Data Growth | `55173` |
| Data Agents | `60113` |
| Data S&S | `15755` |
| Data Governance | `14712` |
| Data Primitives | `69331` |
| Data Serving | `69332` |
| Data Life Cycle | `58334` |
| MLOps | `55171` |
| AE All | `16503` |

### `customfield_12350` — SLA affected?
| Value | ID |
|---|---|
| Yes | `15757` |
| No | `15758` |

### Other fields
| Field | Key |
|---|---|
| Failed Task | `customfield_30056` (plain string) |
| Description (Problem/Cause/Solution) | `description` (markdown string) |

## Workflow

### Step 1 — Gather context

Collect from the user or infer from conversation:
- Issue keys or URLs (e.g. `DEI-20521`)
- DAG name and failed task
- Error log snippet
- Incident Owner team
- Whether SLA was affected

**Always ask the user explicitly:**
> "Was a solution applied to this incident, or is it still under investigation?"

Use the answer to drive Step 2:
- If a solution was applied → ask what was done and set Root Cause Resolution = **Fixed**, Incident Status = **Hot Fixed**
- If still open → set Root Cause Resolution = **Discovery**, Incident Status = **Under investigation**, and document the hypothesis in the Solution field

If anything else is unclear, ask before proceeding.

### Step 2 — Choose field values

Use this decision guide:

**Root Cause Resolution:**
- Root cause confirmed + fix deployed → `Fixed`
- Root cause confirmed + no permanent fix → `Not Fixed`
- Still investigating → `Discovery`

**Incident Status:**
- Fix deployed during on-call → `Hot Fixed`
- Task marked as success / DAG turned off → `Bypass`
- Still open → `Under investigation`

**Incident Category:** match the primary failure reason to the table above.

### Step 3 — Fetch existing Databricks Details

Before writing the description, call `getJiraIssue` (or equivalent read tool) to retrieve the auto-generated fields from the existing card:

| Field | Purpose |
|---|---|
| `customfield_30055` | Cluster Log Location (S3 path) |
| `customfield_30040` | Run Link (Databricks job URL) |
| `customfield_30039` | Databricks Error (raw error text) |

These values must be appended verbatim at the end of every description so the auto-generated section is not lost.

### Step 4 — Fill all cards in parallel

Call `editJiraIssue` for each card simultaneously with all fields at once:

```json
{
  "cloudId": "8a4667b7-87a1-4c6c-805c-fc0d6e60a7a0",
  "issueIdOrKey": "DEI-XXXXX",
  "contentFormat": "markdown",
  "fields": {
    "description": "<see description template below>",
    "customfield_11194": {"id": "<root_cause_id>"},
    "customfield_21698": {"id": "<incident_status_id>"},
    "customfield_11195": {"id": "<category_id>"},
    "customfield_12078": {"id": "<owner_id>"},
    "customfield_12350": {"id": "<sla_id>"},
    "customfield_30056": "<failed_task_name>"
  }
}
```

### Description template

> All card content **must be written in English**. Never use Portuguese in the description fields.

```markdown
**Problem:**
The task `<task_name>` in DAG `<dag_name>` failed with <error_type>. <Brief description of what happened, with log snippet if available.>

**Cause:**
<Root cause explanation. Be specific: what failed, why, evidence found.>

**Solution:**
<What was done. If hotfix: link the PR. If bypass: explain why. If still open: state "Under investigation".>

---

**Databricks Details (auto)**

Cluster Log Location: <value of customfield_30055>

Databricks Error:
<value of customfield_30039 — paste the plain text of the error>

Run Link: <value of customfield_30040>
```

> The `---` separator and everything below it must always be included, using the values fetched in Step 3. Never omit or modify the Databricks Details block.

## Prerequisites

This skill requires the **Atlassian MCP** (`plugin-atlassian-atlassian`) to be configured
in your Cursor workspace. If tool calls to `plugin-atlassian-atlassian` fail or the server
is not listed, instruct the user to install it:

1. Open Cursor Settings → MCP
2. Search for and add the **Atlassian** MCP server
3. Authenticate with your Atlassian account when prompted

The agent cannot install MCP servers on behalf of the user.

## Notes

- Always fill **all fields in a single `editJiraIssue` call per card** to minimize API calls.
- Fill multiple cards **in parallel** (single message, multiple tool calls).
- If the user provides Databricks run links per card, use each card's specific run link in the description — do not reuse the same link across all cards.
- `SLA affected?` should be confirmed with the user if uncertain — do not assume.
