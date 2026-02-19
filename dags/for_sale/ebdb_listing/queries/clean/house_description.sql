SELECT
    id,
    house_id AS id_house,
    house_hash,
    long_description,
    short_rent_description,
    short_sale_description,
    version_description,
    CAST(overwritten_short_description AS BOOLEAN) AS is_overwritten_short_description,
    CAST(overwritten_long_description AS BOOLEAN) AS is_overwritten_long_description,
    CAST(show_description AS BOOLEAN) AS is_show_description,
    criadoEm AS ts_created,
    atualizadoEm AS ts_updated
FROM
    datalake_ebdb_raw.HouseDescription
