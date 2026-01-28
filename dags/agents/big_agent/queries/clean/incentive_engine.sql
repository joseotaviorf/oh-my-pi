SELECT
    id,
    external_condition_id AS id_external_condition,
    external_condition_type,
    incentive_system,
    status,
    DATE(classification_start_at) AS dt_classification_started,
    DATE(classification_end_at) AS dt_classification_ended,
    DATE(partner_tier_validity_start_at) AS dt_partner_tier_validity_started,
    DATE(partner_tier_validity_end_at) AS dt_partner_tier_validity_ended,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.incentive_engine