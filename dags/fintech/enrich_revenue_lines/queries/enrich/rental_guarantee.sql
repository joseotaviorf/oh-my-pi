WITH recent_guarantee AS (
    SELECT DISTINCT
        id AS id_guarantee,
        MAX(ts_updated) AS ts_last_updated
    FROM
        datalake_rental_guarantee_clean.guarantee
    GROUP BY 1
),
recent_guarantee_distinct AS (
    SELECT DISTINCT
        id AS id_guarantee,
        id_contract_ebdb,
        guarantee_status,
        final_value,
        ts_created
    FROM
        datalake_rental_guarantee_clean.guarantee g
    INNER JOIN
        recent_guarantee rg
          ON rg.id_guarantee = g.id
          AND g.ts_updated = rg.ts_last_updated
),
captured_charge AS (
    SELECT DISTINCT
        id_guarantee,
        MAX(ts_updated) AS ts_last_updated
    FROM 
        datalake_rental_guarantee_clean.charge
    WHERE
        charge_status = 'CAPTURED'
    GROUP BY 1
),
captured_charge_distinct AS (
    SELECT DISTINCT
        c.id_guarantee,
        c.id AS id_charge,
        installments AS total_installments,
        charge_status,
        charge_type,
        ts_updated
    FROM 
        datalake_rental_guarantee_clean.charge c
    INNER JOIN
        captured_charge cc
          ON c.id_guarantee = cc.id_guarantee
          AND c.ts_updated = cc.ts_last_updated      
),
df AS (
SELECT DISTINCT
  rg.id_guarantee,
  rg.guarantee_status,
  rc.id_charge,
  rc.total_installments,
  rc.charge_status,
  rc.charge_type,
  dc.sk_contract AS id_contract_ebdb,
  dc.type,
  dc.rent,
  dc.status,
  COALESCE(date_trunc('month', dt_start), date_trunc('month', dt_entrance)) AS dt_started,
  COALESCE(date_trunc('month', dt_annulment), date_trunc('month', current_date)) AS dt_ended,
  rg.final_value/100 AS final_value,
  ROUND(((((CAST(rg.final_value AS DECIMAL(10,4))/100)/12)/1.0738)*0.825),2) AS installment_value,
  rg.ts_created AS ts_guarantee_created
FROM 
  recent_guarantee_distinct AS rg
INNER JOIN
  captured_charge_distinct AS rc
    ON rc.id_guarantee = rg.id_guarantee
INNER JOIN
  dw_public.dim_contract dc
    ON dc.sk_contract = rg.id_contract_ebdb
WHERE 
  dc.guarantee = 'RentalGuarantee'
AND
  dc.type != 'DealOnly'
AND
  dc.status IN ('Ativo', 'Finalizado')
AND
  dc.country_code = 'BR'
)
SELECT DISTINCT
  id_guarantee,
  id_contract_ebdb,
  id_charge,
  status AS contract_status,
  guarantee_status,
  charge_status,
  charge_type,
  total_installments,
  installment_value AS monthly_revenue,
  CAST(CAST(YEAR(dd.month_start) AS STRING) || LPAD(CAST(MONTH(dd.month_start) AS STRING), 2, '0') AS INTEGER) AS accrual_year_month,
  ts_guarantee_created
FROM 
  df
INNER JOIN
  dw_public.dim_date AS dd
    ON dd.date BETWEEN dt_started AND dt_ended
WHERE
    date(dd.month_start) >= date('2022-01-01')