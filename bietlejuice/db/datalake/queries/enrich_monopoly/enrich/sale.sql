WITH last_sale_transaction AS (
  SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY id_sale ORDER BY ts_created DESC) AS rw_sale_transaction
  FROM
      datalake_monopoly_clean.sale_transaction AS st
  WHERE
      st.event = 'income-down-payment'
      AND st.status = 'created'
)
SELECT
    s.id AS id_sale,
    s.id_external_offer,
    st.id_income_reference,
    MAX(ir.dt_income) AS dt_occurence,
    s.ts_created
FROM
    datalake_monopoly_clean.sale AS s
LEFT JOIN
    last_sale_transaction AS st
        ON st.id_sale = s.id
        AND rw_sale_transaction = 1
LEFT JOIN
    datalake_monopoly_clean.income_reference AS ir
        ON st.id_income_reference = ir.id
GROUP BY 1,2,3,5
