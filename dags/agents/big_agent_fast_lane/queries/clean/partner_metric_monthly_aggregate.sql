SELECT
    id,
    partner_external_id AS id_partner_external,
    user_id AS id_user,
    partner_external_type,
    metric_name,
    reference_date AS dt_reference,
    metric_value,
    highest_revision,
    TIMESTAMP(highest_source_updated_at) AS ts_highest_source_updated,
    source,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.partner_metric_monthly_aggregate
