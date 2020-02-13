SELECT
    id,
    timestamp(created_at) as ts_created,
    timestamp(updated_at) as ts_updated,
    version,
    main_id as id_main,
    street_address,
    house_number,
    complement,
    city,
    state,
    reservation_allowed as is_reservation_allowed,
    rent_price,
    floor,
    reservation_fee,
    region_id as id_region,
    owner_id as id_owner
FROM
    datalake_kill_queue_raw.house