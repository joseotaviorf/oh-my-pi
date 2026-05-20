# Conversation Explorer

Ingests daily session categorization data produced by the **Wall-E session categoriser** model and annotations produced by human reviewers into the datalake.

## Overview

### Categorisation

| Property | Value |
|----------|-------|
| **Raw table** | `datalake_conversation_explorer_raw.categorisation` |
| **Clean table** | `datalake_conversation_explorer_clean.categorisation` |
| **Source** | `s3://conversation-explorer-prod/session-metadata/<YYYY-MM-DD>.parquet` |
| **Trigger** | Dataset: `quintoml.chatbot.wall_e_session_categoriser.inference:first-run-of-day` |
| **Extraction** | Full load (picks the most recently uploaded file) |
| **Partitions** | `year`, `month`, `day` (derived from `session_date`) |

### Annotations

| Property | Value |
|----------|-------|
| **Raw table** | `datalake_conversation_explorer_raw.annotations` |
| **Clean table** | `datalake_conversation_explorer_clean.annotations` |
| **Source** | `s3://conversation-explorer-prod/annotations-index/<YYYY-MM-DD>/*.json` → resolves `annotation_key` to `s3://conversation-explorer-prod/annotations/...` |
| **Trigger** | Runs after categorisation completes (same DAG, `raw_inner_dependencies`) |
| **Extraction** | Full load (picks the most recent date folder) |
| **Partitions** | `year`, `month`, `day` (derived from `created_at`) |

## What it does

### Categorisation flow

1. Waits for the Wall-E session categoriser model to emit its daily dataset event.
2. Lists all parquet files in the S3 bucket and selects the **most recently uploaded** one (by S3 last-modified timestamp).
3. Reads the parquet, adds `year`/`month`/`day` partition columns from `session_date`, and writes to **raw**.
4. Clean query reads from raw and writes to **clean** with schema enforcement.

### Annotations flow

1. After categorisation completes, lists date folders in `annotations-index/` and picks the **most recent** one.
2. Reads all JSON index files from that folder. Each contains `session_id` and `annotation_key`.
3. Resolves each `annotation_key` to the full annotation JSON in `s3://conversation-explorer-prod/<annotation_key>`.
4. Renames fields (`id` → `annotation_id`, `session_id` → `id_langfuse_session`, `text` → `annotation_text`), adds `year`/`month`/`day` from `created_at`, and writes to **raw**.
5. Clean query reads from raw and writes to **clean** with schema enforcement.

## Columns

### Categorisation

| Column | Description |
|--------|-------------|
| `id_langfuse_session` | Unique Langfuse session identifier |
| `session_date` | Date the session occurred (YYYY-MM-DD) |
| `channel` | Communication channel (in app, whatsapp) |
| `is_escalated` | Whether the session was escalated to a human agent |
| `first_queue` | First support queue routed to (if escalated) |
| `last_queue` | Last support queue routed to (if escalated) |
| `category` | High-level conversation category (pagamentos, visitas, rescisao, etc.) |
| `subcategory` | Detailed subcategory |
| `resolution_category` | How the session was resolved |
| `resolution_refinement_category` | Refinement of the resolution |
| `ai_resistance` | User resistance level toward the AI assistant |
| `frustration` | User frustration level during the session |
| `summary` | AI-generated summary of the conversation |

### Annotations

| Column | Description |
|--------|-------------|
| `annotation_id` | Unique identifier for the annotation |
| `id_langfuse_session` | Langfuse session the annotation refers to |
| `annotation_text` | Free-text content of the reviewer annotation |
| `author` | Email of the person who created the annotation |
| `created_at` | Timestamp (UTC) when the annotation was created |

## Backfill

Trigger the DAG manually in Airflow with config:

```json
{"date": "2026-04-05"}
```

- For **categorisation**: loads the specific file `2026-04-05.parquet` instead of auto-detecting the most recent one.
- For **annotations**: loads the specific folder `annotations-index/2026-04-05/` instead of auto-detecting the most recent date folder.
