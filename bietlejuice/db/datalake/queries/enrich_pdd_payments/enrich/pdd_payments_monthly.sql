SELECT
  *
FROM
  datalake_pdd_payments.pdd_payments
WHERE
  {year} = year
  AND {month} = month
  AND {day} = day