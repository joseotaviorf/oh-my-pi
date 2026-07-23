WITH visit_rent_flow AS (
    SELECT
        frde.sk_visit,
        LOWER(dret.abbreviation) AS event_code,
        'RENT' AS business_context,
        MIN(frde.ts_event) AS ts_first_event,
        MAX(frde.ts_event) AS ts_last_event
    FROM
        dw_rent.fact_rent_demand_events AS frde
    INNER JOIN
        dw_rent.dim_rent_event_type AS dret
            ON dret.sk_event_type = frde.sk_event_type
    WHERE
        LOWER(dret.abbreviation) IN ('os','oa','cs')
        AND sk_visit IS NOT NULL
    GROUP BY 1, 2, 3
),
visit_sale_flow AS (
    SELECT
        fsde.sk_visit,
        IF(LOWER(dset.abbreviation) = 'ccv', 'cs', LOWER(dset.abbreviation)) AS event_code,
        'SALE' AS business_context,
        MIN(fsde.ts_event) AS ts_first_event,
        MAX(fsde.ts_event) AS ts_last_event
    FROM
        dw_sale.fact_sale_demand_event AS fsde
    INNER JOIN
        dw_sale.dim_sale_event_type AS dset
            ON dset.sk_event_type = fsde.sk_event_type
    WHERE
        LOWER(dset.abbreviation) IN ('os', 'oa', 'ccv')
        AND sk_visit IS NOT NULL
    GROUP BY 1, 2, 3
)
SELECT
    MD5(sk_visit || event_code || business_context) AS sk_visit_funnel,
    sk_visit,
    event_code,
    business_context,
    ts_first_event,
    ts_last_event
FROM
    visit_rent_flow
UNION ALL
SELECT
    MD5(sk_visit || event_code || business_context) AS sk_visit_funnel,
    sk_visit,
    event_code,
    business_context,
    ts_first_event,
    ts_last_event
FROM
    visit_sale_flow
