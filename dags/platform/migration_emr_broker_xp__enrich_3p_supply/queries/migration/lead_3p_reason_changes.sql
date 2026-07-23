WITH exploded_reasons AS (
  SELECT
    id,
    id_file,
    'SALE' AS business_context,
    EXPLODE(FROM_JSON(status_reason, 'map<string, string>')) AS (reason, value),
    TO_UTC_TIMESTAMP(ts_updated, 'America/Sao_Paulo') AS ts_reason_started
  FROM
    datalake_brokers_supply_processor_clean.lead_3p_aud
  WHERE
    mod_status_reason
  UNION ALL
  SELECT
    bcd.id_lead AS id,
    bcd.id_file,
    bcd.business_context,
    EXPLODE(FROM_JSON(bcda.status_reason, 'map<string, string>')) AS (reason, value),
    TO_UTC_TIMESTAMP(bcda.ts_updated, 'America/Sao_Paulo') AS ts_reason_started
  FROM
    datalake_brokers_supply_processor_clean.business_context_detail_aud AS bcda
  INNER JOIN
    datalake_brokers_supply_processor_clean.business_context_detail AS bcd
      ON bcda.id = bcd.id
  WHERE
    mod_status_reason
),
previous_value_aux AS (
  SELECT
    er.id,
    er.id_file,
    er.business_context,
    er.reason,
    er.value,
    er.ts_reason_started,
    LAG(er.value) OVER (
      PARTITION BY er.id, er.business_context, er.reason ORDER BY er.ts_reason_started
    ) AS previous_value
  FROM
    exploded_reasons AS er
),
reason_ended_aux AS (
  SELECT
    pva.id,
    pva.id_file,
    pva.business_context,
    pva.reason,
    pva.value,
    pva.ts_reason_started,
    sr.reason_type,
    sr.reason_type = 'INELIGIBLE_REASON' AS is_ineligible_reason,
    sr.reason_type = 'DISCARD_REASON' AS is_discard_reason,
    sr.reason_type = 'ENRICHMENT_REASON' AS is_enrichment_reason,
    LEAD(pva.ts_reason_started) OVER (
      PARTITION BY pva.id, pva.business_context, pva.reason ORDER BY pva.ts_reason_started
    ) AS ts_reason_ended
  FROM
    previous_value_aux AS pva
  INNER JOIN
    datalake_gsheets_clean.supply_processor_status_reasons AS sr
      ON pva.reason = sr.reason_name
  WHERE
    pva.previous_value IS DISTINCT FROM pva.value
),
forced_end_aux AS (
  SELECT
    rea.id AS id_lead_3p,
    rea.id_file,
    rea.business_context,
    rea.reason,
    rea.reason_type,
    sc.status AS status_when_reason_started,
    sc.growth_status AS growth_status_when_reason_started,
    COALESCE(sc_end.status, ll.status) AS status_when_reason_ended,
    COALESCE(sc_end.growth_status, ll.growth_status) AS growth_status_when_reason_ended,
    DATEDIFF(COALESCE(rea.ts_reason_ended, ll.ts_start), rea.ts_reason_started) AS days_in_reason,
    -- The last left join with lead_3p_status_changes can bring more than one result.
    -- We only want the most recent one.
    ROW_NUMBER() OVER (
      PARTITION BY rea.id, rea.business_context, rea.reason, rea.ts_reason_started
      ORDER BY ll.ts_start NULLS LAST
    ) AS rn,
    sc.is_waiting_for_enrichment AS is_waiting_for_enrichment_when_reason_started,
    sc.is_ineligible AS is_ineligible_when_reason_started,
    sc.is_discarded AS is_discarded_when_reason_started,
    COALESCE(sc_end.is_waiting_for_enrichment, ll.is_waiting_for_enrichment) AS is_waiting_for_enrichment_when_reason_ended,
    COALESCE(sc_end.is_ineligible, ll.is_ineligible) AS is_ineligible_when_reason_ended,
    COALESCE(sc_end.is_discarded, ll.is_discarded) AS is_discarded_when_reason_ended,
    rea.ts_reason_ended IS NOT NULL AS is_requirement_met,
    rea.is_ineligible_reason,
    rea.is_discard_reason,
    rea.is_enrichment_reason,
    rea.ts_reason_started,
    COALESCE(rea.ts_reason_ended, ll.ts_start) AS ts_reason_ended
  FROM
    reason_ended_aux AS rea
  LEFT JOIN
    datalake_3p_supply.lead_3p_status_changes AS sc
      ON rea.id = sc.id_lead_3p
      AND rea.business_context = sc.business_context
      AND rea.ts_reason_started >= sc.ts_start
      AND rea.ts_reason_started < COALESCE(sc.ts_end, CURRENT_TIMESTAMP())
  LEFT JOIN
    datalake_3p_supply.lead_3p_status_changes AS sc_end
      ON rea.id = sc_end.id_lead_3p
      AND rea.business_context = sc_end.business_context
      AND rea.ts_reason_ended >= sc_end.ts_start
      AND rea.ts_reason_ended < COALESCE(sc_end.ts_end, CURRENT_TIMESTAMP())
  LEFT JOIN
    datalake_3p_supply.lead_3p_status_changes AS ll -- finds the next time when the lead was discarded or not eligible
      ON rea.is_enrichment_reason
      AND rea.business_context = ll.business_context
      AND rea.ts_reason_ended IS NULL
      AND rea.id = ll.id_lead_3p
      AND rea.ts_reason_started <= ll.ts_start
      AND (ll.is_discarded OR ll.is_ineligible)
  WHERE
    rea.value = 'true'
)
SELECT
  id_lead_3p,
  id_file,
  business_context,
  reason,
  reason_type,
  status_when_reason_started,
  growth_status_when_reason_started,
  status_when_reason_ended,
  growth_status_when_reason_ended,
  days_in_reason,
  TRUE AS has_3p_access_control,
  is_ineligible_reason,
  is_discard_reason,
  is_enrichment_reason,
  is_waiting_for_enrichment_when_reason_started,
  is_ineligible_when_reason_started,
  is_discarded_when_reason_started,
  is_waiting_for_enrichment_when_reason_ended,
  is_ineligible_when_reason_ended,
  is_discarded_when_reason_ended,
  is_requirement_met,
  ts_reason_started,
  ts_reason_ended,
  CURRENT_TIMESTAMP() AS ts_load,
  YEAR(ts_reason_started) AS year,
  MONTH(ts_reason_started) AS month,
  DAY(ts_reason_started) AS day
FROM
  forced_end_aux
WHERE
  rn = 1
