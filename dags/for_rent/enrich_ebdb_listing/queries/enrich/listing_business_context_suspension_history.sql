WITH events AS (
    SELECT 
        id_house,
        business_context,
        suspension_reason,
        CAST(FROM_UNIXTIME(CAST(ure.ts_revision/1000 AS BIGINT)) AS TIMESTAMP) AS ts_event,
        ROW_NUMBER() OVER(PARTITION BY id_house, business_context ORDER BY CAST(FROM_UNIXTIME(CAST(ure.ts_revision/1000 AS BIGINT)) AS TIMESTAMP)) AS event_order
    FROM 
        datalake_ebdb_clean.listing_business_context_aud AS aud
    JOIN 
        datalake_ebdb_clean.user_revision_entity AS ure 
            ON aud.rev = ure.id
    WHERE 
        mod_suspension_reason IS TRUE
                
), 
event_order AS (
    SELECT
        e.id_house,
        COALESCE(ch.country_code, 'Undefined') AS country_code,
        COALESCE(NULLIF(e.business_context, ''), 'Undefined') AS business_context,
        e.suspension_reason,
        e.ts_event AS ts_status_started,
        e2.ts_event AS ts_status_ended,
        ROW_NUMBER() OVER(PARTITION BY e.id_house, e.business_context, e.suspension_reason ORDER BY e.ts_event) AS event_order
    FROM 
        events AS e
    LEFT JOIN 
        events AS e2
            ON e2.id_house = e.id_house
            AND e2.business_context = e.business_context
            AND e.event_order = e2.event_order - 1
    LEFT JOIN
        datalake_ebdb_country.house AS ch
            ON ch.id_house = e.id_house

)
SELECT
    eo.id_house,
    eo.country_code,
    eo.business_context,
    eo.suspension_reason,
    eo.ts_status_started,
    COALESCE(eo2.ts_status_ended, eo.ts_status_ended) AS ts_status_ended
FROM
    event_order AS eo
LEFT JOIN 
    event_order AS eo2
        ON eo.id_house = eo2.id_house
        AND eo.business_context = eo2.business_context
        AND eo.event_order = eo2.event_order - 1
WHERE 
    eo.event_order = 1