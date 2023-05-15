WITH zendesk_tickets_unique AS (
    --this CTE fix the error of multiple tickets openned for a single call
  SELECT
      tfm.id_call,
      MAX(tfm.id_zendesk_requester_user) AS id_respondent,
      MAX(tfm.id_ticket) AS id_ticket,
      MAX(tfm.id_contract) AS id_contract
  FROM
      datalake_zendesk_ticket_funnels.tickets_funnel_metrics AS tfm
  WHERE
      id_call IS NOT NULL
  GROUP BY 1
)
SELECT
    MD5(CONCAT(cie.id_call, MAX(cie.ts_created_local))) AS id_answer,
    tfm.id_contract,
    tfm.id_ticket,
    tfm.id_respondent,
    'customer support' AS service_type,
    'call' AS service_context,
    'bigfone' AS source_name,
    MAX(cie.csat_2) FILTER(WHERE cie.csat_2 IS NOT NULL) AS satisfaction_score,
    "satisfaction evaluation" AS score_description,
    MAX(
        CASE
            WHEN cie.csat_1 = 2 THEN 5
            ELSE cie.csat_1
        END
    ) FILTER(WHERE cie.csat_1 IS NOT NULL) AS secondary_satisfaction_score,
    "resolution survey" AS secondary_score_description,
    MIN(cie.ts_created_local) AS ts_submitted,
    cie.year,
    cie.month,
    cie.day
FROM
    datalake_bigfone_twilio.call_ivr_events AS cie
JOIN
    zendesk_tickets_unique AS tfm
        ON tfm.id_call = cie.id_call
WHERE
    COALESCE(cie.csat_1, cie.csat_2) IS NOT NULL
    AND cie.year = {year}
    AND cie.month = {month}
    AND cie.day = {day}
GROUP BY cie.id_call, 2, 3, 4, 5, 6, 7, 9, 11, 13, 14, 15