-- Negotiated / list DBU price (USD per DBU) by compute type and validity window.
-- Source-controlled replacement for the stale gsheet `databricks_contract_details`
-- and the inline Superset CASE rates.
-- Current rates = AWS Premium pay-as-you-go list (effective 2026-07-01):
--   JOBS 0.15 / ALL_PURPOSE 0.55 / SQL 0.17.
-- Prior range = Oct-2024 $1M/24-month committed-use contract (closed 2026-07-01).
-- Oldest range = expired (2024-09-01) gsheet rates.
WITH dbu_prices (compute_type, usd_per_dbu, contract_note, dt_valid_from, dt_valid_to) AS (
    VALUES
        ('JOBS',        0.15,   'AWS Premium pay-as-you-go list (from 2026-07-01)', DATE('2026-07-01'), CAST(NULL AS DATE)),
        ('ALL_PURPOSE', 0.55,   'AWS Premium pay-as-you-go list (from 2026-07-01)', DATE('2026-07-01'), CAST(NULL AS DATE)),
        ('SQL',         0.17,   'AWS Premium pay-as-you-go list (from 2026-07-01)', DATE('2026-07-01'), CAST(NULL AS DATE)),
        ('JOBS',        0.114,  'Oct-2024 $1M/24mo committed-use contract', DATE('2024-09-30'), DATE('2026-07-01')),
        ('ALL_PURPOSE', 0.418,  'Oct-2024 $1M/24mo committed-use contract', DATE('2024-09-30'), DATE('2026-07-01')),
        ('SQL',         0.1672, 'Oct-2024 $1M/24mo committed-use contract', DATE('2024-09-30'), DATE('2026-07-01')),
        ('JOBS',        0.10,   'prior contract (gsheet, expired 2024-09-01)', DATE('2000-01-01'), DATE('2024-09-30')),
        ('ALL_PURPOSE', 0.32,   'prior contract (gsheet, expired 2024-09-01)', DATE('2000-01-01'), DATE('2024-09-30')),
        ('SQL',         0.17,   'prior contract (gsheet, expired 2024-09-01)', DATE('2000-01-01'), DATE('2024-09-30'))
)
SELECT
    compute_type,
    contract_note,
    CAST(usd_per_dbu AS DOUBLE) AS usd_per_dbu,
    CAST(dt_valid_from AS DATE) AS dt_valid_from,
    CAST(dt_valid_to AS DATE)   AS dt_valid_to,
    (dt_valid_to IS NULL)       AS is_current,
    CURRENT_TIMESTAMP()         AS ts_load
FROM dbu_prices
