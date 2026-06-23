SELECT
    uuid AS uuid_lead,
    company_uuid AS uuid_company,
    phone,
    name,
    email,
    CAST(last_session_activity_at AS TIMESTAMP) AS ts_last_session_activity,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    YEAR(CAST(updated_at AS TIMESTAMP)) AS year,
    MONTH(CAST(updated_at AS TIMESTAMP)) AS month,
    DAY(CAST(updated_at AS TIMESTAMP)) AS day
FROM
    datalake_alias_raw.leads