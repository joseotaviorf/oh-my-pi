WITH bank_grouper_0 AS (
        SELECT DISTINCT
            COALESCE( cc.dt_installment_credit ,aa.dt_adjustment_launch ,bb.dt_launch) AS dt_credit,
            COALESCE(cc.id_ec, aa.id_ec, bb.id_ec) AS id_ec,
            COALESCE(cc.flag, aa.flag) AS flag,
            COALESCE(cc.id_flag, aa.id_flag, bb.id_flag) AS id_flag,
            COALESCE(cc.id_bank_grouper, aa.id_bank_grouper) AS id_bank_grouper,
            bb.rn_bank
        FROM
            datalake_nexxera.financial cc
        FULL OUTER JOIN
            datalake_nexxera.adjustments aa
            ON cc.dt_installment_credit = aa.dt_adjustment_launch
            AND cc.id_ec = aa.id_ec
            AND cc.id_flag = aa.id_flag
            AND cc.id_bank_grouper = aa.id_bank_grouper
        FULL OUTER JOIN
            datalake_nexxera.financial_extracts_050e bb
            ON cc.dt_installment_credit = bb.dt_launch
            AND cc.id_ec = bb.id_ec
            AND cc.id_flag = bb.id_flag
    ),
    bank_grouper AS (
        SELECT DISTINCT
            bg0.dt_credit,
            bg0.id_ec,
            bg0.flag,
            COALESCE(bg1.flag, bg0.flag, '-1') AS end_flag,
            bg0.id_flag,
            COALESCE(bg1.id_flag, bg0.id_flag, '-1') AS end_id_flag,
            COALESCE(bg0.id_bank_grouper, -1) AS id_bank_grouper,
            COALESCE(bg1.id_bank_grouper, bg0.id_bank_grouper, -1) AS end_id_bank_grouper,
            COALESCE(bg1.rn_bank, bg0.rn_bank) AS rn_bank
        FROM
            bank_grouper_0 bg0
        LEFT JOIN
            (SELECT * FROM bank_grouper_0 WHERE rn_bank IS NOT NULL) bg1
            ON bg0.id_ec = bg1.id_ec
            AND (bg1.id_bank_grouper = bg0.id_bank_grouper OR (bg1.id_bank_grouper != bg0.id_bank_grouper AND bg0.dt_credit = bg1.dt_credit AND bg0.id_flag = bg1.id_flag))
        WHERE
            COALESCE(bg1.rn_bank, bg0.rn_bank) IS NOT NULL
    ),
    credit AS (
        SELECT
            c0.rn_credit,
            c0.manual_bank_reconciliation,
            c0.payment_status,
            c0.dt_installment_credit,
            c0.dt_sale,
            c0.id_ec,
            COALESCE(bg.end_flag, c0.flag) AS flag,
            COALESCE(bg.end_id_flag, c0.id_flag) AS id_flag,
            c0.nsu_cv,
            c0.rv_summary_number,
            c0.id_authorization,
            c0.installment_number,
            c0.total_installments,
            c0.installment_gross_amount,
            c0.installment_discount_value,
            c0.installment_net_amount,
            c0.total_sale_gross_amount,
            c0.total_sale_discount_amount,
            c0.total_sale_net_amount,
            c0.discount_charge,
            COALESCE(bg.end_id_bank_grouper, c0.id_bank_grouper, -1) AS id_bank_grouper,
            COALESCE(bg.rn_bank, -1) AS rn_bank,
            c0.ts_ingested,
            c0.year,
            c0.month,
            c0.day
        FROM
            datalake_nexxera.financial c0
        LEFT JOIN bank_grouper bg
            ON bg.dt_credit = c0.dt_installment_credit
            AND bg.id_ec = c0.id_ec
            AND bg.id_flag = c0.id_flag
            AND bg.id_bank_grouper = COALESCE(c0.id_bank_grouper, -1)
    ),
    adjustments AS (
        SELECT
            a0.rn_adjustments,
            a0.dt_adjustment_launch,
            a0.dt_sale_adjustment,
            COALESCE(bg.end_flag, a0.flag) AS flag,
            COALESCE(bg.end_id_flag, a0.id_flag) AS id_flag,
            a0.installment_number,
            a0.total_installments,
            COALESCE(bg.end_id_bank_grouper, a0.id_bank_grouper, -1) AS id_bank_grouper,
            a0.current_summary_number,
            a0.id_authorization,
            a0.nsu_cv,
            a0.adjustment_original_reason,
            a0.id_ec,
            a0.adjustment_value,
            a0.net_adjustment_value,
            a0.adjustment_value_tax,
            a0.counter_adjustments,
            COALESCE(bg.rn_bank, -1) AS rn_bank,
            a0.ts_ingested,
            a0.year,
            a0.month,
            a0.day
        FROM
            datalake_nexxera.adjustments a0
        LEFT JOIN
            bank_grouper bg
            ON bg.dt_credit = a0.dt_adjustment_launch
            AND bg.id_ec = a0.id_ec
            AND bg.id_flag = a0.id_flag
            AND bg.id_bank_grouper = COALESCE(a0.id_bank_grouper, -1)
    ),
    end_credit AS (
        SELECT
            c1.id_bank_grouper,
            c1.id_flag,
            c1.flag || ':' || c1.id_ec AS id_external_payment,
            c1.manual_bank_reconciliation AS reconciliation_status,
            'Ref. Baixa de Cartão | ' || c1.flag || ':' || c1.id_ec AS description_memo,
            c1.rn_credit,
            COALESCE(a1.rn_adjustments, -1) AS rn_adjustments,
            c1.rn_bank,
            c1.payment_status,
            c1.id_ec AS ec,
            c1.flag,
            c1.rv_summary_number AS summary_number,
            c1.id_authorization AS authorization_number,
            c1.nsu_cv AS receipt,
            c1.installment_number,
            c1.total_installments,
            c1.installment_gross_amount AS gross_amount,
            c1.installment_discount_value AS tax_amount,
            c1.installment_net_amount AS net_amount,
            c1.total_sale_gross_amount AS total_gross_amount,
            c1.total_sale_discount_amount AS total_tax_amount,
            c1.total_sale_net_amount AS total_net_amount,
            c1.discount_charge AS tax,
            COALESCE(a1.adjustment_original_reason, '-1') AS adjustment_type,
            COALESCE(a1.adjustment_value, 0.00) AS adjustment_gross_value,
            COALESCE(a1.net_adjustment_value, 0.00) AS adjustment_sale_value,
            COALESCE(a1.adjustment_value_tax, 0.00) AS adjustment_tax_value,
            COALESCE(a1.dt_adjustment_launch, '-1') AS dt_credit_adjustment,
            c1.dt_installment_credit AS dt_credit,
            c1.dt_sale,
            c1.ts_ingested,
            c1.year,
            c1.month,
            c1.day
        FROM
            credit c1
        LEFT JOIN
            adjustments a1
            ON a1.rn_bank = c1.rn_bank
            AND a1.installment_number = c1.installment_number
            AND a1.id_ec = c1.id_ec
            AND a1.nsu_cv = c1.nsu_cv
    ),
    end_adjustments AS (
        SELECT
            a0.id_bank_grouper,
            a0.id_flag,
            a0.flag || ':' || a0.id_ec AS id_external_payment,
            COALESCE(cc.manual_bank_reconciliation, -1) AS reconciliation_status,
            'Ref. Baixa de Cartão | ' || a0.flag || ':' || a0.id_ec AS description_memo,
            COALESCE(cc.rn_credit, -1) AS rn_credit,
            a0.rn_adjustments,
            a0.rn_bank,
            COALESCE(cc.payment_status, -1) AS payment_status,
            a0.id_ec AS ec,
            a0.flag,
            COALESCE(a0.current_summary_number, cc.rv_summary_number) AS summary_number,
            COALESCE(a0.id_authorization,cc.id_authorization,UPPER(LEFT(a0.adjustment_original_reason, 2))) AS authorization_number,
            COALESCE(a0.nsu_cv, cc.nsu_cv) AS receipt,
            COALESCE(a0.installment_number, cc.installment_number) AS installment_number,
            COALESCE(a0.total_installments, cc.total_installments) AS total_installments,
            0.00 AS gross_amount,
            0.00 AS tax_amount,
            0.00 AS net_amount,
            0.00 AS total_gross_amount,
            0.00 AS total_tax_amount,
            0.00 AS total_net_amount,
            0.00 AS tax,
            a0.adjustment_original_reason AS adjustment_type,
            a0.adjustment_value AS adjustment_gross_value,
            a0.net_adjustment_value AS adjustment_sale_value,
            a0.adjustment_value_tax AS adjustment_tax_value,
            a0.dt_adjustment_launch AS dt_credit_adjustment,
            a0.dt_adjustment_launch AS dt_credit,
            a0.dt_sale_adjustment AS dt_sale,
            a0.ts_ingested,
            a0.year,
            a0.month,
            a0.day
        FROM (
                SELECT
                    a1.*
                FROM
                    adjustments a1
                LEFT JOIN
                    end_credit ct ON ct.rn_adjustments = a1.rn_adjustments
                WHERE
                    ct.rn_adjustments IS NULL
                ORDER BY
                    a1.rn_adjustments
            ) a0
        LEFT JOIN
            credit cc
            ON a0.installment_number = cc.installment_number
            AND a0.id_ec = cc.id_ec
            AND a0.nsu_cv = cc.nsu_cv
    ),
    end_union AS (
        SELECT
            *
        FROM
            end_credit
        UNION ALL
        SELECT
            *
        FROM
            end_adjustments
    )

    SELECT
        id_bank_grouper,
        id_flag,
        id_external_payment,
        reconciliation_status,
        description_memo,
        ROW_NUMBER() OVER(ORDER BY rn_bank, rn_credit, rn_adjustments) AS rn_end,
        rn_credit,
        rn_adjustments,
        rn_bank,
        payment_status,
        ec,
        flag,
        summary_number,
        authorization_number,
        receipt,
        installment_number,
        total_installments,
        gross_amount,
        tax_amount,
        net_amount,
        total_gross_amount,
        total_tax_amount,
        total_net_amount,
        tax,
        adjustment_type,
        adjustment_gross_value,
        adjustment_sale_value,
        adjustment_tax_value,
        dt_credit_adjustment,
        dt_credit,
        dt_sale,
        ts_ingested,
        year,
        month,
        day
    FROM
        end_union
