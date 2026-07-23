WITH leads AS (
    SELECT
        lc.id,
        CAST(lc.id_property AS BIGINT) AS id_house,
        h.id_region,
        lc.user_name,
        REGEXP_EXTRACT(lrw.user_phone_number,'([0-9]+)', 1) AS user_phone_number,
        REGEXP_EXTRACT(lc.user_ddd,'([0-9]+)', 1) AS user_ddd,
        LOWER(lre.user_email) AS user_email,
        lc.origin_partner,
        lc.ts_received
    FROM 
        datalake_classified_leads_clean.lead_contact AS lc
    LEFT JOIN
        datalake_classified_leads_clean.lead_reply_whatsapp AS lrw
            ON lc.id = lrw.id_lead
    LEFT JOIN
        datalake_classified_leads_clean.lead_reply_email AS lre
            ON lc.id = lre.id_lead
    LEFT JOIN 
        datalake_ebdb_clean.house AS h
            ON h.id = lc.id_property
    WHERE
        lc.business_context = 'SALE'
        AND CAST(lc.ts_received AS DATE) || lc.id_property != '2021-07-30893359741'
),
clean_leads AS (
    SELECT *,
        CASE
            WHEN RIGHT(user_phone_number, 7) IN (
                '1111111',
                '9999999',
                '0000000',
                '1212121',
                '3456789',
                '1234567',
                '2222222',
                '3333333',
                '4444444',
                '5555555',
                '6666666',
                '7777777',
                '8888888',
                '9999991'
            )
                THEN NULL
            WHEN LENGTH(user_phone_number) IN (11,10) AND SUBSTRING(user_phone_number,1,2) = '55' 
                THEN '+55' || COALESCE(NULLIF(user_ddd,''),'11') || SUBSTRING(user_phone_number,3)
            WHEN LENGTH(user_phone_number) IN (11,10) AND SUBSTRING(user_phone_number,1,2) != '55' 
                THEN '+55' || user_phone_number
            WHEN LENGTH(user_phone_number) IN (8,9)
                THEN '+55' || COALESCE(NULLIF(user_ddd,''),'11') || user_phone_number
            WHEN LENGTH(user_phone_number) < 8 
                THEN NULL
            ELSE '+' || user_phone_number
        END AS clean_phone_number
    FROM
        leads AS l
)
SELECT
    id AS id_classified_lead,
    id_region,
    id_house,
    user_email AS email,
    clean_phone_number AS phone_number,
    origin_partner,
    ts_received AS ts_intent
FROM
    clean_leads
WHERE
    clean_phone_number IS NOT NULL
    OR user_email IS NOT NULL