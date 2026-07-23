WITH main_client AS (
    SELECT
      id_propose,
      id_person AS id_primary_person,
      ROW_NUMBER() OVER(PARTITION BY id_propose ORDER BY ts_updated DESC) AS rn
    FROM
      datalake_rental_guarantee_platform_clean.fiancavelo_proposeperson_legacy
    WHERE
      is_active
        AND id_type = 1 -- bringing only main IQ
  )

  SELECT DISTINCT
    (cp.id + 100) * -1 AS id_person,
    pp.id_propose,
    TRIM(UPPER(cp.name)) AS name,
    cp.email,
    cp.phone,
    CAST(NULL AS STRING) AS bureau_name,
    IF(cp.document IS NULL, '0', cp.document) AS document,
    CAST(NULL AS INT) AS serasa_score,
    CAST(NULL AS INT) AS risk_score,
    CAST(NULL AS INT) AS risk_classification,
    CAST(NULL AS INT) AS score_personal_value,
    CAST(NULL AS INT) AS declared_income,
    CAST(NULL AS INT) AS requested_income,
    mc.id_primary_person IS NOT NULL AS is_primary_person,
    TRUE AS is_legacy,
    cp.dt_birth
  FROM
    datalake_rental_guarantee_platform_clean.clientes_person_legacy AS cp
  LEFT JOIN
    datalake_rental_guarantee_platform_clean.fiancavelo_proposeperson_legacy AS pp
      ON pp.id_person = cp.id
  LEFT JOIN
    main_client AS mc
      ON mc.id_primary_person = cp.id
      AND mc.id_propose = pp.id_propose
