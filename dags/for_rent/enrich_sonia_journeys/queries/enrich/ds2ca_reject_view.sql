WITH docs_rejected_events AS (
  SELECT
    id_event,
    id_user,
    id_person AS uuid_person,
    CAST(JSON_EXTRACT_SCALAR(JSON_PARSE(event_properties), '$.proposal_id') AS INT) AS id_proposal,
    CAST(JSON_EXTRACT(JSON_PARSE(event_properties), '$.party_rejection_reasons') AS ARRAY(VARCHAR)) AS party_rejection_reasons,
    JSON_EXTRACT_SCALAR(JSON_PARSE(event_properties), '$.status') AS analysis_status,
    ts_event,
    event_properties
  FROM datalake_cdp_clean.transactional
  WHERE
    event_name = 'tenant_rent_documentation_analysis_result_event'
    AND application = 'sorting_hat'
    AND journey_step = 'documentation'
    AND (
        YEAR > YEAR(CURRENT_DATE - INTERVAL '1' DAY)
        OR (
          YEAR = YEAR(CURRENT_DATE - INTERVAL '1' DAY)
          AND MONTH > MONTH(CURRENT_DATE - INTERVAL '1' DAY)
        )
        OR (
          YEAR = YEAR(CURRENT_DATE - INTERVAL '1' DAY)
          AND MONTH = MONTH(CURRENT_DATE - INTERVAL '1' DAY)
          AND DAY >= DAY(CURRENT_DATE - INTERVAL '1' DAY)
        )
      )
    AND ts_event >= CURRENT_TIMESTAMP - INTERVAL '1' DAY
)
SELECT
  CONCAT(ae.id_event, '-', ae.uuid_person) AS pk_event_user,
  ae.id_event,
  p.id_house,
  ae.id_user,
  ae.uuid_person,
  SPLIT(TRIM(u.name), ' ')[1] AS user_first_name,
  REPLACE(u.main_phone, '+', '') AS user_phone,
  u.email AS user_email,
  DATE_FORMAT(ae.ts_event,  '%Y-%m-%d %T') AS ts_event,
  ABS(CRC32(TO_UTF8(ae.uuid_person))) % 100 AS binning_value,
  CONCAT_WS(', ', h.address, h.number) AS address_text,
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
WHERE ae.analysis_status = 'REJECTED'
  