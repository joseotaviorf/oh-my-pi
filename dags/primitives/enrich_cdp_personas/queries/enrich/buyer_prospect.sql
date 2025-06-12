WITH base AS (
    SELECT
        sde.id_buyer AS id_user,
        u.uuid_person,
        MIN(sde.ts_event) AS ts_first_event,
        MAX(sde.ts_event) AS ts_last_event
    FROM
        datalake_sale_demand_events.sale_demand_events AS sde
    LEFT JOIN
        datalake_ebdb_clean.user AS u
            ON u.id = sde.id_buyer
    WHERE
        sde.id_buyer IS NOT NULL
        AND sk_event_type <> 6 -- SALE_AGREEMENT_SIGNED
    GROUP BY 1, 2
),
latest_event AS (
    SELECT
        id_buyer AS id_user,
        CASE
            WHEN sk_event_type IN (1, 2, 7) THEN 'VISIT'
            WHEN sk_event_type IN (3, 4, 8) THEN 'OFFER'
            WHEN sk_event_type = 5 THEN 'CLOSING'
            ELSE NULL
        END AS journey_step
    FROM
        datalake_sale_demand_events.sale_demand_events AS sde
    JOIN
        base AS b
            ON b.id_user = sde.id_buyer
    WHERE
        b.ts_last_event = sde.ts_event
        AND sde.sk_event_type <> 6
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY sde.id_buyer ORDER BY sde.ts_event DESC) = 1
)
SELECT
    b.id_user,
    b.uuid_person,
    le.journey_step,
    CAST(NULL AS BOOLEAN) AS is_active,
    b.ts_first_event,
    b.ts_last_event
FROM
    base AS b
JOIN
    latest_event AS le
        ON b.id_user = le.id_user