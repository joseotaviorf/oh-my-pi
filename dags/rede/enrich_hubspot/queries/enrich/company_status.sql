WITH exploded_history_sale AS (
    SELECT
        id_company::BIGINT,
        EXPLODE(sale_lead_status_history) AS lead_status_struct
    FROM
        datalake_hubspot.company
),
exploded_history_rent AS (
    SELECT
        id_company::BIGINT,
        EXPLODE(rent_lead_status_history) AS lead_status_struct
    FROM
        datalake_hubspot.company
),
extracted_properties AS (
    SELECT
        id_company,
        lead_status_struct['updatedByUserId'] AS id_user_updated_by,
        lead_status_struct['sourceType'] AS source_type,
        'SALE' AS business_context,
        lead_status_struct.value AS lead_status,
        lead_status_struct.timestamp AS ts_status_started,
        LEAD(lead_status_struct.timestamp) OVER (
            PARTITION BY
                id_company
            ORDER BY
                lead_status_struct.timestamp
            ) AS ts_status_ended
    FROM
        exploded_history_sale
    UNION ALL
        SELECT
        id_company,
        lead_status_struct['updatedByUserId'] AS id_user_updated_by,
        lead_status_struct['sourceType'] AS source_type,
        'RENT' AS business_context,
        lead_status_struct.value AS lead_status,
        lead_status_struct.timestamp AS ts_status_started,
        LEAD(lead_status_struct.timestamp) OVER (
            PARTITION BY
                id_company
            ORDER BY
                lead_status_struct.timestamp
            ) AS ts_status_ended
    FROM
        exploded_history_rent
)
SELECT
    id_company,
    id_user_updated_by,
    source_type,
    business_context,
    lead_status,
    DATEDIFF(COALESCE(ts_status_ended, NOW()), ts_status_started) AS days_in_status,
    lead_status IN ('Parceiro', 'Membro', 'Em processo tombamento') AS is_partner,
    ts_status_started,
    ts_status_ended
FROM
    extracted_properties