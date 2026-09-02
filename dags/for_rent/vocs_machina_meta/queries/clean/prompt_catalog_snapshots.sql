SELECT
    prompt_id AS id_prompt,
    run_id AS uuid_run,
    prompt_hash,
    classifier_contract_fingerprint,
    effective_applicability,
    collection,
    opportunity,
    backfill_days,
    active AS is_active,
    CAST(generated_at AS TIMESTAMP) AS ts_generated,
    s3_key,
    ts_load,
    year,
    month,
    day
FROM
    datalake_vocs_machina_meta_raw.prompt_catalog_snapshots
