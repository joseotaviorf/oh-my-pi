SELECT
    CAST(id AS BIGINT) AS id,
    CAST(main_id AS BIGINT) AS id_main,
    CAST(owner_id AS BIGINT) AS id_owner, 
    CAST(region_id AS BIGINT) AS id_region,
    CAST(city AS STRING) AS city,
    CAST(complement AS STRING) AS complement,
    CAST(house_number AS INT) AS house_number,
    CAST(street_address AS STRING) AS street_address,
    CAST(state AS STRING) AS state,
    CAST(version AS SMALLINT) AS version, 
    CAST(floor AS SMALLINT) AS floor,
    CAST(rent_price AS FLOAT) AS rent_price,
    CAST(reservation_fee AS FLOAT) AS reservation_fee,
    CAST(reservation_allowed AS BOOLEAN) AS is_reservation_allowed,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_kill_queue_raw.house
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}