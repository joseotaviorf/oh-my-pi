WITH exploded_history AS (
    SELECT
        id_company::BIGINT,
        EXPLODE(lead_status_history) AS lead_status_struct
    FROM
        datalake_hubspot.company
),
extracted_properties AS (
    SELECT
        id_company,
        lead_status_struct.value AS lead_status,
        lead_status_struct.timestamp AS ts_status_started,
        LEAD(lead_status_struct.timestamp) OVER (
            PARTITION BY
                id_company
            ORDER BY
                lead_status_struct.timestamp
            ) AS ts_status_ended
    FROM
        exploded_history
)
SELECT
    id_company,
    lead_status,
    DATEDIFF(COALESCE(ts_status_ended, NOW()), ts_status_started) AS days_in_status,
    ts_status_started,
    ts_status_ended
FROM
    extracted_properties