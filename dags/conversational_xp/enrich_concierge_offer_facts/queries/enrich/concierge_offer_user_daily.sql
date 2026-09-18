WITH offers AS (
    SELECT
        id_tenant_prospect AS id_user,
        id_house,
        ts_offer_submitted
    FROM
        datalake_rent_flows.rent_flows
    WHERE
        ts_offer_submitted IS NOT NULL
        AND DATE(ts_offer_submitted) >= DATE_SUB(CURRENT_DATE(), {days_lookback_7})
        AND DATE(ts_offer_submitted) < CURRENT_DATE()
        AND id_tenant_prospect IS NOT NULL
),
last_offer AS (
    SELECT
        ranked.id_user,
        ranked.id_house AS id_house_last_offer,
        ranked.ts_offer_submitted AS ts_last_offer
    FROM (
        SELECT
            id_user,
            id_house,
            ts_offer_submitted,
            ROW_NUMBER() OVER (
                PARTITION BY id_user
                ORDER BY ts_offer_submitted DESC
            ) AS rn
        FROM
            offers
    ) AS ranked
    WHERE
        ranked.rn = 1
)
SELECT
    last_offer.id_user,
    MAX(CASE WHEN DATE(offers.ts_offer_submitted) >= DATE_SUB(CURRENT_DATE(), 1) THEN TRUE ELSE FALSE END) AS has_rent_offer_1d,
    TRUE AS has_rent_offer_7d,
    last_offer.id_house_last_offer,
    last_offer.ts_last_offer,
    YEAR(CURRENT_DATE()) AS year,
    MONTH(CURRENT_DATE()) AS month,
    DAY(CURRENT_DATE()) AS day
FROM
    last_offer
INNER JOIN
    offers
    ON last_offer.id_user = offers.id_user
GROUP BY
    last_offer.id_user,
    last_offer.id_house_last_offer,
    last_offer.ts_last_offer
