WITH person AS (
  SELECT
    *,
    rn
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY p.uuid_person ORDER BY p.ts_updated DESC) AS rn,
      ROW_NUMBER() OVER (PARTITION BY p.id ORDER BY p.ts_updated DESC) AS _w
    FROM datalake_person_clean.person AS p
  ) AS _t
  WHERE
    _w = 1
), person_document AS (
  SELECT
    *
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY i.id_person ORDER BY i.document_type, i.ts_updated DESC) AS _w
    FROM datalake_person_clean.identity_document AS i
    WHERE
      i.document_type IN ('CPF', 'RG') AND i.status = 'ACTIVE'
  ) AS _t
  WHERE
    _w = 1
), contact_deduplication AS (
  SELECT
    *
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY i.id, i.category ORDER BY i.ts_updated DESC) AS _w
    FROM datalake_person_clean.contact_info AS i
  ) AS _t
  WHERE
    _w = 1
), person_contact AS (
  SELECT
    p.id AS id_person,
    MIN(IF(c.category = 'EMAIL', c.contact_info, NULL)) AS email,
    MIN(IF(c.category = 'PHONE', c.contact_info, NULL)) AS phone
  FROM person AS p
  LEFT JOIN contact_deduplication AS c
    ON p.id = c.id_person AND c.category IN ('EMAIL', 'PHONE')
  GROUP BY
    1
), neurotech_clean /* START NEUROTECH */ AS (
  SELECT
    proposal_cpfs,
    proposal_number,
    proposal_rating,
    serasa_score_csba_bureau,
    ts_operation
  FROM (
    SELECT
      proposal_cpfs,
      proposal_number,
      proposal_rating,
      serasa_score_csba_bureau,
      ts_operation,
      ROW_NUMBER() OVER (PARTITION BY CAST(proposal_number AS INT) ORDER BY ts_operation DESC) AS _w
    FROM datalake_velo_neurotech_clean.logs_credit_granting
  ) AS _t
  WHERE
    _w = 1
), serasa_neurotech AS (
  SELECT
    CAST(proposal_number AS INT) AS id_propose,
    serasa_score_csba_bureau AS bureau_score_serasa_neurotech,
    proposal_cpfs AS cpf,
    proposal_rating AS risk_rating
  FROM neurotech_clean AS b1
  WHERE
    serasa_score_csba_bureau[0] > 0 /* Removing negative values */
    AND NOT b1.proposal_number IS NULL
), base_persons_info AS (
  SELECT
    id_propose,
    EXPLODE(ARRAYS_ZIP(cpf, bureau_score_serasa_neurotech)) AS person_info,
    risk_rating
  FROM serasa_neurotech
), serasa_neurotech_per_person AS (
  SELECT
    id_propose,
    person_info.cpf AS cpf,
    person_info.bureau_score_serasa_neurotech AS serasa_score,
    risk_rating AS risk_score,
    'Serasa' AS bureau_name
  FROM base_persons_info
), main_person /* END NEUROTECH */ AS (
  SELECT
    id AS id_person,
    id_propose
  FROM datalake_rental_guarantee_platform_clean.propose_person AS pp
  WHERE
    pp.id_propose_person_type = 3 /* "Responsável Principal" */
)
SELECT DISTINCT
  pp.id AS id_person,
  pp.id_propose,
  TRIM(UPPER(pp.name)) AS name,
  pc.email,
  pc.phone,
  s.bureau_name,
  REPLACE(REPLACE(pd.identification_number, '.', ''), '-', '') AS document,
  s.serasa_score,
  s.risk_score,
  CAST(NULL AS BIGINT) AS risk_classification,
  CAST(NULL AS BIGINT) AS score_personal_value,
  pp.declared_income,
  CAST(NULL AS BIGINT) AS requested_income,
  NOT mp.id_person IS NULL AS is_primary_person,
  FALSE AS is_legacy,
  p.dt_birth
FROM datalake_rental_guarantee_platform_clean.propose_person AS pp
LEFT JOIN person AS p
  ON pp.uuid_person = p.uuid_person AND p.rn = 1
LEFT JOIN person_document AS pd
  ON p.id = pd.id_person
LEFT JOIN person_contact AS pc
  ON p.id = pc.id_person
LEFT JOIN serasa_neurotech_per_person AS s
  ON pp.id_propose = s.id_propose
  AND REGEXP_REPLACE(pd.identification_number, '[^0-9]', '') = REGEXP_REPLACE(s.cpf, '[^0-9]', '')
LEFT JOIN main_person AS mp
  ON pp.id = mp.id_person
