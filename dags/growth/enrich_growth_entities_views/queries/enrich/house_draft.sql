SELECT
    hd.id AS id_entity,
    h.id AS id_house,
    CAST(NULL AS BIGINT) AS id_contract,
    r.id_main AS id_user,
    'HOUSE_DRAFT' AS entity,
    'OWNER' AS persona,
    CAST(NULL AS STRING) AS business_context,
    TO_JSON(
        STRUCT(
            hd.status AS status,
            hd.ts_created AS when
        )
    ) AS properties,
    CASE
        WHEN hd.status IN ('EDITING', 'PROCESSING') THEN TRUE
        ELSE FALSE
    END AS is_active,
    hd.ts_created,
    hd.ts_updated
FROM
    datalake_bob_clean.house_draft AS hd
LEFT JOIN
    datalake_ebdb_clean.house AS h
        ON h.id_external = hd.id
LEFT JOIN
    datalake_bob_clean.registrar AS r
        ON hd.registrar = r.id
WHERE
    hd.type = 'FULL_SELF_SERVICE'
