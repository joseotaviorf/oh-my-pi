SELECT
    uuid AS uuid_lead_resolution,
    lead_session_uuid AS uuid_lead_session,
    property_id AS id_property,
    type,
    summary,
    metadata,
    CAST(resolved_at AS TIMESTAMP) AS ts_resolved,
    CAST(sent_to_crm_at AS TIMESTAMP) AS ts_sent_to_crm,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    YEAR(CAST(updated_at AS TIMESTAMP)) AS year,
    MONTH(CAST(updated_at AS TIMESTAMP)) AS month,
    DAY(CAST(updated_at AS TIMESTAMP)) AS day
FROM
    datalake_alias_raw.lead_resolutions