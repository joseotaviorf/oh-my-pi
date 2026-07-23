WITH mova_recurrence_signed AS (
  SELECT DISTINCT
    sk_contract AS id_contract,
    sk_base_proposal AS id_base_proposal,
    DATE(ts_created_at) AS dt_created,
    DENSE_RANK() OVER(PARTITION BY sk_contract ORDER BY ts_created_at) AS nbr_transactions_signed
  FROM
    datalake_gsheets_clean.mova_lra_owners
  WHERE
    dt_signed_contract IS NOT NULL
),
fastforward_recurrence_signed AS (
  SELECT
    id_contract,
    id,
    ts_created,
    ROW_NUMBER() OVER(PARTITION BY id_contract ORDER BY ts_created) AS nbr_transactions_signed
  FROM
    datalake_fastforward_clean.long_term_anticipation
  WHERE
    ts_signed IS NOT NULL
),
fastforward AS (
  SELECT
    lra.id AS id_lra,
    c.id_external AS id_contract_ebdb,
    lra.total_rent,
    lio.installments AS total_installments,
    li.installment_number as installment,
    frs.nbr_transactions_signed,
    lio.months_anticipated,
    COALESCE((li.amount + li.interest_value),lra.installment_value) AS prod_theorical_amount,
    li.interest_value AS prod_theorical_fee
  FROM
    datalake_fastforward_clean.long_term_anticipation AS lra
  INNER JOIN
      datalake_fastforward_clean.contract AS c
        ON lra.id_contract = c.id
  INNER JOIN
      datalake_fastforward_clean.lra_installment_option AS lio
        ON lra.id_installment_option = lio.id
  INNER JOIN
      datalake_fastforward_clean.lra_installment AS li
        ON lra.id = li.id_long_term_anticipation
  INNER JOIN
      fastforward_recurrence_signed AS frs
        ON lra.id = frs.id
)

SELECT
  lra.id_lra,
  mova.sk_contract AS id_contract_ebdb,
  mova.installment_status AS status,
  lra.months_anticipated,
  mova.installment_number AS installment,
  mova.installment_total_count AS total_installments,
  mova.main_value AS total_rent,
  mrs.nbr_transactions_signed,
  lra.prod_theorical_amount,
  lra.prod_theorical_fee,
  mova.installment_value AS mova_invoice_theorical_amount,
  mova.paid_value AS mova_invoice_paid_amount,
  mova.contract_installment_interest AS mova_invoice_theorical_fee,
  IF(installment_status = 'PAGA', mova.contract_installment_interest, NULL) AS mova_invoice_paid_fee,
  mova.interest_value AS mova_interest_value,
  DATE_FORMAT(ADD_MONTHS(DATE_TRUNC('month', mova.dt_expiration), -1), 'yyyyMM') AS accrual_year_month,
  mova.dt_expiration AS dt_due,
  mova.dt_payment AS dt_paid,
  DATE(mova.ts_created_at) AS dt_created,
  mova.dt_signed_contract AS dt_signed
FROM
  datalake_gsheets_clean.mova_lra_owners AS mova
LEFT JOIN
  mova_recurrence_signed AS mrs
    ON mova.sk_contract = mrs.id_contract
    AND mova.sk_base_proposal = mrs.id_base_proposal
LEFT JOIN
  fastforward AS lra
    ON mova.sk_contract = lra.id_contract_ebdb
    AND mova.main_value = lra.total_rent
    AND mova.installment_total_count = lra.total_installments
    AND mova.installment_number = lra.installment
    AND mrs.nbr_transactions_signed = lra.nbr_transactions_signed
LEFT JOIN
  datalake_fastforward_clean.gateway_loan_installment bfi
    ON mova.sk_installment = CAST(bfi.id_partner_reference AS BIGINT)
WHERE
  bfi.id IS NULL --excluding bfi data
  AND mova.installment_status <> 'RENEGOCIADA'
