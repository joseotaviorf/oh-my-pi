WITH base AS (
     SELECT DISTINCT
            c0.manual_bank_reconciliation,
            CASE CAST(c0.payment_status AS INT)
                WHEN 1 THEN 'Pago'
                WHEN 0 THEN 'Em aberto'
                ELSE -1
            END AS payment_status,
            COALESCE(
                hd.work_day,
                CASE WEEKDAY(c0.dt_installment_credit)
                    WHEN 6 THEN c0.dt_installment_credit + 2
                    WHEN 7 THEN c0.dt_installment_credit + 1
                    ELSE c0.dt_installment_credit
                END) AS dt_installment_credit,
            c0.dt_sale,
            CAST(c0.acquirer_pos AS INT) AS id_ec,
            c0.flag,
            UPPER(LEFT(TRIM(c0.flag), 4)) AS id_flag,
            CAST(c0.nsu_cv AS INT) AS nsu_cv,
            SUM(IF(CAST(c0.rv_summary_number AS INT) = 0, -1, CAST(c0.rv_summary_number AS INT))) AS rv_summary_number,
            c0.id_authorization,
            CAST(c0.installment_number AS INT) AS installment_number,
            CAST(c0.total_installments AS INT) AS total_installments,
            c0.installment_gross_amount,
            c0.installment_discount_value,
            c0.installment_net_amount,
            c0.total_sale_gross_amount,
            c0.total_sale_discount_amount,
            c0.total_sale_net_amount,
            CAST(c0.discount_charge AS double) AS discount_charge,
            CAST(c0.id_bank_grouper AS INT) AS id_bank_grouper,
            c0.ts_ingested,
            year,
            month,
            day
        FROM
            datalake_nexxera_clean.financial c0
        LEFT JOIN
            datalake_gsheets_clean.nexxera_holly_days hd ON hd.holly_day = c0.dt_installment_credit
        GROUP BY
            1,2,3,4,5,6,7,8,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24
)
    SELECT
        id_bank_grouper,
        id_ec,
        id_flag,
        id_authorization,
        ROW_NUMBER() OVER(ORDER BY dt_installment_credit, installment_gross_amount, installment_discount_value, installment_net_amount) AS rn_credit,
        manual_bank_reconciliation,
        payment_status,
        flag,
        nsu_cv,
        rv_summary_number,
        installment_number,
        total_installments,
        installment_gross_amount,
        installment_discount_value,
        installment_net_amount,
        total_sale_gross_amount,
        total_sale_discount_amount,
        total_sale_net_amount,
        discount_charge,
        dt_installment_credit,
        dt_sale,
        ts_ingested,
        year,
        month,
        day
    FROM
        base
