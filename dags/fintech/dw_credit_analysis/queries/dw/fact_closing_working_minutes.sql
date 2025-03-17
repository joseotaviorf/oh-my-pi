WITH calculate_working_minutes as (
  SELECT
    rf.sk_contract,
    rf.sk_proposal,
    proposal.ts_credit_approved_last,
    contract.ts_created,
    contract.ts_signed,
 -- generic date 1900-01-01 is being used as a workaround for null dates error. Businesstimedelta cant handle null dates.
    CAST(
      FINTECHOPS_WORK_MIN_SLA(
        coalesce(proposal.ts_credit_approved_last, TIMESTAMP '1900-01-01'),
        coalesce(contract.ts_created, TIMESTAMP '1900-01-01')
      ) AS FLOAT
    ) AS ca2cc_working_minutes,
    CAST(
      FINTECHOPS_WORK_MIN_SLA(
        coalesce(proposal.ts_credit_approved_last, TIMESTAMP '1900-01-01'),
        coalesce(contract.ts_signed, TIMESTAMP '1900-01-01')
      ) AS FLOAT
    ) ca2cs_working_minutes,
    CAST(
      FINTECHOPS_WORK_MIN_SLA(
        coalesce(contract.ts_created, TIMESTAMP '1900-01-01'),
        coalesce(contract.ts_signed, TIMESTAMP '1900-01-01')
      ) AS FLOAT
    ) cc2cs_working_minutes
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
)
SELECT
  sk_contract,
  sk_proposal,
  ca2cc_working_minutes AS working_min_credit_approved_to_contract_created,
  IF(
    ts_signed IS NULL, NULL, ca2cs_working_minutes
  ) AS working_min_credit_approved_to_contract_signed,
  IF(
    ts_signed IS NULL, NULL, cc2cs_working_minutes
  ) AS working_min_contract_created_to_contract_signed,
  ts_credit_approved_last AS ts_credit_analysis_approved,
  ts_created AS ts_contract_created,
  ts_signed AS ts_contract_signed,
  NOW() AS ts_load
FROM
  calculate_working_minutes
