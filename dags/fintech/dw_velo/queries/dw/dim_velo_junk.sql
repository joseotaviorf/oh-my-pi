SELECT
    id_junk AS sk_junk,
    id_master_type,
    id_lvl_1,
    desc_master_type,
    desc_lvl_1,
    NOW() AS ts_load
FROM
    datalake_velo.junk
