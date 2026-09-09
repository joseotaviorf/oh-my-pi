-- One _meta/backfill_plans/<run_id>.json can yield many Spark rows when the
-- raw table still carries pre-VOCS-61 garbage (line-delimited JSON read of
-- pretty-printed files). MERGE on uuid_run then aborts with
-- DELTA_MULTIPLE_SOURCE_ROW_MATCHING_TARGET_ROW_IN_MERGE. Keep one row per
-- run_id until raw is rebuilt and clean MERGE is restored (VOCS-61 cleanup PR).
-- Prefer rows with a real payload (partitions/estimated_calls) over all-null
-- garbage; tie-break on ts_load then s3_key. Defensive run_id filter drops
-- filename-parse failures without changing the uuid_run grain.
WITH ranked AS (
    SELECT
        run_id AS uuid_run,
        caution,
        partitions,
        estimated_calls,
        estimated_llm_seconds,
        estimated_wall_clock_seconds,
        estimated_runs_needed,
        estimate_basis_counts.measured_from_last_success AS estimate_basis_measured_from_last_success,
        estimate_basis_counts.config_default AS estimate_basis_config_default,
        backfill_breaker.n_prompts AS breaker_n_prompts,
        backfill_breaker.n_partitions AS breaker_n_partitions,
        backfill_breaker.estimated_calls AS breaker_estimated_calls,
        backfill_breaker.tripped AS is_breaker_tripped,
        backfill_breaker.approved AS is_breaker_approved,
        backfill_breaker.refused AS is_breaker_refused,
        s3_key,
        ts_load,
        estimate_basis_counts,
        throughput_calibration,
        backfill_breaker,
        year,
        month,
        day,
        ROW_NUMBER() OVER (
            PARTITION BY run_id
            ORDER BY
                CASE
                    WHEN partitions IS NOT NULL
                        AND estimated_calls IS NOT NULL
                        THEN 0
                    ELSE 1
                END,
                CASE
                    WHEN run_id IS NOT NULL
                        AND run_id != ''
                        THEN 0
                    ELSE 1
                END,
                ts_load DESC,
                s3_key DESC
        ) AS rn
    FROM
        datalake_vocs_machina_meta_raw.backfill_plans
    WHERE
        run_id IS NOT NULL
        AND run_id != ''
)
SELECT
    uuid_run,
    caution,
    partitions,
    estimated_calls,
    estimated_llm_seconds,
    estimated_wall_clock_seconds,
    estimated_runs_needed,
    estimate_basis_measured_from_last_success,
    estimate_basis_config_default,
    breaker_n_prompts,
    breaker_n_partitions,
    breaker_estimated_calls,
    is_breaker_tripped,
    is_breaker_approved,
    is_breaker_refused,
    s3_key,
    ts_load,
    estimate_basis_counts,
    throughput_calibration,
    backfill_breaker,
    year,
    month,
    day
FROM
    ranked
WHERE
    rn = 1
