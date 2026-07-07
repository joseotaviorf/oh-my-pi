SELECT
    feedback_id AS id_feedback,
    prompt_id AS id_prompt,
    author_id AS id_author,
    account_id AS id_account,
    run_id AS uuid_run,
    prompt_hash,
    reasoning,
    verbatim_text,
    feedback_kind,
    source_name,
    customer_type,
    campaign_name,
    llm_model,
    llm_temperature,
    prompt_collection,
    prompt_opportunity,
    rating,
    label AS is_label,
    submitted_at AS ts_submitted,
    ts_classified,
    ts_load,
    year,
    month,
    day
FROM
    datalake_vocs_machina_raw.vocs_machina
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
