SELECT
    CAST(id AS BIGINT) AS id_contract_segment_distribution,
    CAST(segment_id AS BIGINT) AS id_segment,
    CAST(audience_id AS BIGINT) AS id_audience,
    contract_id AS id_contract,
    customer_ids AS id_customer,
    version,
    active AS is_active,
    last_appearance_date AS dt_last_appearance,
    entered_segment_at AS ts_entered_segment,
    entered_audience_at AS ts_entered_audience,
    created_at AS ts_created,
    updated_at AS ts_updated,
    NOW() AS ts_load
FROM
    datalake_trato_feito_raw.contract_segment_distribution
