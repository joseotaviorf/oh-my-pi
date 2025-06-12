WITH base AS (
    SELECT
        rde.id_tenant_prospect AS id_user,
        u.uuid_person,
        MIN(rde.ts_event) AS ts_first_event,
        MAX(rde.ts_event) AS ts_last_event
    FROM
        datalake_rent_demand_events.rent_demand_events AS rde
    LEFT JOIN
        datalake_ebdb_clean.user AS u
            ON u.id = rde.id_tenant_prospect
    GROUP BY 1, 2
),
latest_event AS (
    SELECT
        id_tenant_prospect AS id_user,
        CASE
            WHEN id_event_type IN (1, 2, 11, 12, 13, 14) THEN 'VISIT'
            WHEN id_event_type IN (3, 4) THEN 'OFFER'
            WHEN id_event_type IN (5, 6, 7, 8) THEN 'PROPOSAL'
            WHEN id_event_type IN (9, 10) THEN 'CONTRACT'
            ELSE NULL
        END AS journey_step
    FROM
        datalake_rent_demand_events.rent_demand_events AS rde
    JOIN
        base AS b
            ON b.id_user = rde.id_tenant_prospect
    WHERE
        b.ts_last_event = rde.ts_event 
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY rde.id_tenant_prospect ORDER BY rde.ts_event DESC) = 1
)
SELECT 
    b.id_user,
    b.uuid_person,
    le.journey_step,
    IF(DATEDIFF(NOW(), b.ts_last_event) <= 30, TRUE, FALSE) AS is_active,
    b.ts_first_event,
    b.ts_last_event,
    NOW() AS ts_load
FROM
    base AS b
JOIN
    latest_event AS le
        ON le.id_user = b.id_user