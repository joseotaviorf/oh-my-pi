WITH base AS (
    SELECT
        asvi.id_user,
        asvi.ts_visit_intent,
        dr.sk_region,
        dr.city_name,
        ROW_NUMBER() OVER (PARTITION BY asvi.id_user ORDER BY asvi.ts_visit_intent) AS rw
    FROM
        datalake_amplitude_sale_visit_intent.amplitude_sale_visit_intent AS asvi
    LEFT JOIN
        dw_sale.fact_listings AS fl
        	ON fl.sk_house = asvi.id_house
    LEFT JOIN
    	dw_public.dim_region AS dr
        	ON dr.sk_region = fl.sk_region
)
SELECT
    id_user,
    sk_region,
    city_name,
    ts_visit_intent AS ts_first_visit_intent
FROM
    base
WHERE
    rw = 1
