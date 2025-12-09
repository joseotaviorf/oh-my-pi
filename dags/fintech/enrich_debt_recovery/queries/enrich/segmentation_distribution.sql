SELECT
    csdh.id_contract_segment_distribution_history,
    csdh.id_contract,
    csdh.id_customer,
    csdh.id_segment,
    csdh.id_audience,
    a.id_communication_audience,
    a.id_communication_sequence,
    s.collector_key AS segment_collector_key,
    a.collector_audience_key,
    s.name AS segment_name,
    s.description AS segment_description,
    s.priority AS segment_priority,
    a.name AS audience_name,
    a.distribution_percentage,
    csdh.revision_number,
    csdh.revision_type,
    s.version AS segment_version,
    a.version AS audience_version,
    csdh.is_active,
    csdh.is_active_modified,
    csdh.is_segment_modified,
    csdh.is_audience_modified,
    csdh.is_contract_modified,
    csdh.is_entered_segment_modified,
    csdh.is_entered_audience_modified,
    csdh.is_last_appearance_modified,
    csdh.is_id_customers_modified,
    s.is_active AS is_segment_active,
    a.is_active AS is_audience_active,
    csdh.dt_last_appearance,
    csdh.revision_end AS dt_revision_end,
    a.dt_start AS dt_audience_start,
    a.dt_end AS dt_audience_end,
    csdh.ts_entered_segment,
    csdh.ts_entered_audience,
    csdh.ts_created,
    csdh.ts_updated,
    s.ts_created AS ts_segment_created,
    s.ts_updated AS ts_segment_updated,
    a.ts_created AS ts_audience_created,
    a.ts_updated AS ts_audience_updated,
    NOW() AS ts_load
FROM
    datalake_trato_feito_clean.contract_segment_distribution_history AS csdh
LEFT JOIN
    datalake_trato_feito_clean.segment AS s
    ON s.id_segment = csdh.id_segment
LEFT JOIN
    datalake_trato_feito_clean.audience AS a
    ON a.id_communication_audience = csdh.id_audience
