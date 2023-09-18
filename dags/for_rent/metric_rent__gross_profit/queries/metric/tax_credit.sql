SELECT
  DATE_FORMAT(dt_reference, 'yyyyMM') AS accrual_year_month,
  SUM(debit_credit) AS tax_credit
FROM
  datalake_pas.ledger
WHERE
  account_number IN (
    '41101.04.09',
    '41101.05.11',
    '41101.06.18',
    '41101.07.22',
    '41101.09.19',
    '41101.12.05',
    '41101.16.03',
    '41101.16.06',
    '41101.17.02',
    '41101.18.02',
    '41101.23.12',
    '41101.24.12',
    '51101.05.04',
    '51101.07.03',
    '51101.09.02'
  )
  AND cost_center_code REGEXP '^R.*'
  AND DATE_FORMAT(dt_reference, 'yyyyMM') >= 202301
GROUP BY 1