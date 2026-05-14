# Conversation Explorer

Ingests daily session categorization data produced by the **Wall-E session categoriser** model into the datalake.

## Overview

| Property | Value |
|----------|-------|
| **Raw table** | `datalake_conversation_explorer_raw.categorisation` |
| **Clean table** | `datalake_conversation_explorer_clean.categorisation` |
| **Source** | `s3://conversation-explorer-prod/session-metadata/<YYYY-MM-DD>.parquet` |
| **Trigger** | Dataset: `quintoml.chatbot.wall_e_session_categoriser.inference:first-run-of-day` |
| **Extraction** | Full load (picks the most recently uploaded file) |
| **Partitions** | `year`, `month`, `day` (derived from `session_date`) |

## What it does

1. Waits for the Wall-E session categoriser model to emit its daily dataset event.
2. Lists all parquet files in the S3 bucket and selects the **most recently uploaded** one (by S3 last-modified timestamp).
3. Reads the parquet, adds `year`/`month`/`day` partition columns from `session_date`, and writes to **raw**.
4. Clean query reads from raw and writes to **clean** with schema enforcement.

## Columns

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

## Backfill

Trigger the DAG manually in Airflow with config:

```json
{"date": "2026-04-05"}
```

This loads the specific file `2026-04-05.parquet` instead of auto-detecting the most recent one.
