WITH docs_rejected_events AS (
  SELECT
    id_event,
    id_user,
    CAST(id_person AS VARCHAR) AS uuid_person,
    CAST(json_extract_scalar(json_parse(event_properties), '$.proposal_id') AS INT) AS id_proposal,
    CAST(json_extract(json_parse(event_properties), '$.party_rejection_reasons') AS ARRAY(VARCHAR)) AS party_rejection_reasons,
    ts_event,
    event_properties
  FROM datalake_cdp_clean.transactional
  WHERE
    event_name = 'tenant_rent_documentation_analysis_result_event'
    AND ts_event >= TIMESTAMP '2026-05-26 12:00:00'
    AND json_extract_scalar(json_parse(event_properties), '$.status') = 'REJECTED'
)
SELECT
  CAST(ae.id_event AS VARCHAR) || '-' || ae.uuid_person AS pk_event_user,
  ae.id_event,
  p.id_house,
  ae.id_user,
  ae.uuid_person,
  split(trim(u.name), ' ')[1] AS user_first_name,
  replace(u.main_phone, '+', '') AS user_phone,
  u.email AS user_email,
  date_format(ae.ts_event, '%Y-%m-%d %H:%i:%s') AS ts_event,
  abs(crc32(to_utf8(ae.uuid_person))) % 100 AS binning_value,
  concat_ws(', ', CAST(h.address AS VARCHAR), CAST(h.number AS VARCHAR)) AS address_text,
  CASE
    WHEN cardinality(ae.party_rejection_reasons) > 0 
      AND cardinality(
        filter(
          ae.party_rejection_reasons,
          x -> x NOT IN (
            'REJECT_INCOMPLETE_DOC',
            'PENDING_INVOICES_FROM_OTHER_CONTRACTS',
            'NOT_SAME_PERSON_FROM_IDENTITY_DOC',
            'INCOME_FLUCTUATION',
            'NUMBER_OF_ACTIVE_CONTRACTS_ABOVE_LIMIT',
            'NOT_ENOUGH_TOTAL_VERIFIED_INCOME',
            'NOT_ENOUGH_INCOME'
          )
        )
      ) = 0
      THEN 1
    ELSE 0
  END AS has_only_eligible_rejection_reasons  
FROM docs_rejected_events AS ae
LEFT JOIN datalake_ebdb_clean.proposal AS p
  ON ae.id_proposal = p.id
LEFT JOIN datalake_ebdb_clean.house AS h
  ON p.id_house = h.id
LEFT JOIN datalake_ebdb_clean.user AS u
  ON ae.uuid_person = u.uuid_person
  