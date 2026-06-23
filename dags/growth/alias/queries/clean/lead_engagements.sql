SELECT
    uuid AS uuid_lead_engagement,
    lead_session_uuid AS uuid_lead_session,
    company_uuid AS uuid_company,
    origin_property_id AS id_property,
    origin_lead_id AS id_origin_lead,
    origin,
    message,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    YEAR(CAST(created_at AS TIMESTAMP)) AS year,
    MONTH(CAST(created_at AS TIMESTAMP)) AS month,
    DAY(CAST(created_at AS TIMESTAMP)) AS day
FROM
    datalake_alias_raw.lead_engagements