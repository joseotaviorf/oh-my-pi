SELECT
    d.id_dejavu,
    cf.*
FROM
    datalake_vespucio.condo_full AS cf
LEFT JOIN
    datalake_vespucio.dejavu AS d
    ON d.address_type = "condo"
        AND cf.id_condo = d.id_address