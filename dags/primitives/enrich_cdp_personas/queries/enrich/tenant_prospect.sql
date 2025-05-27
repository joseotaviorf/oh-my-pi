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
)
SELECT 
    id_user,
    uuid_person,
    IF(DATEDIFF(NOW(), ts_last_event) <= 30, TRUE, FALSE) AS is_active,
    ts_first_event,
    ts_last_event,
    NOW() AS ts_load
FROM
    base