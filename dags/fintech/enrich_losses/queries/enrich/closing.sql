WITH BASE_INVOICES_SNAPSHOT_CLEAN AS (
      WITH BASE_INVOICES_SNAPSHOT_RAW AS (    
            SELECT
                  ps.*, 
                  dt.month_end AS closing_day,
                  CAST(ps.ts_snapshot AS DATE) AS dt_snapshot
            FROM 
                  dw_payment_snapshot.dim_invoice_snapshot AS ps
            LEFT JOIN
                  dw_public.dim_date dt 
                        ON (dt.sk_date = CAST(DATE_FORMAT(DATEADD(MONTH,-1,ps.ts_snapshot), "yyyyMMdd") AS BIGINT))
            WHERE 
                  TRUE
                  AND ps.due_amount <=0
                  AND ((ps.year = 2022 AND ps.month > 7) OR ps.year > 2022)
      )
      SELECT 
            * 
      FROM 
            BASE_INVOICES_SNAPSHOT_RAW
      WHERE 
            TRUE 
            AND CAST(ts_created AS DATE) <= closing_day 
            AND payment_status NOT IN ('not payable')
            AND (dt_paid >= closing_day OR dt_paid IS NULL)
),
BASE_DIM_CONTRACT_INFO AS (
      SELECT 
            DISTINCT
            dpdc.id,
            dpdc.dt_started,
            dpdc.dt_termination,
            CAST(dpdc.ts_analyst_annulment_input AS DATE) AS annulment_input_dt,
            CASE 
                  WHEN (upper(dpdc.guarantee_type) = 'RENTALDEPOSIT' 
                        OR upper(dpdc.guarantee_type) = 'RENTALGUARANTEE' 
                        OR upper(dpdc.guarantee_type) = 'DEPOSITO' 
                        OR upper(dpdc.guarantee_type) = 'PRO_GUARANTOR' 
                        OR upper(dpdc.guarantee_type) = 'THIRDPARTYGUARANTEE' 
                        OR upper(dpdc.guarantee_type) = 'STANDALONE') 
                        THEN TRUE
                  ELSE FALSE 
            END AS guarantee_type,
            CASE 
                  WHEN(dpdc.country_code<>'BR') THEN TRUE
                  ELSE FALSE
            END AS flag_is_international,
            CASE 
                  WHEN(dpdc.dt_termination IS NOT NULL AND dpdc.dt_termination <= dpdc.dt_started) THEN TRUE
                  ELSE FALSE
            END AS flag_is_before_started_raw
      FROM 
            datalake_ebdb_contract.contract AS dpdc
      WHERE 
            dpdc.id<>-1
),
BASE_CLOSING_DRAFT AS (
      SELECT 
            m.*,
            CASE 
                  WHEN (m.ts_canceled IS NOT NULL) AND (m.ts_canceled > closing_day) AND (m.ts_canceled <= ts_snapshot) THEN TRUE
                  ELSE FALSE 
            END AS flag_canceled_in_dead_time,
            CASE 
                  WHEN (payment_status = 'written down') AND (m.dt_paid > closing_day) AND (m.dt_paid <= ts_snapshot ) THEN TRUE
                  ELSE FALSE 
            END AS flag_writtendown_in_dead_time,
            CASE 
                  WHEN m.dt_paid = closing_day THEN TRUE 
                  ELSE FALSE
            END AS flag_paid_in_closing_day,
            CASE 
                  WHEN flag_is_before_started_raw IS TRUE AND annulment_input_dt > ts_snapshot THEN FALSE
                  ELSE flag_is_before_started_raw 
            END AS flag_is_before_started,
            c.*
      FROM 
            BASE_INVOICES_SNAPSHOT_CLEAN AS m
      LEFT JOIN 
            datalake_retsuko.invoice AS i 
                  ON id_external = m.sk_invoice
      LEFT JOIN 
            datalake_retsuko_clean.contract AS cr 
                  ON cr.id = i.id_contract
      LEFT JOIN 
            BASE_DIM_CONTRACT_INFO AS c 
                  ON c.id = cr.id_external
)
SELECT 
      sk_invoice as id_invoice,
      id as id_contract,
      accrual_year_month,
      due_amount, 
      frequency, 
      guarantee_type as is_guarantee_paid,
      flag_is_before_started as is_before_started,
      flag_is_before_started_raw as is_before_started_raw,
      flag_canceled_in_dead_time as is_canceled_in_dead_time,
      flag_is_international as is_international,
      flag_paid_in_closing_day as is_paid_in_closing_day,
      flag_writtendown_in_dead_time as is_writtendown_in_dead_time,
      payment_status, 
      user,
      closing_day as dt_closing,
      dt_due, 
      dt_paid, 
      dt_snapshot
FROM 
      BASE_CLOSING_DRAFT