SELECT
    CAST(id AS BIGINT) AS id_segment_distribution,
    CAST(segment_id AS BIGINT) AS id_segment,
    CAST(communication_audience_id AS BIGINT) AS id_communication_audience,
    customer_document_type,
    customer_document_value,
    version,
    active AS is_active,
    last_appearance_date AS dt_last_appearance,
    entered_segment_at AS ts_entered_segment,
    created_at AS ts_created,
    updated_at AS ts_updated,
    NOW() AS ts_load
FROM
    datalake_trato_feito_raw.segment_distribution
