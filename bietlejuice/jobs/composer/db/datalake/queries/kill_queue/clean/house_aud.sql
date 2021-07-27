SELECT
    id,
    main_id AS id_main,
    owner_id AS id_owner,
    region_id AS id_region,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    city,
    complement,
    floor,
    house_number,
    state,
    street_address,
    rent_price,
    reservation_fee,
    CAST(reservation_allowed AS BOOLEAN) AS is_reservation_allowed,
    CAST(rent_price_mod AS BOOLEAN) AS mod_has_rent_price,
    CAST(reservation_fee_mod AS BOOLEAN) AS mod_has_reservation_fee,
    CAST(reservation_allowed_mod AS BOOLEAN) AS mod_is_reservation_allowed
FROM
    datalake_kill_queue_raw.house_aud