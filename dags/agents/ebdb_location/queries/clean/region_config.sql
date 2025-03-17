SELECT
    id,
    region_id AS id_region,
    placeId AS id_place,
    timezoneId AS id_timezone,
    maxPrice AS max_price,
    minPrice AS min_price,
    phoneDDD AS phone_ddd,
    featuredPhoto AS featured_photo,
    featuredRank AS featured_rank,
    shelfPrimeFee AS shelf_prime_fee,
    houseReferralEnabled AS is_house_referral_enabled,
    houseRegistrationEnabled AS is_house_registration_enabled,
    searchEnabled AS is_search_enabled,
    visitsEnabled AS is_visit_enabled,
    addressNumberRequired AS is_address_number_required,
    criadoEm AS ts_created,
    atualizadoEm AS ts_updated
FROM
    datalake_ebdb_raw.regionconfig