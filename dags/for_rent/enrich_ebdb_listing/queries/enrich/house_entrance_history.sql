WITH occupant_aud AS (
    SELECT
        aud.id_house,
        aud.id_occupant,
        LAG(id_occupant) OVER(PARTITION BY aud.id_house ORDER BY aud.rev) AS previous_id_occupant,
        aud.rev,
        FROM_UNIXTIME(ure.ts_revision/1000) AS ts_updated    
    FROM
        datalake_ebdb_clean.access_type_aud AS aud
    JOIN
        datalake_ebdb_clean.user_revision_entity AS ure
            ON aud.rev = ure.id
    WHERE
        id_house IS NOT NULL 
),
scd_occupant AS (
  SELECT
      id_house,
      id_occupant,
      rev,
      ts_updated AS ts_occupant_started,
      LEAD(ts_updated) OVER(PARTITION BY id_house ORDER BY rev) AS ts_occupant_ended
  FROM
      occupant_aud
  WHERE
      id_occupant <> COALESCE(previous_id_occupant, -1)
),
doorman_aud AS (
    SELECT
        aud.id_house,
        aud.rev,
        doorman_type,
        LAG(doorman_type) OVER(PARTITION BY aud.id_house ORDER BY aud.rev) AS previous_doorman_type,
        FROM_UNIXTIME(ure.ts_revision/1000) AS ts_updated
    FROM
        datalake_ebdb_clean.house_aud AS aud
    JOIN
        datalake_ebdb_clean.user_revision_entity AS ure
            ON aud.rev= ure.id
    WHERE
        aud.id_house IS NOT NULL
),
scd_doorman AS (
    SELECT
        id_house,
        rev,
        doorman_type,
        ts_updated AS ts_doorman_type_started,
        LEAD(ts_updated) OVER(PARTITION BY id_house ORDER BY rev) AS ts_doorman_type_ended
    FROM
        doorman_aud
    WHERE
        doorman_type <> COALESCE(previous_doorman_type, -1)
),
key_location_aud AS (
    SELECT
        ata.id_house,
        ata.rev,
        aat.name AS key_location,
        kt.name AS key_type,
        LAG(aat.name) OVER(PARTITION BY ata.id_house ORDER BY ata.rev) AS previous_key_location,
        LAG(kt.name) OVER(PARTITION BY ata.id_house ORDER BY ata.rev) AS previous_key_type,
        FROM_UNIXTIME(ure.ts_revision/1000) AS ts_updated
    FROM
        datalake_ebdb_clean.access_type_aud AS ata
    JOIN
        datalake_ebdb_clean.user_revision_entity AS ure
            ON ata.rev = ure.id
    JOIN
        datalake_ebdb_clean.access_authorization_type AS aat
            ON ata.id_authorization = aat.id
    JOIN
        datalake_ebdb_clean.key_type AS kt
            ON ata.id_type = kt.id
),
scd_key_location AS (
    SELECT
        id_house,
        rev,
        key_location,
        key_type,
        ts_updated AS ts_key_location_started,
        LEAD(ts_updated) OVER(PARTITION BY id_house ORDER BY rev) AS ts_key_location_ended
    FROM
        key_location_aud
    WHERE
        key_location <> COALESCE(previous_key_location, -1)
        OR key_type <> COALESCE(previous_key_type, -1)
),
event_bus AS (
    SELECT
        id_house,
        rev,
        TIMESTAMP(ts_occupant_started) AS ts_event
    FROM
        scd_occupant
    UNION
    SELECT
        id_house,
        rev,
        TIMESTAMP(ts_doorman_type_started) AS ts_event
    FROM
        scd_doorman
    UNION
    SELECT
        id_house,
        rev,
        TIMESTAMP(ts_key_location_started) AS ts_event
    FROM
        scd_key_location
)
SELECT
    eb.id_house,
    so.id_occupant,
    COALESCE(ch.country_code, 'Undefined') AS country_code,
    eb.rev,
    sd.doorman_type,
    skl.key_location,
    skl.key_type,
    COALESCE(MAX(eb.rev) OVER(PARTITION BY eb.id_house, DATE(eb.ts_event)) = eb.rev, FALSE) AS is_last_status_of_day,
    eb.ts_event AS ts_entrance_started,
    LEAD(eb.ts_event) OVER(PARTITION BY eb.id_house ORDER BY eb.rev) AS ts_entrance_ended
FROM
    event_bus AS eb
LEFT JOIN
    scd_occupant AS so
        ON eb.ts_event >= so.ts_occupant_started
        AND eb.ts_event < COALESCE(so.ts_occupant_ended, '2100-01-01')
        AND eb.id_house = so.id_house
LEFT JOIN
    scd_doorman AS sd
        ON eb.ts_event >= sd.ts_doorman_type_started
        AND eb.ts_event < COALESCE(sd.ts_doorman_type_ended, '2100-01-01')
        AND eb.id_house = sd.id_house
LEFT JOIN
    scd_key_location AS skl
        ON eb.ts_event >= skl.ts_key_location_started
        AND eb.ts_event < COALESCE(skl.ts_key_location_ended, '2100-01-01')
        AND eb.id_house = skl.id_house
LEFT JOIN
    datalake_ebdb_country.house AS ch
        ON ch.id_house = eb.id_house