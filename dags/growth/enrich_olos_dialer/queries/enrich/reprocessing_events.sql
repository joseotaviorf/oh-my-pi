SELECT
  olc.id_lead,
  EXPLODE (
    CASE
      WHEN REGEXP_LIKE(SF_NORMALIZE_STRING(olc.olos_disposition), 'rent') THEN ARRAY('RENT')
      WHEN REGEXP_LIKE(SF_NORMALIZE_STRING(olc.olos_disposition), 'sale') THEN ARRAY('SALE')
      WHEN REGEXP_LIKE(SF_NORMALIZE_STRING(olc.olos_disposition), 'hibrida') THEN ARRAY('RENT', 'SALE')
      ELSE ARRAY('RENT', 'SALE')
    END
  ) AS business_context,
  u.id AS id_user_registrant,
  olc.ts_call_ended AS ts_event,
  NOW() AS ts_load,
  olc.year,
  olc.month,
  olc.day
FROM
  datalake_olos_dialer.outbound_contact_attempts AS olc
LEFT JOIN datalake_ebdb_clean.user AS u
  ON (LOWER(olc.agent_email) = u.email)
WHERE
  LOWER(olos_disposition) LIKE 'opportunity%'
  AND olc.id_lead IS NOT NULL
  AND DATE(olc.ts_call_ended) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')