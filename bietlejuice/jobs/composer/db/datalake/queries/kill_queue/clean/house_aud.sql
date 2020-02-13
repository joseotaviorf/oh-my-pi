SELECT
    id,
    rev,
    revtype as rev_type,
    revend as rev_end,
    city,
    complement,
    floor,
    house_number,
    state,
    street_address,
    main_id as id_main,
    rent_price,
    rent_price_mod as is_rent_price_mod,
    reservation_allowed as is_reservation_allowed,
    reservation_allowed_mod as is_reservation_allowed_mod,
    reservation_fee,
    reservation_fee_mod as is_reservation_fee_mod,
    region_id as id_region,
    owner_id as id_owner
FROM
    datalake_kill_queue_raw.house_aud