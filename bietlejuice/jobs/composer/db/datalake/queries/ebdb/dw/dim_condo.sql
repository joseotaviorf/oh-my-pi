SELECT
    c.id AS sk_condo,
    c.id AS id_condo,
    c.neighborhood,
    c.zipcode,
    c.city,
    c.address,
    c.lat,
    c.lng,
    c.name,
    c.number,
    c.ts_created,
    c.ts_updated,
    now() AS ts_load
FROM
    datalake_ebdb_clean.condo AS c
