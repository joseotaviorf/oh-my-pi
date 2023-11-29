WITH claims_omie AS (
    SELECT
        CAST(CONCAT(te.sk_transaction_entry , '0002') AS BIGINT) AS sk_transaction_entry,
        CAST(CONCAT(t.sk_transaction ,'0002') AS BIGINT) AS sk_transaction,
        te.sk_propose,
        te.percent_amount_from_transaction,
        te.due_amount,
        te.paid_amount,
        (te.due_amount - te.paid_amount) AS open_amount,
        te.dt_register,
        te.dt_due,
        te.dt_paid,
        te.sk_omie_client,
        oc.corporate_name,
        oc.name_doing_business_as,
        oc.client_cpf_cnpj,
        oc.corporate_name ||' '|| oc.client_cpf_cnpj AS subscription_key,
        COALESCE(t.project, (oc.corporate_name ||' '|| oc.client_cpf_cnpj)) AS key,
        t.project,
        t.transaction_type,
        c.description,
        CASE
            WHEN te.sk_category = '1.01.03' THEN 'Taxa de ativação'
            WHEN te.sk_category IN ('1.01.96','1.01.97') THEN 'Juros e Multa'
            WHEN te.sk_category = '1.01.90' AND t.project is NULL THEN 'Assinatura'
            WHEN te.sk_category = '1.01.90' AND t.project IS NOT NULL THEN 'Garantia'
            WHEN te.sk_category IN ('1.01.02','1.01.01','1.01.91','1.01.92') THEN 'Assinatura'
            WHEN te.sk_category IN ('1.05.99','2.11.99','1.05.95','2.11.94','1.05.97','2.11.97','1.05.96','2.11.96','1.05.98','2.11.98') THEN 'Garantia'
            ELSE 'Outros'
        END AS provisional_group,
        NULL AS invoice_type,
        IF(dt_due < CURRENT_DATE AND EXTRACT (DAY FROM (COALESCE(dt_paid,CURRENT_DATE) - dt_due))>0, 1, 0) AS is_over,
        IF(dt_due < CURRENT_DATE AND EXTRACT (DAY FROM (COALESCE(dt_paid,CURRENT_DATE) - dt_due))>30, 1, 0) AS is_over_30,
        IF(dt_due < CURRENT_DATE AND EXTRACT (DAY FROM (COALESCE(dt_paid,CURRENT_DATE) - dt_due))>60, 1, 0) AS is_over_60,
        IF(dt_due < CURRENT_DATE AND EXTRACT (DAY FROM (COALESCE(dt_paid,CURRENT_DATE) - dt_due))>90, 1, 0) AS is_over_90
    FROM
        dw_velo.fact_velo_transaction_entries AS te
    LEFT JOIN
        dw_velo.dim_velo_transaction AS t
            ON t. sk_transaction = te.sk_transaction
    INNER JOIN
        dw_velo.dim_velo_transaction_category AS c
            ON te.sk_category = c.sk_category
    LEFT JOIN
        dw_velo.dim_velo_omie_client AS oc
            ON oc.sk_client = te.sk_omie_client
    WHERE
        transaction_type = 'CONTA_A_RECEBER'
),
30_claims AS (
    WITH qtd_bill AS (
        SELECT
            d.sk_propose AS id,
            COUNT(entry.id) AS bill_items
        FROM
            dw_velo.fact_velo_occurrence AS d
        LEFT JOIN
            datalake_rental_guarantee_platform_clean.delinquency_entry AS entry
                ON d.sk_occurrence = entry.id_delinquency
        WHERE
            entry.value IS NOT NULL
        GROUP BY 1
    )

    SELECT
        CAST(NULL AS BIGINT) AS sk_transaction_entry,
        CAST(CONCAT(d.sk_occurrence , '0003') AS BIGINT) AS sk_transaction,
        d.sk_propose AS sk_propose,
        NULL AS percent_amount_from_transaction,
        d.due_amount_original AS due_amount,
        d.paid_amount AS paid_amount,
        NULL AS open_amount,
        d.ts_created AS dt_register,
        d.dt_due,
        d.ts_paid AS dt_paid,
        NULL AS sk_omie_client,
        NULL AS corporate_name,
        NULL AS name_doing_business_as,
        NULL AS client_cpf_cnpj,
        NULL AS subscription_key,
        NULL AS key,
        NULL AS project,
        NULL AS transaction_type,
        entry.bill_item AS description,
        'Garantia' AS provisional_group,
        CASE
            WHEN j.desc_lvl_1 = 'GUARANTEE' THEN 'Garantia'
            WHEN j.desc_lvl_1 = 'TERMINATION' THEN 'Rescisao'
            ELSE NULL
        END AS invoice_type,
        IF(dt_due < CURRENT_DATE AND EXTRACT (DAY FROM (COALESCE(dt_paid,CURRENT_DATE) - dt_due))>0, 1, 0) AS is_over,
        IF(dt_due < CURRENT_DATE AND EXTRACT (DAY FROM (COALESCE(dt_paid,CURRENT_DATE) - dt_due))>30, 1, 0) AS is_over_30,
        IF(dt_due < CURRENT_DATE AND EXTRACT (DAY FROM (COALESCE(dt_paid,CURRENT_DATE) - dt_due))>60, 1, 0) AS is_over_60,
        IF(dt_due < CURRENT_DATE AND EXTRACT (DAY FROM (COALESCE(dt_paid,CURRENT_DATE) - dt_due))>90, 1, 0) AS is_over_90

    FROM
        dw_velo.fact_velo_occurrence AS d
    LEFT JOIN
        dw_velo.dim_velo_junk AS j
            ON d.sk_occurrence_type = j.sk_junk
    LEFT JOIN
        datalake_rental_guarantee_platform_clean.delinquency_entry AS entry
            ON d.sk_occurrence = entry.id_delinquency
    LEFT JOIN
        qtd_bill AS qtd
            ON d.sk_occurrence = qtd.id
    WHERE
        d.is_legacy IS TRUE
        AND j.desc_lvl_1 IN ('GUARANTEE', 'TERMINATION')
),
claims_final AS (
    SELECT
        *,
        2 AS system
    FROM
        claims_omie
    WHERE
        provisional_group = 'Garantia'

    UNION ALL

    SELECT
        *,
        3 AS system
    FROM
        30_claims
),
cte_contracts AS (
    SELECT DISTINCT
        b1.sk_propose,
        DATE(b1.ts_propose_started) AS dt_created,
        DATE(b1.ts_evaluation_started) AS dt_es,
        DATE(b1.ts_sign_started) AS dt_ca,
        b1.dt_contract_started AS dt_cs
    FROM
        dw_velo.fact_velo_propose AS b1
    WHERE
        b1.is_contract IS TRUE
),
cte_claims_by_month AS (
    SELECT
        f.sk_propose,
        f.provisional_group,
        DATEDIFF(MONTH, DATE_TRUNC('month',c.dt_cs), DATE_TRUNC('month',f.dt_register)) AS mob,
        DATE_TRUNC('month', f.dt_register) AS dt_month_claim,
        SUM(f.due_amount) AS due_amount
    FROM
        claims_final AS f
    LEFT JOIN
        cte_contracts AS c
            ON f.sk_propose = c.sk_propose
    WHERE
        provisional_group = 'Garantia'
    GROUP BY 1,2,3,4
),
cte_claims AS (
    SELECT
        cf.sk_propose,
        cf.provisional_group,
        MIN(cf.dt_register) AS dt_first_claim,
        MAX(cf.dt_register) AS dt_last_claim,
        COUNT(DISTINCT cm.mob) AS mob_count,
        SUM(cm.due_amount) AS total_mob_value,
        ARRAY_AGG(DISTINCT cm.mob) AS mob_array,
        SUM(IF(cm.mob = 0, cm.due_amount, 0)) AS claim_value_mob0,
        SUM(IF(cm.mob = 1, cm.due_amount, 0)) AS claim_value_mob1,
        SUM(IF(cm.mob = 2, cm.due_amount, 0)) AS claim_value_mob2,
        SUM(IF(cm.mob = 3, cm.due_amount, 0)) AS claim_value_mob3,
        SUM(IF(cm.mob = 4, cm.due_amount, 0)) AS claim_value_mob4,
        SUM(IF(cm.mob = 5, cm.due_amount, 0)) AS claim_value_mob5,
        SUM(IF(cm.mob = 6, cm.due_amount, 0)) AS claim_value_mob6,
        SUM(IF(cm.mob = 7, cm.due_amount, 0)) AS claim_value_mob7,
        SUM(IF(cm.mob = 8, cm.due_amount, 0)) AS claim_value_mob8,
        SUM(IF(cm.mob = 9, cm.due_amount, 0)) AS claim_value_mob9,
        SUM(IF(cm.mob = 10, cm.due_amount, 0)) AS claim_value_mob10,
        SUM(IF(cm.mob = 11, cm.due_amount, 0)) AS claim_value_mob11,
        SUM(IF(cm.mob = 12, cm.due_amount, 0)) AS claim_value_mob12,
        SUM(IF(cm.mob = 13, cm.due_amount, 0)) AS claim_value_mob13,
        SUM(IF(cm.mob = 14, cm.due_amount, 0)) AS claim_value_mob14,
        SUM(IF(cm.mob = 15, cm.due_amount, 0)) AS claim_value_mob15,
        SUM(IF(cm.mob = 16, cm.due_amount, 0)) AS claim_value_mob16,
        SUM(IF(cm.mob = 17, cm.due_amount, 0)) AS claim_value_mob17,
        SUM(IF(cm.mob = 18, cm.due_amount, 0)) AS claim_value_mob18,
        SUM(IF(cm.mob = 19, cm.due_amount, 0)) AS claim_value_mob19,
        SUM(IF(cm.mob = 20, cm.due_amount, 0)) AS claim_value_mob20,
        SUM(IF(cm.mob = 21, cm.due_amount, 0)) AS claim_value_mob21,
        SUM(IF(cm.mob = 22, cm.due_amount, 0)) AS claim_value_mob22,
        SUM(IF(cm.mob = 23, cm.due_amount, 0)) AS claim_value_mob23,
        SUM(IF(cm.mob = 24, cm.due_amount, 0)) AS claim_value_mob24,
        SUM(IF(cm.mob = 25, cm.due_amount, 0)) AS claim_value_mob25,
        SUM(IF(cm.mob = 26, cm.due_amount, 0)) AS claim_value_mob26,
        SUM(IF(cm.mob = 27, cm.due_amount, 0)) AS claim_value_mob27,
        SUM(IF(cm.mob = 28, cm.due_amount, 0)) AS claim_value_mob28,
        SUM(IF(cm.mob = 29, cm.due_amount, 0)) AS claim_value_mob29,
        SUM(IF(cm.mob = 30, cm.due_amount, 0)) AS claim_value_mob30,
        SUM(IF(cm.mob > 30, cm.due_amount, 0)) AS claim_value_mob31_more
    FROM
        claims_final AS cf
    LEFT JOIN
        cte_claims_by_month AS cm
            ON cf.sk_propose = cm.sk_propose
    WHERE
        cf.provisional_group = 'Garantia'
    GROUP BY 1,2
),
cte_final AS (
    SELECT
        b1.sk_propose,
        b1.dt_created,
        b1.dt_es,
        b1.dt_ca,
        b1.dt_cs,
        b2.provisional_group,
        b2.dt_first_claim,
        b2.dt_last_claim,
        b2.mob_count,
        b2.total_mob_value,
        b2.claim_value_mob0,
        b2.claim_value_mob1,
        b2.claim_value_mob2,
        b2.claim_value_mob3,
        b2.claim_value_mob4,
        b2.claim_value_mob5,
        b2.claim_value_mob6,
        b2.claim_value_mob7,
        b2.claim_value_mob8,
        b2.claim_value_mob9,
        b2.claim_value_mob10,
        b2.claim_value_mob11,
        b2.claim_value_mob12,
        b2.claim_value_mob13,
        b2.claim_value_mob14,
        b2.claim_value_mob15,
        b2.claim_value_mob16,
        b2.claim_value_mob17,
        b2.claim_value_mob18,
        b2.claim_value_mob19,
        b2.claim_value_mob20,
        b2.claim_value_mob21,
        b2.claim_value_mob22,
        b2.claim_value_mob23,
        b2.claim_value_mob24,
        b2.claim_value_mob25,
        b2.claim_value_mob26,
        b2.claim_value_mob27,
        b2.claim_value_mob28,
        b2.claim_value_mob29,
        b2.claim_value_mob30,
        b2.claim_value_mob31_more,
        DATEDIFF(MONTH, DATE_TRUNC('month',b1.dt_cs), DATE_TRUNC('month',b2.dt_first_claim)) AS mob,
        b2.mob_array
    FROM
        cte_contracts AS b1
    LEFT JOIN
        cte_claims AS b2
            ON b1.sk_propose = b2.sk_propose
)

SELECT DISTINCT
    f.sk_propose,
    f.mob_count AS total_mob_count,
    f.total_mob_value,
    DATEDIFF(MONTH, DATE_TRUNC('month',f.dt_cs), DATE_TRUNC('month',CURRENT_DATE) ) AS cohort_age_mob_actual,
    f.mob AS first_claim_mob,
    IF(f.mob = 0, 1, 0) AS claim_mob0,
    IF(f.mob BETWEEN 0 AND 1, 1, 0) AS claim_mob1,
    IF(f.mob BETWEEN 0 AND 2, 1, 0) AS claim_mob2,
    IF(f.mob BETWEEN 0 AND 3, 1, 0) AS claim_mob3,
    IF(f.mob BETWEEN 0 AND 4, 1, 0) AS claim_mob4,
    IF(f.mob BETWEEN 0 AND 5, 1, 0) AS claim_mob5,
    IF(f.mob BETWEEN 0 AND 6, 1, 0) AS claim_mob6,
    IF(f.mob BETWEEN 0 AND 7, 1, 0) AS claim_mob7,
    IF(f.mob BETWEEN 0 AND 8, 1, 0) AS claim_mob8,
    IF(f.mob BETWEEN 0 AND 9, 1, 0) AS claim_mob9,
    IF(f.mob BETWEEN 0 AND 10, 1, 0) AS claim_mob10,
    IF(f.mob BETWEEN 0 AND 11, 1, 0) AS claim_mob11,
    IF(f.mob BETWEEN 0 AND 12, 1, 0) AS claim_mob12,
    IF(f.mob BETWEEN 0 AND 13, 1, 0) AS claim_mob13,
    IF(f.mob BETWEEN 0 AND 14, 1, 0) AS claim_mob14,
    IF(f.mob BETWEEN 0 AND 15, 1, 0) AS claim_mob15,
    IF(f.mob BETWEEN 0 AND 16, 1, 0) AS claim_mob16,
    IF(f.mob BETWEEN 0 AND 17, 1, 0) AS claim_mob17,
    IF(f.mob BETWEEN 0 AND 18, 1, 0) AS claim_mob18,
    IF(f.mob BETWEEN 0 AND 19, 1, 0) AS claim_mob19,
    IF(f.mob BETWEEN 0 AND 20, 1, 0) AS claim_mob20,
    IF(f.mob BETWEEN 0 AND 21, 1, 0) AS claim_mob21,
    IF(f.mob BETWEEN 0 AND 22, 1, 0) AS claim_mob22,
    IF(f.mob BETWEEN 0 AND 23, 1, 0) AS claim_mob23,
    IF(f.mob BETWEEN 0 AND 24, 1, 0) AS claim_mob24,
    IF(f.mob BETWEEN 0 AND 25, 1, 0) AS claim_mob25,
    IF(f.mob BETWEEN 0 AND 26, 1, 0) AS  claim_mob26,
    IF(f.mob BETWEEN 0 AND 27, 1, 0) AS  claim_mob27,
    IF(f.mob BETWEEN 0 AND 28, 1, 0) AS  claim_mob28,
    IF(f.mob BETWEEN 0 AND 29, 1, 0) AS  claim_mob29,
    IF(f.mob BETWEEN 0 AND 30, 1, 0) AS claim_mob30,
    IF(f.mob IS NOT NULL, 1, 0) AS claim_mob31_more,
    IF(ARRAY_CONTAINS(f.mob_array, 0), 1, 0) AS mob_has_claim0,
    IF(ARRAY_CONTAINS(f.mob_array, 1), 1, 0) AS mob_has_claim1,
    IF(ARRAY_CONTAINS(f.mob_array, 2), 1, 0) AS mob_has_claim2,
    IF(ARRAY_CONTAINS(f.mob_array, 3), 1, 0) AS mob_has_claim3,
    IF(ARRAY_CONTAINS(f.mob_array, 4), 1, 0) AS mob_has_claim4,
    IF(ARRAY_CONTAINS(f.mob_array, 5), 1, 0) AS mob_has_claim5,
    IF(ARRAY_CONTAINS(f.mob_array, 6), 1, 0) AS mob_has_claim6,
    IF(ARRAY_CONTAINS(f.mob_array, 7), 1, 0) AS mob_has_claim7,
    IF(ARRAY_CONTAINS(f.mob_array, 8), 1, 0) AS mob_has_claim8,
    IF(ARRAY_CONTAINS(f.mob_array, 9), 1, 0) AS mob_has_claim9,
    IF(ARRAY_CONTAINS(f.mob_array, 10), 1, 0) AS mob_has_claim10,
    IF(ARRAY_CONTAINS(f.mob_array, 11), 1, 0) AS mob_has_claim11,
    IF(ARRAY_CONTAINS(f.mob_array, 12), 1, 0) AS mob_has_claim12,
    IF(ARRAY_CONTAINS(f.mob_array, 13), 1, 0) AS mob_has_claim13,
    IF(ARRAY_CONTAINS(f.mob_array, 14), 1, 0) AS mob_has_claim14,
    IF(ARRAY_CONTAINS(f.mob_array, 15), 1, 0) AS mob_has_claim15,
    IF(ARRAY_CONTAINS(f.mob_array, 16), 1, 0) AS mob_has_claim16,
    IF(ARRAY_CONTAINS(f.mob_array, 17), 1, 0) AS mob_has_claim17,
    IF(ARRAY_CONTAINS(f.mob_array, 18), 1, 0) AS mob_has_claim18,
    IF(ARRAY_CONTAINS(f.mob_array, 19), 1, 0) AS mob_has_claim19,
    IF(ARRAY_CONTAINS(f.mob_array, 20), 1, 0) AS mob_has_claim20,
    IF(ARRAY_CONTAINS(f.mob_array, 21), 1, 0) AS mob_has_claim21,
    IF(ARRAY_CONTAINS(f.mob_array, 22), 1, 0) AS mob_has_claim22,
    IF(ARRAY_CONTAINS(f.mob_array, 23), 1, 0) AS mob_has_claim23,
    IF(ARRAY_CONTAINS(f.mob_array, 24), 1, 0) AS mob_has_claim24,
    IF(ARRAY_CONTAINS(f.mob_array, 25), 1, 0) AS mob_has_claim25,
    IF(ARRAY_CONTAINS(f.mob_array, 26), 1, 0) AS mob_has_claim26,
    IF(ARRAY_CONTAINS(f.mob_array, 27), 1, 0) AS mob_has_claim27,
    IF(ARRAY_CONTAINS(f.mob_array, 28), 1, 0) AS mob_has_claim28,
    IF(ARRAY_CONTAINS(f.mob_array, 29), 1, 0) AS mob_has_claim29,
    IF(ARRAY_CONTAINS(f.mob_array, 30), 1, 0) AS mob_has_claim30,
    IF(ARRAY_MAX(f.mob_array) > 30, 1, 0) AS mob_has_claim31_more,
    f.claim_value_mob0,
    f.claim_value_mob1,
    f.claim_value_mob2,
    f.claim_value_mob3,
    f.claim_value_mob4,
    f.claim_value_mob5,
    f.claim_value_mob6,
    f.claim_value_mob7,
    f.claim_value_mob8,
    f.claim_value_mob9,
    f.claim_value_mob10,
    f.claim_value_mob11,
    f.claim_value_mob12,
    f.claim_value_mob13,
    f.claim_value_mob14,
    f.claim_value_mob15,
    f.claim_value_mob16,
    f.claim_value_mob17,
    f.claim_value_mob18,
    f.claim_value_mob19,
    f.claim_value_mob20,
    f.claim_value_mob21,
    f.claim_value_mob22,
    f.claim_value_mob23,
    f.claim_value_mob24,
    f.claim_value_mob25,
    f.claim_value_mob26,
    f.claim_value_mob27,
    f.claim_value_mob28,
    f.claim_value_mob29,
    f.claim_value_mob30,
    f.claim_value_mob31_more,
    IF(f.mob IS NOT NULL, 1, 0) AS is_claim,
    f.dt_created,
    f.dt_es,
    f.dt_ca,
    f.dt_cs,
    f.dt_first_claim,
    f.dt_last_claim,
    NOW() AS ts_load
FROM
    cte_final AS f
ORDER BY dt_created
