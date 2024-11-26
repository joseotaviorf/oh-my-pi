WITH
contract_write_off AS (
      SELECT DISTINCT
            sk_contract AS id
      FROM
            dw_payment_snapshot.dim_invoice_snapshot  AS m
      LEFT JOIN
            datalake_retsuko.invoice AS i
                  ON i.id_external = m.sk_invoice
      LEFT JOIN
            dw_public_snapshot.dim_contract_snapshot AS c
                  ON c.sk_contract = i.id_contract_external
                  AND c.year = m.year
                  AND c.month = m.month
                  AND c.day = m.day
      WHERE m.is_write_off IS TRUE
),
BASE_INVOICES_SNAPSHOT_CLEAN AS (
      WITH BASE_INVOICES_SNAPSHOT_RAW AS (
            SELECT
                  ps.sk_invoice,
                  ps.frequency,
                  ps.payment_status,
                  ps.user,
                  IFNULL(ps.is_write_off, FALSE) AS is_write_off,
                  ps.due_amount,
                  ps.paid_amount,
                  ps.accrual_year_month,
                  ps.ts_created,
                  ps.ts_canceled,
                  ps.dt_sent,
                  ps.dt_due,
                  ps.dt_paid,
                  ps.dt_write_off,
                  ps.year,
                  ps.month,
                  ps.day,
                  ps.ts_snapshot,
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
            dpdc.sk_contract as id,
            dpdc.dt_start as dt_started,
            dpdc.dt_annulment as dt_termination,
            CAST(dpdc.ts_analyst_annulment_input AS DATE) AS annulment_input_dt,
            CASE
                  WHEN (upper(dpdc.guarantee) = 'RENTALDEPOSIT'
                        OR upper(dpdc.guarantee) = 'RENTALGUARANTEE'
                        OR upper(dpdc.guarantee) = 'DEPOSITO'
                        OR upper(dpdc.guarantee) = 'PRO_GUARANTOR'
                        OR upper(dpdc.guarantee) = 'THIRDPARTYGUARANTEE'
                        OR upper(dpdc.guarantee) = 'STANDALONE')
                        THEN TRUE
                  ELSE FALSE
            END AS guarantee_type,
            CASE
                  WHEN(dpdc.country_code<>'BR') THEN TRUE
                  ELSE FALSE
            END AS flag_is_international,
            CASE
                  WHEN(dpdc.dt_annulment IS NOT NULL AND datediff(dpdc.dt_annulment, dpdc.dt_start ) <= 0) THEN TRUE
                  ELSE FALSE
            END AS flag_is_before_started_raw,
            CASE
              WHEN upper(dpdc.guarantee) = 'SEGUROFAIRFAX' THEN 'Fairfax'
              WHEN upper(dpdc.guarantee) = 'PRO_GUARANTOR' THEN 'Pro_Guarantor'
              WHEN upper(dpdc.guarantee) = 'RENTALGUARANTEE' THEN 'Rental_Guarantee'
              WHEN upper(dpdc.guarantee) = 'RENTALDEPOSIT' or dpdc.guarantee = 'DEPOSITO' THEN 'Rental_Deposit'
              WHEN upper(dpdc.guarantee) = 'STANDALONE' THEN 'Standalone'
              WHEN upper(dpdc.guarantee) = 'THIRDPARTYGUARANTEE' THEN 'Third_Party_3D'
            ELSE 'Outros' END AS contract_guarantee,
            coalesce(date(dpdc.ts_signature), date(dpdc.dt_start)) as contract_signature_date,
            dt_annulment,
            year,
            month,
            day
      FROM
            dw_public_snapshot.dim_contract_snapshot AS dpdc
      WHERE
            dpdc.sk_contract<>-1
),
CONTRACT_AUX AS (
      SELECT
        *
      FROM
        BASE_DIM_CONTRACT_INFO
      WHERE
            year = 2022 AND month  = 10 AND day = 4
),
repair_offboarding AS (
      SELECT DISTINCT
            id_invoice,
            dt_closing
      FROM
            datalake_losses.bill_items
      WHERE bill_item_name = 'repair offboarding'
),
BASE_CLOSING_DRAFT AS (
      SELECT
            m.*,
            CASE
                  WHEN (m.ts_canceled IS NOT NULL) AND (m.ts_canceled > m.closing_day) AND (m.ts_canceled <= m.ts_snapshot) THEN TRUE
                  ELSE FALSE
            END AS flag_canceled_in_dead_time,
            CASE
                  WHEN (m.payment_status = 'written down') AND (m.dt_paid > m.closing_day) AND (m.dt_paid <= m.ts_snapshot) THEN TRUE
                  ELSE FALSE
            END AS flag_writtendown_in_dead_time,
            CASE
                  WHEN m.dt_paid = m.closing_day THEN TRUE
                  ELSE FALSE
            END AS flag_paid_in_closing_day,
            IF(cwo.id IS NOT NULL, TRUE, FALSE) AS is_contract_write_off,
            coalesce(c.flag_is_before_started_raw, c_backup.flag_is_before_started_raw) as flag_is_before_started,
            coalesce(c.id, c_backup.id) as id,
            coalesce(c.dt_started, c_backup.dt_started) as dt_started,
            coalesce(c.dt_termination, c_backup.dt_termination) as dt_termination,
            coalesce(c.annulment_input_dt, c_backup.annulment_input_dt) as annulment_input_dt,
            coalesce(c.guarantee_type, c_backup.guarantee_type) as guarantee_type,
            coalesce(c.flag_is_international, c_backup.flag_is_international) as flag_is_international,
            coalesce(c.flag_is_before_started_raw, c_backup.flag_is_before_started_raw) as flag_is_before_started_raw,
            IF(b.id_invoice IS NOT NULL, TRUE, FALSE) AS has_repair_offboarding_bill_item,
            CASE
              WHEN coalesce(c.dt_annulment, current_date) <= (date_trunc('month', m.dt_snapshot) - interval '1' day) THEN 'Finalizado'
            ELSE 'Ativo' END AS status_mes_fechamento,
            cr.city,
            c.contract_signature_date,
            c.contract_guarantee,
            c.dt_annulment
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
                  AND c.year = m.year
                  AND c.month = m.month
                  AND c.day = m.day
      LEFT JOIN
            CONTRACT_AUX AS c_backup
                  ON c_backup.id = cr.id_external
      LEFT JOIN
            repair_offboarding AS b
                  ON b.id_invoice = m.sk_invoice and b.dt_closing = m.closing_day
      LEFT JOIN
            contract_write_off AS cwo
                  ON cwo.id = coalesce(c.id, c_backup.id)
)
SELECT
      sk_invoice AS id_invoice,
      id AS id_contract,
      accrual_year_month,
      status_mes_fechamento AS closing_month_status,
      due_amount,
      frequency,
      CASE
            WHEN frequency = 'monthly' THEN 'Mensal'
            WHEN frequency = 'onboarding' THEN 'Onboarding'
            WHEN frequency = 'extra' THEN 'Extra'
            WHEN frequency = 'early termination' THEN 'Rescisão'
            WHEN frequency = 'pos rental' THEN 'Pos_rental'
            ELSE frequency
      END AS invoice_type,
      city,
      contract_guarantee,
      guarantee_type AS is_guarantee_paid,
      flag_is_before_started AS is_before_started,
      flag_is_before_started_raw AS is_before_started_raw,
      flag_canceled_in_dead_time AS is_canceled_in_dead_time,
      flag_is_international AS is_international,
      flag_paid_in_closing_day AS is_paid_in_closing_day,
      flag_writtendown_in_dead_time AS is_writtendown_in_dead_time,
      is_write_off,
      is_contract_write_off,
      has_repair_offboarding_bill_item,
      paid_amount,
      payment_status,
      COALESCE(user,'tenant') AS user,
      'SNAPSHOT' as origin_factor,
      closing_day AS dt_closing,
      contract_signature_date as dt_contract_signature,
      dt_annulment,
      dt_due,
      dt_paid,
      dt_sent,
      dt_write_off,
      dt_snapshot
FROM
      BASE_CLOSING_DRAFT
