-- Daily snapshot of published listings whose prospect demand over the last 14 days is high
-- relative to their neighborhood, city and city group peers, used to target post-visit
-- offer incentives.
WITH rent_demand_events AS (
    SELECT
        rde.id_house,
        'RENT' AS business_context,
        COUNT(DISTINCT rde.id_tenant_prospect) AS num_prospects
    FROM
        datalake_rent_demand_events.rent_demand_events AS rde
    WHERE
        rde.country_code = 'BR'
        AND rde.id_event_type IN (1, 2, 3)
        AND DATE(rde.ts_event) BETWEEN DATE_SUB(CURRENT_DATE(), 14) AND DATE_SUB(CURRENT_DATE(), 1)
    GROUP BY
        rde.id_house
),
sale_demand_events AS (
    SELECT
        sde.id_house,
        'SALE' AS business_context,
        COUNT(DISTINCT sde.id_buyer) AS num_prospects
    FROM
        datalake_sale_demand_events.sale_demand_events AS sde
    WHERE
        sde.sk_event_type IN (1, 2, 3)
        AND DATE(sde.ts_event) BETWEEN DATE_SUB(CURRENT_DATE(), 14) AND DATE_SUB(CURRENT_DATE(), 1)
    GROUP BY
        sde.id_house
),
demand_events AS (
    SELECT
        id_house,
        business_context,
        num_prospects
    FROM
        rent_demand_events
    UNION ALL
    SELECT
        id_house,
        business_context,
        num_prospects
    FROM
        sale_demand_events
),
published_listings AS (
    SELECT DISTINCT
        lbc.id_house,
        lbc.business_context
    FROM
        datalake_ebdb_clean.listing_business_context AS lbc
    WHERE
        LOWER(lbc.status) = 'published'
),
listings_with_demand AS (
    SELECT
        evt.id_house,
        evt.business_context,
        evt.num_prospects,
        -- Peer demand baseline: weighted blend of the neighborhood, city and city group
        -- averages, with a 25% margin so only clearly above-average listings qualify.
        ROUND(
            1.25 * (
                0.5 * AVG(evt.num_prospects) OVER (
                    PARTITION BY evt.business_context, reg.id, reg.city_name
                )
                + 0.3 * AVG(evt.num_prospects) OVER (
                    PARTITION BY evt.business_context, reg.city_name, reg.city_group
                )
                + 0.2 * AVG(evt.num_prospects) OVER (
                    PARTITION BY evt.business_context, reg.city_group
                )
            ),
            3
        ) AS demand_reference,
        COUNT(*) OVER (
            PARTITION BY evt.business_context, reg.id, reg.city_name
        ) AS num_houses_neighborhood,
        COUNT(*) OVER (
            PARTITION BY evt.business_context, reg.city_group
        ) AS num_houses_city_group
    FROM
        demand_events AS evt
    INNER JOIN
        datalake_ebdb_clean.house AS hse
            ON hse.id = evt.id_house
            AND hse.lat IS NOT NULL
            AND hse.lng IS NOT NULL
    INNER JOIN
        datalake_region.region AS reg
            ON reg.id = hse.id_region
            AND reg.country_code = 'BR'
            AND reg.level = 'SubRegiao'
            AND reg.city_name IS NOT NULL
            AND reg.city_group IS NOT NULL
    INNER JOIN
        published_listings AS pli
            ON pli.id_house = evt.id_house
            AND pli.business_context = evt.business_context
),
listings_snapshot AS (
    SELECT
        id_house,
        business_context,
        num_prospects,
        demand_reference,
        CURRENT_TIMESTAMP() AS ts_snapshot,
        YEAR(CURRENT_DATE()) AS year,
        MONTH(CURRENT_DATE()) AS month,
        DAY(CURRENT_DATE()) AS day
    FROM
        listings_with_demand
    WHERE
        num_prospects >= GREATEST(3, demand_reference)
        AND num_houses_neighborhood >= 5
        AND num_houses_city_group >= 20
)
SELECT
    CONCAT_WS('_', CAST(id_house AS STRING), business_context, CAST(year AS STRING), CAST(month AS STRING), CAST(day AS STRING)) AS id,
    id_house,
    business_context,
    num_prospects,
    demand_reference,
    ts_snapshot,
    year,
    month,
    day
FROM
    listings_snapshot
