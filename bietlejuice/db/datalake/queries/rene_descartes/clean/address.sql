SELECT
    id,
    zip,
    state,
    city,
    neighbourhood,
    street_name,
    house_number,
    complement,
    reference,
    lat,
    lng,
    region,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_rene_descartes_raw.address