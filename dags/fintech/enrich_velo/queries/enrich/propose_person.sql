WITH cte_union AS (
(
  WITH person_score AS (
    SELECT
      c.id AS id_score_consultation,
      c.id_person,
      c.value AS score_value,
      c.risk,
      r.name AS risk_classification,
      c.id_bureau,
      b.name AS bureau_name,
      vp.value AS score_personal_value,
      vp.declared AS declared_income,
      vp.requested AS requested_income,
      ROW_NUMBER() OVER(PARTITION BY c.id_person ORDER BY c.ts_updated DESC, c.ts_inserted DESC) AS rn
    FROM
      datalake_velo_clean.veloscore_consultations AS c
    LEFT JOIN
      datalake_velo_clean.veloscore_bureau AS b
        ON b.id = c.id_bureau
    LEFT JOIN
      datalake_velo_clean.veloscore_personal AS vp
        ON vp.consultations = c.id
    LEFT JOIN
      datalake_velo_clean.veloscore_risk AS r
        ON r.id = c.risk
  ),
  main_client AS (
    SELECT
      id_propose,
      id_person AS id_primary_person,
      ROW_NUMBER() OVER(PARTITION BY id_propose ORDER BY ts_updated DESC) AS rn
    FROM
      datalake_velo_clean.fiancavelo_proposeperson
    WHERE
      is_active
        AND id_type = 1 -- bringing only main IQ
  )

  SELECT DISTINCT
    cp.id AS id_person,
    pp.id_propose,
    TRIM(UPPER(cp.name)) AS name,
    cp.email,
    cp.phone,
    prs.bureau_name,
    cp.document,
    prs.score_value AS serasa_score,
    prs.risk AS risk_score,
    prs.risk_classification,
    prs.score_personal_value,
    prs.declared_income,
    prs.requested_income,
    mc.id_primary_person IS NOT NULL AS is_primary_person,
    TRUE AS is_legacy,
    cp.dt_birth
  FROM
    datalake_velo_clean.clientes_person AS cp
  LEFT JOIN
    datalake_velo_clean.fiancavelo_proposeperson AS pp
      ON pp.id_person = cp.id
  LEFT JOIN
    person_score AS prs
      ON prs.id_person =  cp.id
        AND prs.rn = 1
  LEFT JOIN
    main_client AS mc
      ON mc.id_primary_person = cp.id
      AND mc.id_propose = pp.id_propose

)
UNION ALL
(
  WITH person AS (
      SELECT *
      FROM
          datalake_person_clean.person AS p
      QUALIFY
          ROW_NUMBER() OVER (PARTITION BY p.id ORDER BY p.ts_updated DESC) = 1
  ),
  person_document AS (
      SELECT *
      FROM
          datalake_person_clean.identity_document AS i
      WHERE
          i.document_type IN ('CPF', 'RG')
          AND i.status = 'ACTIVE'
      QUALIFY
          ROW_NUMBER() OVER (PARTITION BY i.id_person ORDER BY i.document_type, i.ts_updated DESC) = 1
  ),
  person_contact AS (
      WITH contact_deduplication AS (
          SELECT *
          FROM
              datalake_person_clean.contact_info AS i
          QUALIFY
              ROW_NUMBER() OVER (PARTITION BY i.id, i.category  ORDER BY i.ts_updated DESC) = 1
      )
      SELECT
          p.id AS id_person,
          MIN(IF(c.category = 'EMAIL', c.contact_info, NULL)) AS email,
          MIN(IF(c.category = 'PHONE', c.contact_info, NULL)) AS phone
      FROM
          person AS p
      LEFT JOIN
          contact_deduplication AS c
          ON p.id = c.id_person
          AND c.category IN ('EMAIL', 'PHONE')
      GROUP BY 1
  )
  -- START NEUROTECH
  ,neurotech_clean AS (
      SELECT
          proposal_cpfs,
          proposal_number,
          proposal_rating,
          serasa_score_csba_bureau,
          ts_operation
      FROM
          datalake_velo_neurotech_clean.logs_credit_granting
      QUALIFY ROW_NUMBER() OVER(PARTITION BY proposal_number ORDER BY ts_operation DESC) = 1
  )

  ,serasa_neurotech as (
      SELECT
          CAST(proposal_number AS INT) as id_propose,
          TRANSFORM(SPLIT(serasa_score_csba_bureau, '#@#'), x -> CAST(x AS DECIMAL)) AS bureau_score_serasa_neurotech,
          proposal_cpfs AS cpf,
          proposal_rating AS risk_rating
      FROM
          neurotech_clean AS b1
      WHERE
          SUBSTR(serasa_score_csba_bureau,1,1) <> '-' -- Removing negative values
          AND b1.proposal_number <> 'NaN'
          AND b1.serasa_score_csba_bureau <> ('NaN')
  ),
  serasa_neurotech_per_person AS (
      WITH base_persons_info AS (
          SELECT
              id_propose,
              EXPLODE(ARRAYS_ZIP(cpf, bureau_score_serasa_neurotech)) AS person_info,
              risk_rating
          FROM
              serasa_neurotech
      )
      SELECT
          id_propose,
          person_info.cpf AS cpf,
          person_info.bureau_score_serasa_neurotech AS serasa_score,
          risk_rating AS risk_score,
          "Serasa" AS bureau_name
      FROM
          base_persons_info
  ),
  -- END NEUROTECH
  main_person AS (
    SELECT
        id AS id_person,
        id_propose
    FROM
        datalake_rental_guarantee_platform_clean.propose_person AS pp
    WHERE
        pp.id_propose_person_type =3 -- "Responsável Principal"
)
  SELECT
      pp.id AS id_person,
      pp.id_propose,
      pp.name,
      pc.email,
      pc.phone,
      s.bureau_name,
      pd.identification_number AS document,
      s.serasa_score,
      s.risk_score,
      NULL AS risk_classification,
      NULL AS score_personal_value,
      pp.declared_income,
      NULL AS requested_income,
      mp.id_person IS NOT NULL AS is_primary_person,
      FALSE AS is_legacy,
      p.dt_birth
  FROM
      datalake_rental_guarantee_platform_clean.propose_person AS pp
  LEFT JOIN
      person AS p
          ON pp.uuid_person = p.uuid_person
  LEFT JOIN
      person_document AS pd
          ON p.id = pd.id_person
  LEFT JOIN
      person_contact AS pc
          ON p.id = pc.id_person
  LEFT JOIN
      serasa_neurotech_per_person AS s
          ON pp.id_propose = s.id_propose
          AND REGEXP_REPLACE(pd.identification_number, '[^0-9]', '') = REGEXP_REPLACE(s.cpf, '[^0-9]', '')
  LEFT JOIN
      main_person AS mp
          ON pp.id = mp.id_person
)
ORDER BY 1
)
SELECT
  id_person,
  id_propose,
  name,
  email,
  phone,
  bureau_name,
  document,
  serasa_score,
  risk_score,
  risk_classification,
  score_personal_value,
  declared_income,
  requested_income,
  is_primary_person,
  is_legacy,
  dt_birth
FROM
    cte_union
