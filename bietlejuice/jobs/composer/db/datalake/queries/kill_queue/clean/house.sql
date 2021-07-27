SELECT
    id,
    main_id AS id_main,
    owner_id AS id_owner, 
    region_id AS id_region,
    city,
    complement,
    house_number,
    street_address,
    state,
    version, 
    floor,
    rent_price,
    reservation_fee,
    CAST(reservation_allowed AS BOOLEAN) AS is_reservation_allowed,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_kill_queue_raw.house
WHERE 
    year = {year}
    AND month = {month}
    AND day = {day}