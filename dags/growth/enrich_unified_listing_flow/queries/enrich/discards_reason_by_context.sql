WITH
context_rene AS (
    SELECT
        id_house_lead,
        CASE
            WHEN business_context = 'SALE' THEN reason
            ELSE NULL
        END AS is_sale,
        CASE
            WHEN business_context = 'RENT' THEN reason
            ELSE NULL
        END AS is_rent
    FROM
        datalake_rene_descartes_clean.lead_rejection
    WHERE origin != 'PROSPECT' 
),
discard_rene AS (
    SELECT
        id_house_lead,
        MAX(is_sale) AS discard_sale,
        MAX(is_rent) AS discard_rent
    FROM
        context_rene
    GROUP BY 1
),
unique_wololo AS (
    SELECT distinct
        id_prospect,
        business_context,
        MAX(id) AS id
    FROM
        datalake_wololo_clean.context_discard
    GROUP BY 1, 2
),
context_wololo AS (
    SELECT
        u.id_prospect,
        CASE
            WHEN u.business_context = 'SALE' THEN cd.reason
            ELSE NULL
        END AS is_sale,
        CASE
            WHEN u.business_context = 'RENT' THEN cd.reason
            ELSE NULL
        END AS is_rent
    FROM
        datalake_wololo_clean.context_discard cd
    INNER JOIN
        unique_wololo u
            ON u.id = cd.id
            AND u.business_context = cd.business_context
            AND u.id_prospect = cd.id_prospect
),
wololo_discard AS (
    SELECT
        id_prospect,
        MAX(is_sale) discard_sale,
        MAX(is_rent) discard_rent
    FROM
        context_wololo
    GROUP BY 1
),
conversions AS (
    SELECT distinct
        id_prospect,
        CASE
            WHEN business_context = 'SALE' THEN 'true'
            ELSE NULL
        END AS is_sale,
        CASE
            WHEN business_context = 'RENT' THEN 'true'
            ELSE NULL
        END AS is_rent
    FROM datalake_wololo_clean.conversion
),
conversions_prospect as (
    SELECT
        id_prospect,
        MAX(is_sale) AS conversion_sale,
        MAX(is_rent) AS conversion_rent
    FROM
        conversions
    GROUP by 1
)
SELECT
    lead.id AS id_lead,
    lead.is_for_rent,
    lead.is_for_sale,
    r.discard_rent AS lead_discard_rent,
    r.discard_sale AS lead_discard_sale,
    p.status AS prospect_status,
    COALESCE(w.discard_rent, lead.reason_detail) AS prospect_discard_rent,
    w.discard_sale AS prospect_discard_sale,
    cp.conversion_rent,
    cp.conversion_sale
FROM
    datalake_lead.lead
LEFT JOIN
    datalake_wololo_clean.prospect p
        ON cast(p.id_reference AS string) = lead.id
LEFT JOIN
    wololo_discard w
        ON w.id_prospect = p.id
LEFT JOIN
    discard_rene r
        ON r.id_house_lead = lead.id_external
LEFT JOIN
    conversions_prospect cp
        ON cp.id_prospect = p.id
