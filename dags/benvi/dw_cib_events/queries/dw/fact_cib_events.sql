WITH sum_events AS (
    SELECT
        id_cib AS sk_cib,
        id_event AS sk_event,
        id_house AS sk_house,
        id_house_listing AS sk_house_listing,
        id_contract AS sk_contract,
        dt_event,
        SUM(IF(event_type = 'FL', 1, 0)) AS first_listings,
        SUM(IF(event_type = 'CS', 1, 0)) AS contracts_signed,
        year,
        month,
        day
    FROM
        datalake_mexico_cib_events.cib_events
    WHERE
      year = {year}
      AND month = {month}
      AND day = {day}
    GROUP BY
        1, 2, 3, 4, 5, 6, 9, 10, 11
)
SELECT
    se.sk_cib,
    COALESCE(cs.id_segmentation, 1) AS sk_segmentation,
    se.sk_event,
    se.sk_house,
    se.sk_house_listing,
    se.sk_contract,
    se.first_listings,
    se.contracts_signed,
    se.dt_event,
    se.year,
    se.month,
    se.day
FROM
    sum_events AS se
LEFT JOIN
    datalake_mexico_cib_segmentation.cib_segmentation AS cs
        ON cs.id_cib = se.sk_cib
        AND se.year = cs.year
        AND se.month = cs.month
