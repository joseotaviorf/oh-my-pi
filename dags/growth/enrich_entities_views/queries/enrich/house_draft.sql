SELECT
    hd.id AS id_entity,
    h.id AS id_house,
    r.id_main AS id_owner,
    NULL AS id_contract,
    'HOUSE_DRAFT' AS entity,
    'OWNER' AS persona,
    NULL AS business_context,
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
    datalake_bob_clean.house_draft hd
  LEFT JOIN
    datalake_ebdb_clean.house h
  ON
    h.id_external = hd.id
  LEFT JOIN
    datalake_bob_clean.registrar r
  ON
    hd.registrar = r.id
  WHERE hd.type = 'FULL_SELF_SERVICE'
