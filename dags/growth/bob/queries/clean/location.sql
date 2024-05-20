SELECT
    house_draft_id AS id_house_draft,
    region_id AS id_region,
    address,
    number,
    floor,
    complement,
    reference_point,
    neighborhood,
    city,
    state,
    zip_code,
    lat,
    lng,
    out_of_area AS is_out_of_area
FROM
    datalake_bob_raw.location
