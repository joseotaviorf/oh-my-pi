SELECT
    id,
    main_id AS id_main,
    owner_id AS id_owner, 
    region_id AS id_region,
    city,
    complement,
    CAST(house_number AS INT) AS house_number,
    street_address,
    state,
    CAST(version AS SMALLINT) AS version, 
    CAST(floor AS SMALLINT) AS floor,
    CAST(rent_price AS FLOAT) AS rent_price,
    CAST(reservation_fee AS FLOAT) AS reservation_fee,
    CAST(reservation_allowed AS BOOLEAN) AS is_reservation_allowed,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_kill_queue_raw.house