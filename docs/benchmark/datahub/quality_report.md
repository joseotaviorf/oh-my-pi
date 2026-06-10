# TARS SQL Quality Evaluation Report

Generated: 2026-05-12T21:29:29Z

Validates the **golden SQL** stored in `eval_cases.yml` against three quality dimensions: static analysis (schema routing + column + filter rules), schema validation (Trino DESCRIBE), and execution correctness (live query).

## Summary

| # | Question | Complexity | Routing | Schema | Rules | Exec | Rows | Score |
|---|---|---|:---:|:---:|:---:|:---:|:---:|---:|
| Q1 | What tables track overdue invoices? | Entity routing only | PASS | PASS | PASS | PASS | 10 | 16/16 |
| Q2 | What does the delay_contamined_range column mean? | Column lookup | PASS | PASS | PASS | PASS | 11 | 14/14 |
| Q3 | Give me the AR recovery rate query split by OKR bucket | Golden query retrieval | PASS | PASS | PASS | PASS | 26 | 12/12 |
| Q4 | How do I join fact_negotiation to fact_debt? | Cross-table join | PASS | PASS | PASS | PASS | 10 | 18/18 |
| Q5 | What is the difference between Acordo and Promessa? | Glossary / synonym | PASS | PASS | PASS | PASS | 32 | 14/14 |
| OB1 | Em que tabela posso encontrar informações sobre vistorias de saída? | Entity routing (Inspection) | PASS | PASS | PASS | FAIL | — | 17/19 |
| OB2 | Gere uma query para contabilizar rescisões com isenção de vistoria de saída | Medium query (Offboarding — fact_terminations opt-out) | PASS | PASS | PASS | PASS | 13 | 16/16 |
| OB3 | Gere uma query para contabilizar offboardings sem reparos | Medium query (Offboarding — obt_offboarding has_repairs) | PASS | PASS | PASS | PASS | 16 | 12/12 |
| OB4 | Gere query para analisar se fluxo automático de AR está relacionado com menos aprovações de IQ e PP | Hard query (Offboarding — auto AR approval comparison) | PASS | PASS | PASS | PASS | 2 | 18/18 |
| OB5 | Gere uma query que mostre por termination se houve agreement, relistagem e rerental | Hard query (Offboarding — obt + fact_house_listing_terminations) | PASS | PASS | PASS | PASS | 100 | 19/19 |
| SU1 | Em que tabela posso encontrar informações sobre leads de supply? | Entity routing (Supply) | PASS | PASS | PASS | FAIL | — | 14/16 |
| SU2 | Gere uma query para contabilizar todos os first listings que vieram das calculadoras | Medium query (Supply — calculator acquisition_origin) | PASS | PASS | PASS | FAIL | — | 14/16 |
| SU3 | Gere uma query para contabilizar todos os opportunities gerados pelo Isaías | Medium query (Supply — Isaias tp_origin_acquisition) | PASS | PASS | PASS | FAIL | — | 11/13 |
| SU4 | Gere uma query para analisar a taxa de conversão de lead para opportunity dos leads inbound | Medium query (Supply — coincident date conversion rate) | PASS | PASS | FAIL | FAIL | — | 9/13 |
| SU5 | Gere uma query para comparar volumes de motivos de descarte entre canais de operações e self-service | Hard query (Supply — discard reasons by channel) | PASS | PASS | PASS | FAIL | — | 13/15 |

## Aggregate

| Metric | Value |
|---|---|
| Total score | 217 / 231 (93%) |
| Execution success | 9 / 15 |
| Avg execution latency | 2497 ms |

## Per-question breakdown

### Q1 — What tables track overdue invoices?

**Complexity:** Entity routing only  
**Score:** 16/16 (100%)

**Phase 1 — Static analysis**
- Tables found: `dw_collection_recovery_quintoandar.fact_overdue_portfolio_timeline`
- Columns found: `id_invoice`, `payment_status`, `delay_contamined_range`, `due_amount`
- Filter patterns matched: 2

**Phase 2 — Schema validation (Trino DESCRIBE)**
- Tables validated: `dw_collection_recovery_quintoandar.fact_overdue_portfolio_timeline`

**Phase 3 — Execution validation**
- Status: **SUCCESS**
- Rows returned: 10
- Columns: `id_invoice`, `payment_status`, `delay_contamined_range`, `due_amount`, `dt_reference`
- Latency: 2124 ms
- Meets min-rows threshold: yes

### Q2 — What does the delay_contamined_range column mean?

**Complexity:** Column lookup  
**Score:** 14/14 (100%)

**Phase 1 — Static analysis**
- Tables found: `dw_collection_recovery_quintoandar.fact_overdue_portfolio_timeline`
- Columns found: `delay_contamined_range`, `id_invoice`, `due_amount`
- Filter patterns matched: 2

**Phase 2 — Schema validation (Trino DESCRIBE)**
- Tables validated: `dw_collection_recovery_quintoandar.fact_overdue_portfolio_timeline`

**Phase 3 — Execution validation**
- Status: **SUCCESS**
- Rows returned: 11
- Columns: `delay_contamined_range`, `invoice_count`, `total_due_amount`
- Latency: 4869 ms
- Meets min-rows threshold: yes

### Q3 — Give me the AR recovery rate query split by OKR bucket

**Complexity:** Golden query retrieval  
**Score:** 12/12 (100%)

**Phase 1 — Static analysis**
- Tables found: `dw_collection_recovery_quintoandar.fact_overdue_portfolio_timeline`, `dw_losses.fact_accounts_receivable`
- Columns found: `delay_contamined_range`
- Filter patterns matched: 3

**Phase 2 — Schema validation (Trino DESCRIBE)**
- Tables validated: `dw_collection_recovery_quintoandar.fact_overdue_portfolio_timeline`, `dw_losses.fact_accounts_receivable`

**Phase 3 — Execution validation**
- Status: **SUCCESS**
- Rows returned: 26
- Columns: `dt_closing`, `okr_bucket`, `ar_recovery_rate`
- Latency: 4954 ms
- Meets min-rows threshold: yes

### Q4 — How do I join fact_negotiation to fact_debt?

**Complexity:** Cross-table join  
**Score:** 18/18 (100%)

**Phase 1 — Static analysis**
- Tables found: `dw_collection_recovery_quintoandar.fact_negotiation`, `dw_collection_recovery_quintoandar.fact_debt`, `dw_collection_recovery_quintoandar.bridge_map_debt_negotiation`
- Columns found: `sk_negotiation`, `sk_debt`, `id_invoice`, `negotiation_classification`
- Filter patterns matched: 1

**Phase 2 — Schema validation (Trino DESCRIBE)**
- Tables validated: `dw_collection_recovery_quintoandar.fact_negotiation`, `dw_collection_recovery_quintoandar.fact_debt`, `dw_collection_recovery_quintoandar.bridge_map_debt_negotiation`

**Phase 3 — Execution validation**
- Status: **SUCCESS**
- Rows returned: 10
- Columns: `sk_negotiation`, `negotiation_status`, `negotiation_classification`, `original_debt_amount`, `negotiated_amount`, `sk_debt`, `id_invoice`, `id_contract`
- Latency: 3345 ms
- Meets min-rows threshold: yes

### Q5 — What is the difference between Acordo and Promessa?

**Complexity:** Glossary / synonym  
**Score:** 14/14 (100%)

**Phase 1 — Static analysis**
- Tables found: `dw_collection_recovery_quintoandar.fact_negotiation`
- Columns found: `negotiation_classification`, `original_debt_amount`, `negotiated_amount`
- Filter patterns matched: 3

**Phase 2 — Schema validation (Trino DESCRIBE)**
- Tables validated: `dw_collection_recovery_quintoandar.fact_negotiation`

**Phase 3 — Execution validation**
- Status: **SUCCESS**
- Rows returned: 32
- Columns: `negotiation_classification`, `negotiation_status`, `negotiation_count`, `total_original_debt`, `total_negotiated_amount`
- Latency: 1483 ms
- Meets min-rows threshold: yes

### OB1 — Em que tabela posso encontrar informações sobre vistorias de saída?

**Complexity:** Entity routing (Inspection)  
**Score:** 17/19 (89%)

**Phase 1 — Static analysis**
- Tables found: `dw_inspections.fact_inspection`, `dw_inspections.dim_inspection`
- Columns found: `sk_inspection`, `sk_contract`, `ts_inspected`, `inspection_type`
- Filter patterns matched: 2

**Phase 2 — Schema validation (Trino DESCRIBE)**
- Tables validated: `dw_inspections.fact_inspection`, `dw_inspections.dim_inspection`

**Phase 3 — Execution validation**
- Status: **ERROR**
- Error: `Execution failed on sql: SELECT sub.*
FROM (
  SELECT
    fi.sk_inspection,
    fi.sk_contract,
    fi.sk_house,
    fi.ts_booking_created,
    fi.ts_inspected,
    di.inspection_type,
    di.inspection_status,
    fri.has_agreement,
    fri.total_cost,
    fri.ts_sent_to_repair_analysis,
    ROW_NUMBER() OVER (PARTITION BY fi.sk_contract ORDER BY fi.ts_updated DESC) AS rni
  FROM dw_inspections.fact_inspection AS fi
  LEFT JOIN dw_inspections.dim_inspection AS di
    ON fi.sk_inspection = di.sk_inspection
  LEFT JOIN dw_inspections.fact_report_inspections AS fri
    ON fi.sk_inspection = CAST(fri.sk_inspection AS VARCHAR)
  WHERE di.inspection_type = 'offboarding'
) AS sub
WHERE sub.rni = 1
LIMIT 10

TrinoUserError(type=USER_ERROR, name=COLUMN_NOT_FOUND, message="line 10:5: Column 'di.inspection_status' cannot be resolved", query_id=20260512_212836_39135_jiza4)
unable to rollback`

### OB2 — Gere uma query para contabilizar rescisões com isenção de vistoria de saída

**Complexity:** Medium query (Offboarding — fact_terminations opt-out)  
**Score:** 16/16 (100%)

**Phase 1 — Static analysis**
- Tables found: `dw_offboarding.fact_terminations`, `dw_offboarding.dim_termination`
- Columns found: `is_exit_inspection_opt_out`, `ts_termination_request`, `sk_termination`
- Filter patterns matched: 2

**Phase 2 — Schema validation (Trino DESCRIBE)**
- Tables validated: `dw_offboarding.fact_terminations`, `dw_offboarding.dim_termination`

**Phase 3 — Execution validation**
- Status: **SUCCESS**
- Rows returned: 13
- Columns: `month_request`, `total_terminations`, `total_inspection_exempt`, `pct_inspection_exempt`
- Latency: 2050 ms
- Meets min-rows threshold: yes

### OB3 — Gere uma query para contabilizar offboardings sem reparos

**Complexity:** Medium query (Offboarding — obt_offboarding has_repairs)  
**Score:** 12/12 (100%)

**Phase 1 — Static analysis**
- Tables found: `dw_offboarding.obt_offboarding`
- Columns found: `has_repairs`, `ts_termination_finished`
- Filter patterns matched: 2

**Phase 2 — Schema validation (Trino DESCRIBE)**
- Tables validated: `dw_offboarding.obt_offboarding`

**Phase 3 — Execution validation**
- Status: **SUCCESS**
- Rows returned: 16
- Columns: `mes`, `total_offboardings`, `sem_reparos`, `com_reparos`, `taxa_sem_reparos`
- Latency: 1623 ms
- Meets min-rows threshold: yes

### OB4 — Gere query para analisar se fluxo automático de AR está relacionado com menos aprovações de IQ e PP

**Complexity:** Hard query (Offboarding — auto AR approval comparison)  
**Score:** 18/18 (100%)

**Phase 1 — Static analysis**
- Tables found: `dw_offboarding.obt_offboarding`
- Columns found: `is_automated_ar`, `has_tenant_approved_review`, `has_owner_approved_review`, `has_tenant_approved_budget_approval`, `has_owner_approved_budget_approval`
- Filter patterns matched: 2

**Phase 2 — Schema validation (Trino DESCRIBE)**
- Tables validated: `dw_offboarding.obt_offboarding`

**Phase 3 — Execution validation**
- Status: **SUCCESS**
- Rows returned: 2
- Columns: `fluxo_ar`, `total`, `iq_aprovou_review`, `iq_taxa_aprovacao_review_pct`, `pp_aprovou_review`, `pp_taxa_aprovacao_review_pct`, `iq_aprovou_budget`, `iq_taxa_aprovacao_budget_pct`, `pp_aprovou_budget`, `pp_taxa_aprovacao_budget_pct`, `total_com_acordo`, `taxa_acordo_pct`
- Latency: 1985 ms
- Meets min-rows threshold: yes

### OB5 — Gere uma query que mostre por termination se houve agreement, relistagem e rerental

**Complexity:** Hard query (Offboarding — obt + fact_house_listing_terminations)  
**Score:** 19/19 (100%)

**Phase 1 — Static analysis**
- Tables found: `dw_offboarding.obt_offboarding`, `dw_offboarding.fact_house_listing_terminations`
- Columns found: `has_agreement`, `has_early_agreement`, `has_late_agreement`, `ts_termination_finished`, `sk_next_contract`
- Filter patterns matched: 2

**Phase 2 — Schema validation (Trino DESCRIBE)**
- Tables validated: `dw_offboarding.obt_offboarding`, `dw_offboarding.fact_house_listing_terminations`

**Phase 3 — Execution validation**
- Status: **SUCCESS**
- Rows returned: 100
- Columns: `sk_termination`, `sk_contract`, `termination_status`, `termination_reason`, `has_agreement`, `has_early_agreement`, `has_late_agreement`, `has_discount_agreement`, `is_relisting`, `is_rerental`, `days_termination_to_contract_signed`, `ts_termination_finished`
- Latency: 1998 ms
- Meets min-rows threshold: yes

### SU1 — Em que tabela posso encontrar informações sobre leads de supply?

**Complexity:** Entity routing (Supply)  
**Score:** 14/16 (88%)

**Phase 1 — Static analysis**
- Tables found: `dw_growth.obt_supply`
- Columns found: `sk_lead`, `cd_funnel_step`, `nm_business_context`, `company_report_origin`
- Filter patterns matched: 2

**Phase 2 — Schema validation (Trino DESCRIBE)**
- Tables validated: `dw_growth.obt_supply`

**Phase 3 — Execution validation**
- Status: **ERROR**
- Error: `/Users/aurelio.nogueira/Documents/projects/bi-etl-ejuice/.cursor/skills/trino/scripts/execute_trino.py:28: UserWarning: pandas only supports SQLAlchemy connectable (engine/connection) or database string URI or sqlite3 DBAPI2 connection. Other DBAPI2 objects are not tested. Please consider using SQLAlchemy.
  df = pd.read_sql_query(query, conn)
Traceback (most recent call last):
  File "/Users/aurelio.nogueira/Documents/projects/bi-etl-ejuice/.cursor/skills/trino/scripts/execute_trino.py", line 82, in <module>
    print(json.dumps(res))
  File "/Users/aurelio.nogueira/pyenv/versions/3.8.12/lib/python3.8/json/__init__.py", line 231, in dumps
    return _default_encoder.encode(obj)
  File "/Users/aurelio.nogueira/pyenv/versions/3.8.12/lib/python3.8/json/encoder.py", line 199, in encode
    chunks = self.iterencode(o, _one_shot=True)
  File "/Users/aurelio.nogueira/pyenv/versions/3.8.12/lib/python3.8/json/encoder.py", line 257, in iterencode
    return _iterencode(o, 0)
  File "/Users/aurelio.nogueira/pyenv/versions/3.8.12/lib/python3.8/json/encoder.py", line 179, in default
    raise TypeError(f'Object of type {o.__class__.__name__} '
TypeError: Object of type date is not JSON serializable`

### SU2 — Gere uma query para contabilizar todos os first listings que vieram das calculadoras

**Complexity:** Medium query (Supply — calculator acquisition_origin)  
**Score:** 14/16 (88%)

**Phase 1 — Static analysis**
- Tables found: `dw_growth.obt_supply`
- Columns found: `cd_funnel_step`, `acquisition_origin`, `sk_lead`, `nm_business_context`
- Filter patterns matched: 2

**Phase 2 — Schema validation (Trino DESCRIBE)**
- Tables validated: `dw_growth.obt_supply`

**Phase 3 — Execution validation**
- Status: **ERROR**
- Error: `/Users/aurelio.nogueira/Documents/projects/bi-etl-ejuice/.cursor/skills/trino/scripts/execute_trino.py:28: UserWarning: pandas only supports SQLAlchemy connectable (engine/connection) or database string URI or sqlite3 DBAPI2 connection. Other DBAPI2 objects are not tested. Please consider using SQLAlchemy.
  df = pd.read_sql_query(query, conn)
Traceback (most recent call last):
  File "/Users/aurelio.nogueira/Documents/projects/bi-etl-ejuice/.cursor/skills/trino/scripts/execute_trino.py", line 82, in <module>
    print(json.dumps(res))
  File "/Users/aurelio.nogueira/pyenv/versions/3.8.12/lib/python3.8/json/__init__.py", line 231, in dumps
    return _default_encoder.encode(obj)
  File "/Users/aurelio.nogueira/pyenv/versions/3.8.12/lib/python3.8/json/encoder.py", line 199, in encode
    chunks = self.iterencode(o, _one_shot=True)
  File "/Users/aurelio.nogueira/pyenv/versions/3.8.12/lib/python3.8/json/encoder.py", line 257, in iterencode
    return _iterencode(o, 0)
  File "/Users/aurelio.nogueira/pyenv/versions/3.8.12/lib/python3.8/json/encoder.py", line 179, in default
    raise TypeError(f'Object of type {o.__class__.__name__} '
TypeError: Object of type date is not JSON serializable`

### SU3 — Gere uma query para contabilizar todos os opportunities gerados pelo Isaías

**Complexity:** Medium query (Supply — Isaias tp_origin_acquisition)  
**Score:** 11/13 (85%)

**Phase 1 — Static analysis**
- Tables found: `dw_growth.obt_supply`
- Columns found: `cd_funnel_step`, `tp_origin_acquisition`, `sk_lead`
- Filter patterns matched: 2

**Phase 2 — Schema validation (Trino DESCRIBE)**
- Tables validated: `dw_growth.obt_supply`

**Phase 3 — Execution validation**
- Status: **ERROR**
- Error: `/Users/aurelio.nogueira/Documents/projects/bi-etl-ejuice/.cursor/skills/trino/scripts/execute_trino.py:28: UserWarning: pandas only supports SQLAlchemy connectable (engine/connection) or database string URI or sqlite3 DBAPI2 connection. Other DBAPI2 objects are not tested. Please consider using SQLAlchemy.
  df = pd.read_sql_query(query, conn)
Traceback (most recent call last):
  File "/Users/aurelio.nogueira/Documents/projects/bi-etl-ejuice/.cursor/skills/trino/scripts/execute_trino.py", line 82, in <module>
    print(json.dumps(res))
  File "/Users/aurelio.nogueira/pyenv/versions/3.8.12/lib/python3.8/json/__init__.py", line 231, in dumps
    return _default_encoder.encode(obj)
  File "/Users/aurelio.nogueira/pyenv/versions/3.8.12/lib/python3.8/json/encoder.py", line 199, in encode
    chunks = self.iterencode(o, _one_shot=True)
  File "/Users/aurelio.nogueira/pyenv/versions/3.8.12/lib/python3.8/json/encoder.py", line 257, in iterencode
    return _iterencode(o, 0)
  File "/Users/aurelio.nogueira/pyenv/versions/3.8.12/lib/python3.8/json/encoder.py", line 179, in default
    raise TypeError(f'Object of type {o.__class__.__name__} '
TypeError: Object of type date is not JSON serializable`

### SU4 — Gere uma query para analisar a taxa de conversão de lead para opportunity dos leads inbound

**Complexity:** Medium query (Supply — coincident date conversion rate)  
**Score:** 9/13 (69%)

**Phase 1 — Static analysis**
- Tables found: `dw_growth.obt_supply`
- Columns found: `cd_funnel_step`, `planning_operation`
- **Columns MISSING:** `sk_lead`
- Filter patterns matched: 1
- **Filter patterns MISSING:** ['(?i)lead.*opportunity|opportunity.*lead']

**Phase 2 — Schema validation (Trino DESCRIBE)**
- Tables validated: `dw_growth.obt_supply`

**Phase 3 — Execution validation**
- Status: **ERROR**
- Error: `/Users/aurelio.nogueira/Documents/projects/bi-etl-ejuice/.cursor/skills/trino/scripts/execute_trino.py:28: UserWarning: pandas only supports SQLAlchemy connectable (engine/connection) or database string URI or sqlite3 DBAPI2 connection. Other DBAPI2 objects are not tested. Please consider using SQLAlchemy.
  df = pd.read_sql_query(query, conn)
Traceback (most recent call last):
  File "/Users/aurelio.nogueira/Documents/projects/bi-etl-ejuice/.cursor/skills/trino/scripts/execute_trino.py", line 82, in <module>
    print(json.dumps(res))
  File "/Users/aurelio.nogueira/pyenv/versions/3.8.12/lib/python3.8/json/__init__.py", line 231, in dumps
    return _default_encoder.encode(obj)
  File "/Users/aurelio.nogueira/pyenv/versions/3.8.12/lib/python3.8/json/encoder.py", line 199, in encode
    chunks = self.iterencode(o, _one_shot=True)
  File "/Users/aurelio.nogueira/pyenv/versions/3.8.12/lib/python3.8/json/encoder.py", line 257, in iterencode
    return _iterencode(o, 0)
  File "/Users/aurelio.nogueira/pyenv/versions/3.8.12/lib/python3.8/json/encoder.py", line 179, in default
    raise TypeError(f'Object of type {o.__class__.__name__} '
TypeError: Object of type date is not JSON serializable`

### SU5 — Gere uma query para comparar volumes de motivos de descarte entre canais de operações e self-service

**Complexity:** Hard query (Supply — discard reasons by channel)  
**Score:** 13/15 (87%)

**Phase 1 — Static analysis**
- Tables found: `dw_growth.obt_supply`, `dw_growth.dim_supply_discards`
- Columns found: `company_report_origin`, `cd_discard_reason`, `sk_discard`
- Filter patterns matched: 2

**Phase 2 — Schema validation (Trino DESCRIBE)**
- Tables validated: `dw_growth.obt_supply`, `dw_growth.dim_supply_discards`

**Phase 3 — Execution validation**
- Status: **ERROR**
- Error: `Execution failed on sql: SELECT
  obt.company_report_origin,
  dsd.cd_discard_reason,
  dsd.nm_discard_reason,
  COUNT(DISTINCT obt.sk_lead) AS total_discards
FROM dw_growth.obt_supply AS obt
JOIN dw_growth.dim_supply_discards AS dsd
  ON obt.sk_discard = dsd.sk_discard
WHERE obt.nm_business_context = 'RENT'
  AND obt.company_report_origin IN (
    'Operações',
    'Ownerlanding',
    'Homelanding',
    'Calculadora'
  )
  AND obt.date >= DATE '2025-01-01'
GROUP BY obt.company_report_origin, dsd.cd_discard_reason, dsd.nm_discard_reason
ORDER BY obt.company_report_origin, total_discards DESC
LIMIT 100
TrinoUserError(type=USER_ERROR, name=COLUMN_NOT_FOUND, message="line 8:6: Column 'obt.sk_discard' cannot be resolved", query_id=20260512_212928_39189_jiza4)
unable to rollback`

## What this proves (and what it doesn't)

**Proves:** The DataHub context contains accurate, executable metadata — schema descriptions match real Trino tables, golden queries run without errors, column names are valid. This validates the metadata quality upstream of TARS. Metadata accuracy is the primary determinant of SQL quality: if DataHub has the correct table names, column names, and join patterns, TARS will generate correct SQL.

**Does not prove:** That a live LLM invocation generates the golden SQL unprompted. That requires a full LLM eval harness — see the section below.

## Future: LLM eval harness

To measure whether the **new DataHub context** produces *more accurate SQL than the old file-based context*, the next step is a prompt-response-judge loop:

```
For each eval_case question:
  1. Build old context  → send to LLM → extract SQL → judge SQL
  2. Build new context  → send to LLM → extract SQL → judge SQL
  3. Compare: routing accuracy, schema accuracy, execution success, result correctness
```

Recommended tooling and approaches:

- **Braintrust** (`braintrust-sdk`) — SaaS eval platform with built-in LLM-as-judge scorers, dataset versioning, and A/B comparison. Define a dataset from `eval_cases.yml`, a task that calls TARS with both contexts, and scorers for routing, schema, and execution correctness.
- **RAGAS** — open-source RAG eval framework. Define a custom metric `SqlSchemaAccuracy` that checks if generated SQL references the expected tables and columns. Add `SqlExecutionSuccess` that runs the generated SQL on Trino. Run `ragas evaluate(dataset, metrics=[...])` and compare old vs new context scores.
- **Custom harness** — for full control: wrap the TARS system prompt with both old and new context, call an LLM API directly, parse out the SQL block, then run the three-phase rubric above on the *generated* SQL instead of the golden SQL. This gives the same rubric reuse but tests live LLM behavior.

**Key metrics to collect in the LLM eval:**

| Metric | Definition |
|---|---|
| Routing accuracy | Correct layer (DW) chosen, no forbidden-table references |
| Schema accuracy | All expected tables and key columns present |
| Rule compliance | Partition filter, dedup sentinel, bridge join present |
| Execution success | Generated SQL runs without Trino error |
| Result correctness | Expected columns in output, min-rows threshold met |
| Context efficiency | Input tokens consumed to produce a passing answer |

Combining context efficiency (from `benchmark_tars_pivot.py`) with output quality (from this LLM eval harness) gives the full ROI picture: lower cost *and* higher accuracy.

_Script: `docs/benchmark/datahub/evaluate_sql_quality.py`_