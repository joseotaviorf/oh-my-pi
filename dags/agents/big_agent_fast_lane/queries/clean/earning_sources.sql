SELECT
    id,
    external_domain_id AS id_external_domain,
    earning_source_uuid AS uuid_earning_source,
    external_cart_uuid AS uuid_external_cart,
    external_domain_type,
    currency,
    status,
    failure_reason,
    base_amount,
    revenue_share_total_amount,
    incentive_systems_calculation_status,
    DATE(competence_date) AS dt_competence,
    TIMESTAMP(occurred_at) AS ts_occurred,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.earning_sources