WITH filtered_custom_fields AS (
    SELECT
        zcf.id_ticket,
        REPLACE(REPLACE(REPLACE(zcf.value_field, '"', ''), '[', ''), ']', '') AS contact_type_tag,
        MAX(ts_updated) AS ts_updated
    FROM
        datalake_zendesk_custom_fields.custom_fields zcf
    WHERE
        zcf.id_field = "360017352951" -- Old contact type
        AND zcf.year = '{year}'
        AND zcf.month = '{month}'
        AND zcf.day = '{day}'
    GROUP BY 1, 2
),
check_prefix AS (
    SELECT
        id_ticket,
        contact_type_tag,
        CASE
            WHEN UPPER(SPLIT(contact_type_tag,'_')[0]) IN ('IQ', 'PP', 'CR', 'FT', 'VT', 'CD', 'AF', 'PO', 'PS') THEN 1
            ELSE 0
        END AS has_valid_prefix
    FROM
        filtered_custom_fields
)
SELECT DISTINCT
    fcf.id_ticket,
    fcf.contact_type_tag,
    CASE
        WHEN cp.has_valid_prefix = 1 THEN UPPER(SPLIT(fcf.contact_type_tag,'_')[0])
    END AS client_taxonomy,
    CASE
        WHEN cp.has_valid_prefix = 1 THEN UPPER(SPLIT(fcf.contact_type_tag,'_')[1])
    END AS category_taxonomy,
    has_valid_prefix,
    fcf.ts_updated,
    YEAR(fcf.ts_updated) AS year,
    MONTH(fcf.ts_updated) AS month,
    DAY(fcf.ts_updated) AS day
FROM
    filtered_custom_fields fcf
JOIN
    check_prefix cp
        ON fcf.contact_type_tag = cp.contact_type_tag
        AND fcf.id_ticket = cp.id_ticket
