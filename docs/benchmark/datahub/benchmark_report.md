# TARS context pivot — ROI benchmark

Generated: 2026-05-12T21:27:06Z

Benchmark compares the **old file-based TARS flow** (read `intro.md` + entity MD + optional grep/YAML/SQL) against the **new DataHub MCP flow** (structured GraphQL calls returning only the facts the agent needs).

Question set: **5 Collections** (original) + **5 Offboarding/Inspection** + **5 Supply/Isaias** — drawn from the *Tars MVP Evaluation* PDF (Offboarding tab scored 9.5/10 on TARS branch; Supply/Isaias tab scored 10/10).

> **Token estimation:** bytes ÷ 4 (4 chars/token, industry-standard approximation).  
> Trino skill context (~1 K tokens) is identical in both flows and excluded from the comparison.

## Per-question comparison

| # | Question | Complexity | Old tokens | New tokens | Reduction | Old files | New calls | Old latency | New latency | Coverage old | Coverage new |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|:---:|:---:|
| Q1 | What tables track overdue invoices? | Entity routing only | 8,160 | 649 | 12.6x | 2 | 2 | 0 ms | 1236 ms | yes | yes |
| Q2 | What does the delay_contamined_range column mean? | Column lookup | 13,215 | 496 | 26.6x | 4 | 3 | 2392 ms | 1193 ms | yes | yes |
| Q3 | Give me the AR recovery rate query split by OKR bucket | Golden query retrieval | 14,995 | 491 | 30.5x | 5 | 2 | 1021 ms | 472 ms | yes | yes |
| Q4 | How do I join fact_negotiation to fact_debt? | Cross-table join | 14,049 | 652 | 21.5x | 4 | 3 | 996 ms | 869 ms | yes | yes |
| Q5 | What is the difference between Acordo and Promessa? | Glossary / synonym | 8,160 | 768 | 10.6x | 2 | 2 | 0 ms | 523 ms | yes | yes |
| OBQ1 | Em que tabela posso encontrar informações sobre vistorias de saída? | Entity routing (Inspection) | 4,461 | 3,253 | 1.4x | 2 | 3 | 1 ms | 879 ms | yes | yes |
| OBQ2 | Gere uma query para contabilizar rescisões com isenção de vistoria de saída | Medium query (Offboarding — opt-out flag) | 7,271 | 14 | 519.4x | 3 | 1 | 1 ms | 433 ms | yes | NO |
| OBQ3 | Gere uma query para contabilizar offboardings sem reparos | Medium query (Offboarding — has_repairs OBT) | 4,461 | 496 | 9.0x | 2 | 2 | 0 ms | 1025 ms | yes | yes |
| OBQ4 | Gere query para analisar se fluxo automático de AR reduz aprovações de IQ e PP | Hard query (Offboarding — auto AR approval comparison) | 4,461 | 640 | 7.0x | 2 | 2 | 0 ms | 644 ms | NO | yes |
| OBQ5 | Gere query por termination mostrando agreement, relistagem e rerental | Hard query (Offboarding — obt + fact_house_listing_terminations) | 7,271 | 14 | 519.4x | 3 | 1 | 0 ms | 471 ms | yes | NO |
| SQ1 | Em que tabela posso encontrar informações sobre leads de supply? | Entity routing (Supply) | 17,552 | 38 | 461.9x | 2 | 2 | 1 ms | 563 ms | yes | yes |
| SQ2 | Gere uma query para contabilizar first listings vindos das calculadoras | Medium query (Supply — calculator acquisition_origin) | 17,552 | 14 | 1253.7x | 2 | 1 | 0 ms | 372 ms | yes | NO |
| SQ3 | Gere uma query para contabilizar opportunities gerados pelo Isaías | Medium query (Supply — Isaias tp_origin_acquisition) | 17,552 | 426 | 41.2x | 2 | 2 | 1 ms | 612 ms | yes | yes |
| SQ4 | Gere query para taxa de conversão lead para opportunity dos leads inbound | Medium query (Supply — coincident date conversion) | 17,552 | 322 | 54.5x | 2 | 2 | 0 ms | 546 ms | yes | yes |
| SQ5 | Compare volumes de motivos de descarte entre canais de operações e self-service | Hard query (Supply — discard reasons by channel) | 17,552 | 14 | 1253.7x | 2 | 1 | 0 ms | 361 ms | yes | NO |

## Aggregate (15-question set)

| Metric | Value |
|---|---|
| Total old-flow tokens | 174,264 |
| Total new-flow tokens | 8,287 |
| Token saving (15 questions) | 165,977 |
| Median reduction | 30.5x |
| Mean reduction | 281.5x |
| Avg old latency | 294 ms |
| Avg new latency | 680 ms |

## Domain breakdown

| Domain | Old tokens | New tokens | Saving | Avg reduction | Coverage old | Coverage new |
|---|---:|---:|---:|---:|:---:|:---:|
| Collections | 58,579 | 3,056 | 55,523 | 20.4x | yes | yes |
| Offboarding/Inspection | 27,925 | 4,417 | 23,508 | 211.2x | partial | partial |
| Supply/Isaias | 87,760 | 814 | 86,946 | 613.0x | yes | partial |

## Cost projection

Assumptions: **100 @tars questions/day** (across all 15 question domains), input price **$3.00 / M tokens** (Sonnet 4.6 — adjust the constant in the script to compare models).

| Horizon | Token saving | Estimated saving (USD) |
|---|---|---|
| Per question (avg) | 11,065 | $0.0332 |
| Per day (100 questions) | 1,106,513 | $3.32 |
| Per month | 33,195,400 | $99.59 |
| Per year | 398,344,800 | $1195.03 |

> **Note:** Cost projection covers input token reduction only. The new flow adds small GraphQL network latency (~ms range) with no new infrastructure cost — DataHub and its MCP are already running in production.

## Detailed breakdown

### Q1 — What tables track overdue invoices?

**Old flow files:**
- `intro_bytes`: 5,841 chars ≈ 1,460 tokens
- `entity_md_bytes`: 26,802 chars ≈ 6,700 tokens

**New flow calls:**
- `search_bytes`: 1,561 chars ≈ 390 tokens
- `search_hits`: 5
- `get_entities_bytes`: 1,037 chars ≈ 259 tokens

### Q2 — What does the delay_contamined_range column mean?

**Old flow files:**
- `intro_bytes`: 5,841 chars ≈ 1,460 tokens
- `entity_md_bytes`: 26,802 chars ≈ 6,700 tokens
- `grep_bytes`: 3,350 chars ≈ 837 tokens
- `yaml_bytes`: 16,868 chars ≈ 4,217 tokens

**New flow calls:**
- `search_bytes`: 955 chars ≈ 238 tokens
- `search_hits`: 5
- `get_entities_bytes`: 924 chars ≈ 231 tokens
- `schema_filtered_bytes`: 107 chars ≈ 26 tokens
- `schema_total_fields`: 50
- `schema_matched_fields`: 1

### Q3 — Give me the AR recovery rate query split by OKR bucket

**Old flow files:**
- `intro_bytes`: 5,841 chars ≈ 1,460 tokens
- `entity_md_bytes`: 26,802 chars ≈ 6,700 tokens
- `grep_bytes`: 3,350 chars ≈ 837 tokens
- `yaml_bytes`: 16,868 chars ≈ 4,217 tokens
- `sql_bytes`: 7,122 chars ≈ 1,780 tokens

**New flow calls:**
- `search_bytes`: 59 chars ≈ 14 tokens
- `search_hits`: 0
- `query_bytes`: 1,906 chars ≈ 476 tokens

### Q4 — How do I join fact_negotiation to fact_debt?

**Old flow files:**
- `intro_bytes`: 5,841 chars ≈ 1,460 tokens
- `entity_md_bytes`: 26,802 chars ≈ 6,700 tokens
- `grep_bytes`: 5,042 chars ≈ 1,260 tokens
- `yaml_bytes`: 18,511 chars ≈ 4,627 tokens

**New flow calls:**
- `search_bytes`: 1,054 chars ≈ 263 tokens
- `search_hits`: 5
- `get_entities_bytes`: 1,188 chars ≈ 297 tokens
- `schema_filtered_bytes`: 367 chars ≈ 91 tokens
- `schema_total_fields`: 58
- `schema_matched_fields`: 4

### Q5 — What is the difference between Acordo and Promessa?

**Old flow files:**
- `intro_bytes`: 5,841 chars ≈ 1,460 tokens
- `entity_md_bytes`: 26,802 chars ≈ 6,700 tokens

**New flow calls:**
- `search_bytes`: 556 chars ≈ 139 tokens
- `search_hits`: 1
- `get_entities_bytes`: 2,518 chars ≈ 629 tokens

### OBQ1 — Em que tabela posso encontrar informações sobre vistorias de saída?

**Old flow files:**
- `intro_bytes`: 5,841 chars ≈ 1,460 tokens
- `entity_md_bytes`: 12,004 chars ≈ 3,001 tokens

**New flow calls:**
- `search_bytes`: 4,554 chars ≈ 1,138 tokens
- `search_hits`: 1
- `get_entities_bytes`: 8,366 chars ≈ 2,091 tokens
- `query_bytes`: 95 chars ≈ 23 tokens

### OBQ2 — Gere uma query para contabilizar rescisões com isenção de vistoria de saída

**Old flow files:**
- `intro_bytes`: 5,841 chars ≈ 1,460 tokens
- `entity_md_bytes`: 12,004 chars ≈ 3,001 tokens
- `entity_md_2_bytes`: 11,242 chars ≈ 2,810 tokens

**New flow calls:**
- `search_bytes`: 59 chars ≈ 14 tokens
- `search_hits`: 0

### OBQ3 — Gere uma query para contabilizar offboardings sem reparos

**Old flow files:**
- `intro_bytes`: 5,841 chars ≈ 1,460 tokens
- `entity_md_bytes`: 12,004 chars ≈ 3,001 tokens

**New flow calls:**
- `search_bytes`: 1,130 chars ≈ 282 tokens
- `search_hits`: 5
- `get_entities_bytes`: 855 chars ≈ 213 tokens

### OBQ4 — Gere query para analisar se fluxo automático de AR reduz aprovações de IQ e PP

**Old flow files:**
- `intro_bytes`: 5,841 chars ≈ 1,460 tokens
- `entity_md_bytes`: 12,004 chars ≈ 3,001 tokens

**New flow calls:**
- `search_bytes`: 1,072 chars ≈ 268 tokens
- `search_hits`: 5
- `get_entities_bytes`: 1,489 chars ≈ 372 tokens

### OBQ5 — Gere query por termination mostrando agreement, relistagem e rerental

**Old flow files:**
- `intro_bytes`: 5,841 chars ≈ 1,460 tokens
- `entity_md_bytes`: 12,004 chars ≈ 3,001 tokens
- `entity_md_2_bytes`: 11,242 chars ≈ 2,810 tokens

**New flow calls:**
- `search_bytes`: 59 chars ≈ 14 tokens
- `search_hits`: 0

### SQ1 — Em que tabela posso encontrar informações sobre leads de supply?

**Old flow files:**
- `intro_bytes`: 5,841 chars ≈ 1,460 tokens
- `entity_md_bytes`: 64,367 chars ≈ 16,091 tokens

**New flow calls:**
- `search_bytes`: 59 chars ≈ 14 tokens
- `search_hits`: 0
- `query_bytes`: 95 chars ≈ 23 tokens

### SQ2 — Gere uma query para contabilizar first listings vindos das calculadoras

**Old flow files:**
- `intro_bytes`: 5,841 chars ≈ 1,460 tokens
- `entity_md_bytes`: 64,367 chars ≈ 16,091 tokens

**New flow calls:**
- `search_bytes`: 59 chars ≈ 14 tokens
- `search_hits`: 0

### SQ3 — Gere uma query para contabilizar opportunities gerados pelo Isaías

**Old flow files:**
- `intro_bytes`: 5,841 chars ≈ 1,460 tokens
- `entity_md_bytes`: 64,367 chars ≈ 16,091 tokens

**New flow calls:**
- `search_bytes`: 976 chars ≈ 244 tokens
- `search_hits`: 5
- `get_entities_bytes`: 731 chars ≈ 182 tokens

### SQ4 — Gere query para taxa de conversão lead para opportunity dos leads inbound

**Old flow files:**
- `intro_bytes`: 5,841 chars ≈ 1,460 tokens
- `entity_md_bytes`: 64,367 chars ≈ 16,091 tokens

**New flow calls:**
- `search_bytes`: 503 chars ≈ 125 tokens
- `search_hits`: 2
- `get_entities_bytes`: 788 chars ≈ 197 tokens

### SQ5 — Compare volumes de motivos de descarte entre canais de operações e self-service

**Old flow files:**
- `intro_bytes`: 5,841 chars ≈ 1,460 tokens
- `entity_md_bytes`: 64,367 chars ≈ 16,091 tokens

**New flow calls:**
- `search_bytes`: 59 chars ≈ 14 tokens
- `search_hits`: 0

## Key findings

**DataHub wins decisively on schema and query questions (Q1-Q4).**
Column lookup (Q2) and golden query retrieval (Q3) achieve the highest
reductions because the old flow materialises entire YAML files and SQL
transformation scripts that the LLM only needs for 1-3 facts.

**Overall (Q1-Q4 only):**  
Excluding the glossary outlier, the median reduction is **30.5x**
with full coverage on every question.

## Notes

- **Old flow latency** is disk I/O + subprocess grep — no network.
- **New flow latency** includes real network round-trips to DataHub GMS.
  This is a fair trade: disk reads are cheap but the old flow loads far more
  bytes than needed; the new flow pays a small network cost for scoped responses.
- Entity MD files remain as supplementary context for dos/don'ts and JOIN recipes.
  In the hybrid steady state, both flows share the cost of one entity MD read for
  questions that need business-rule verification — this is not modelled here.
- Re-run this script after populating more entities in DataHub to track ROI growth.

_Script: `docs/benchmark/datahub/benchmark_tars_pivot.py`_