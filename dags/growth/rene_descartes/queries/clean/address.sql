SELECT
    id,
    country AS country_code,
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
    updated_at AS ts_updated,
    YEAR(updated_at) AS year,
    MONTH(updated_at) AS month,
    DAY(updated_at) as day
FROM
    datalake_rene_descartes_raw.address
