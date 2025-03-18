WITH get_contract_events as (
  SELECT
    rf.sk_contract,
    rf.sk_proposal,
    rf.sk_credit_analysis_approved_date,
    proposal.ts_credit_approved_last AS ts_credit_analysis_approved,
    contract.ts_created AS ts_contract_created,
    contract.ts_signed AS ts_contract_signed,
    IF(contract.ts_signed IS NULL, FALSE, TRUE) AS is_contract_signed,
    hour(proposal.ts_credit_approved_last) AS hour_credit_analysis_approved,
    hour(contract.ts_created) AS hour_contract_created,
    hour(contract.ts_signed) AS hour_contract_signed,
    dayofweek(proposal.ts_credit_approved_last) AS dayofweek_credit_analysis_approved,
    dayofweek(contract.ts_created) AS dayofweek_contract_created,
    dayofweek(contract.ts_signed) AS dayofweek_contract_signed
  FROM
    dw_rent.fact_listing_rent_flows AS rf
      LEFT JOIN datalake_ebdb_contract.contract AS contract
        ON contract.id = rf.sk_contract
        AND contract.id_house = CAST(rf.sk_house_listing / 1000 AS INTEGER)
      LEFT JOIN datalake_proposal.proposal AS proposal
        ON proposal.id = rf.sk_proposal
  WHERE
    rf.sk_proposal > 0
    AND rf.sk_contract > 0
    AND proposal.ts_credit_approved_last IS NOT NULL
    AND contract.ts_created IS NOT NULL
),
get_dim_date AS (
  SELECT
    ce.sk_contract,
    ce.sk_proposal,
    ce.ts_credit_analysis_approved,
    ce.ts_contract_created,
    ce.ts_contract_signed,
    ce.is_contract_signed,
    ce.hour_credit_analysis_approved,
    ce.hour_contract_created,
    ce.hour_contract_signed,
    dd.is_brz_fintech_business_day,
    ce.dayofweek_credit_analysis_approved,
    CASE
      WHEN
        (dd.is_brz_fintech_business_day = FALSE) OR
        (ce.dayofweek_credit_analysis_approved = 7 AND ce.hour_credit_analysis_approved > 20)
      THEN make_timestamp(year(dd.next_brz_fintech_business_day), month(dd.next_brz_fintech_business_day), day(dd.next_brz_fintech_business_day), 7, 0, 0)
      ELSE NULL
    END AS ts_next_brz_fintech_business_day,
    CASE
      WHEN
        (ce.dayofweek_credit_analysis_approved = 6 AND ce.hour_credit_analysis_approved > 21)
      THEN make_timestamp(year(date_add(dd.last_day, 2)), month(date_add(dd.last_day, 2)), day(date_add(dd.last_day, 2)), 8, 0, 0)
      WHEN
        (ce.dayofweek_credit_analysis_approved = 7 AND ce.hour_credit_analysis_approved < 8)
      THEN make_timestamp(year(dd.date), month(dd.date), day(dd.date), 8, 0, 0)
      ELSE NULL
    END AS ts_next_saturday_start_shift,
    CASE
      WHEN
        (dd.is_brz_fintech_business_day = TRUE AND ce.dayofweek_credit_analysis_approved != 6) AND
        (ce.hour_credit_analysis_approved > 21)
      THEN make_timestamp(year(dd.next_brz_fintech_business_day), month(dd.next_brz_fintech_business_day), day(dd.next_brz_fintech_business_day), 7, 0, 0)
      ELSE NULL
    END AS ts_next_business_day_start_shift,
    CASE
      WHEN (ce.dayofweek_credit_analysis_approved = 7 AND ce.hour_credit_analysis_approved < 20)
      THEN make_timestamp(year(dd.date), month(dd.date), day(dd.date), 20, 0, 0)
    END AS ts_saturday_end_shift,
    CASE
      WHEN (ce.dayofweek_credit_analysis_approved = 6 AND ce.hour_credit_analysis_approved > 21)
      THEN make_timestamp(year(date_add(dd.last_day, 2)), month(date_add(dd.last_day, 2)), day(date_add(dd.last_day, 2)), 20, 0, 0)
    END AS ts_saturday_end_shift_adjusted,
    CASE
      WHEN dd.is_brz_fintech_business_day = TRUE
      THEN make_timestamp(year(dd.date), month(dd.date), day(dd.date), 21, 0, 0)
    END AS ts_businessday_end_shift,
    CASE
      WHEN
        (
        dd.is_brz_fintech_business_day = FALSE AND
        (ce.dayofweek_credit_analysis_approved = 7 AND (ce.hour_credit_analysis_approved > 20 OR ce.hour_credit_analysis_approved < 8))
        )
        OR
        (
        dd.is_brz_fintech_business_day = FALSE AND
        (ce.dayofweek_credit_analysis_approved BETWEEN 2 AND 6 AND( ce.hour_credit_analysis_approved > 21 OR ce.hour_credit_analysis_approved < 7))
        )
      THEN TRUE
      ELSE FALSE
    END AS is_outside_credit_desk_shift
  FROM
    get_contract_events AS ce
  LEFT JOIN dw_public.dim_date AS dd
    ON dd.sk_date = ce.sk_credit_analysis_approved_date
),
calculate_working_minutes AS (
  SELECT
    sk_contract,
    sk_proposal,
    ts_credit_analysis_approved,
    ts_contract_created,
    ts_contract_signed,
    is_outside_credit_desk_shift,
    is_contract_signed,
    CASE
      WHEN
        is_outside_credit_desk_shift = FALSE
      THEN timestampdiff(MINUTE, ts_credit_analysis_approved, ts_contract_created)
      WHEN is_outside_credit_desk_shift = TRUE THEN 0
      WHEN
        is_outside_credit_desk_shift = TRUE
        AND ts_next_saturday_start_shift IS NOT NULL
        AND (ts_contract_created <= ts_saturday_end_shift OR ts_contract_created <= ts_saturday_end_shift_adjusted)
      THEN timestampdiff(MINUTE, ts_next_saturday_start_shift, ts_contract_created)
      END AS working_min_credit_approved_to_contract_created,
    CASE
      WHEN
        is_outside_credit_desk_shift = FALSE
        AND ts_contract_signed IS NOT NULL
        THEN timestampdiff(MINUTE, ts_credit_analysis_approved, ts_contract_signed)
      WHEN is_outside_credit_desk_shift = TRUE THEN 0
      WHEN
        is_outside_credit_desk_shift = TRUE
        AND ts_next_saturday_start_shift IS NOT NULL
        AND (ts_contract_signed <= ts_saturday_end_shift OR ts_contract_signed <= ts_saturday_end_shift_adjusted)
      THEN timestampdiff(MINUTE, ts_next_saturday_start_shift, ts_contract_signed)
      WHEN
        is_outside_credit_desk_shift = TRUE
        AND ts_next_saturday_start_shift IS NOT NULL
        AND (ts_contract_signed <= ts_saturday_end_shift OR ts_contract_signed <= ts_saturday_end_shift_adjusted)
      THEN timestampdiff(MINUTE, ts_next_saturday_start_shift, ts_contract_signed)
      END AS working_min_credit_approved_to_contract_signed,
    CASE
      WHEN
        is_outside_credit_desk_shift = FALSE
        AND ts_contract_signed IS NOT NULL
        THEN timestampdiff(MINUTE, ts_contract_created, ts_contract_signed)
      WHEN is_outside_credit_desk_shift = TRUE THEN 0
      END AS working_min_contract_created_to_contract_signed
  FROM
    get_dim_date
)
SELECT
  sk_contract,
  sk_proposal,
  working_min_credit_approved_to_contract_created,
  working_min_credit_approved_to_contract_signed,
  working_min_contract_created_to_contract_signed,
  is_contract_signed,
  ts_credit_analysis_approved,
  ts_contract_created,
  ts_contract_signed,
  NOW() AS ts_load
FROM
  calculate_working_minutes
