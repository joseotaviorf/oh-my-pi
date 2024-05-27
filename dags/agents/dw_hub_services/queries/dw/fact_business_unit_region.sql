WITH business_unit_region AS (
    SELECT 
        XXHASH64(bura.id_region, bura.id_business_unit) AS id_business_region,
        bura.id_business_unit,
        bura.id_region,
        bura.rev_end,
        LEAD(bura.ts_created) OVER(PARTITION BY bura.id_region, bura.id_business_unit ORDER BY bura.ts_updated) AS ts_later_created,
        bura.ts_created,
        bura.ts_updated
    FROM
        datalake_hub_services_clean.business_unit_region_aud AS bura
),
business_unit_region_ended AS (
    SELECT
        bur.id_business_region,
        COALESCE(rev.ts_created, bur.ts_later_created) AS ts_ended
    FROM
        business_unit_region AS bur
    LEFT JOIN 
        datalake_hub_services_clean.rev_info AS rev 
            ON rev.id = bur.rev_end
            AND rev.ts_created >= bur.ts_created
)
SELECT DISTINCT
    bur.id_business_region AS sk_business_unit_region,
    bur.id_business_unit AS sk_business_unit,
    bur.id_region AS sk_region,
    bure.ts_ended IS NULL AS is_active,
    FIRST(bur.ts_created) OVER(PARTITION BY bur.id_business_region ORDER BY bur.ts_updated) AS ts_operations_started,
    bure.ts_ended AS ts_operations_ended,
    NOW() AS ts_load
FROM 
    business_unit_region AS bur
LEFT JOIN
    business_unit_region_ended AS bure
        ON bure.id_business_region = bur.id_business_region
        AND bure.ts_ended IS NOT NULL