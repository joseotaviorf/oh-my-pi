SELECT
    CAST(id AS BIGINT) AS id_audience_negotiation_option,
    CAST(negotiation_option_id AS BIGINT) AS id_negotiation_option,
    CAST(audience_id AS BIGINT) AS id_audience,
    version,
    negotiation_option_priority,
    active AS is_active,
    created_at AS ts_created,
    updated_at AS ts_updated,
    NOW() AS ts_load
FROM
    datalake_trato_feito_raw.audience_negotiation_option
