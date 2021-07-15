WITH filtered_custom_fields AS (
    SELECT
        zcf.id_ticket,
        zcf.custom_fields['Motivo de contato'] AS contact_type_tag
    FROM
        datalake_zendesk_custom_fields.custom_fields zcf -- Old contact type, id_ticket_field = 360017352951
),
max_ticket_updated AS (
    SELECT
        tck.id_ticket,
        MAX(tck.ts_updated) AS ts_updated
    FROM
        datalake_zendesk_tickets_clean.tickets tck
    JOIN
        filtered_custom_fields cf
            ON tck.id_ticket = cf.id_ticket
    GROUP BY 1
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
    cp.has_valid_prefix,
    mtu.ts_updated,
    YEAR(mtu.ts_updated) AS year,
    MONTH(mtu.ts_updated) AS month,
    DAY(mtu.ts_updated) AS day
FROM
    filtered_custom_fields fcf
JOIN
    check_prefix cp
        ON fcf.contact_type_tag = cp.contact_type_tag
        AND fcf.id_ticket = cp.id_ticket
JOIN
    max_ticket_updated mtu
        ON mtu.id_ticket = fcf.id_ticket
