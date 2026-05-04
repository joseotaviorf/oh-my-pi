WITH docs_rejected_events AS (
  SELECT
    id_event,
    id_user,
    CAST(id_person AS STRING) AS uuid_person,
    CAST(event_properties:proposal_id AS INT) AS id_proposal,
    FROM_JSON(event_properties:party_rejection_reasons, 'ARRAY<STRING>') AS party_rejection_reasons,
    ts_event,
    event_properties
  FROM datalake_cdp_clean.transactional
  WHERE
    event_name = 'tenant_rent_documentation_analysis_result_event'
    AND ts_event >= TIMESTAMP '2026-01-01 00:00:00'
    AND CAST(event_properties:status AS STRING) = 'REJECTED'
)
SELECT
  ae.id_event,
  ae.uuid_person,
  concat_ws(', ', CAST(h.address AS STRING), CAST(h.number AS STRING)) AS address_text,
  CASE
    WHEN cardinality(ae.party_rejection_reasons) > 0 -- Not empty
      -- If after removing allowed rejection reasons the list
      -- is empty, then there was only eligible rejection reasons.
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
  END AS has_only_eligible_rejection_reasons,
  abs(crc32(encode(ae.uuid_person, 'utf-8'))) % 100 AS binning_value,
  date_format(ae.ts_event, 'yyyy-MM-dd HH:mm:ss') AS ts_event
FROM docs_rejected_events AS ae
LEFT JOIN datalake_ebdb_clean.proposal AS p
  ON ae.id_proposal = p.id
LEFT JOIN datalake_ebdb_clean.house AS h
  ON p.id_house = h.id
