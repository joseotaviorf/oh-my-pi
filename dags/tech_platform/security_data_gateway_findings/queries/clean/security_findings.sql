SELECT
    resource_id AS id_resource,
    source,
    event_type,
    resource_type,
    resource_name,
    location,
    actor_email,
    risk_level,
    classified_at AS ts_classified,
    pii_types_detected,
    source_metadata,
    source_raw_payload,
    year,
    month,
    day
FROM
    datalake_security_data_gateway_raw.security_findings
