SELECT
  cost_center_code,
  SUM(debit_credit) AS gross_sales_tax,
  DATE_FORMAT(dt_reference, 'yyyyMM') AS accrual_year_month
FROM
  datalake_pas.ledger
WHERE
  account_number in (
    '31201.01.01',
    '31201.01.02',
    '31201.01.03',
    '31201.01.04',
    '31201.01.05',
    '31201.01.06',
    '31201.01.08',
    '31201.01.09',
    '31201.01.12',
    '31201.01.13',
    '31201.01.14',
    '31201.01.15',
    '31201.01.18',
    '31201.01.19',
    '31201.01.20',
    '31201.01.21',
    '31201.01.22',
    '31202.01.01',
    '31202.01.02',
    '41102.02.20',
    '41102.02.21'
  )
  AND cost_center_code REGEXP '^R.*'
  AND DATE_FORMAT(dt_reference, 'yyyyMM') >= 202301
GROUP BY 1, 3