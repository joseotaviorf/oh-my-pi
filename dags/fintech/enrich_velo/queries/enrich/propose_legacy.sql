WITH old_system_dates AS (
    WITH propose_canceled_date AS (
        SELECT
            id_propose,
            MAX(CAST(ts_updated AS TIMESTAMP)) AS ts_ended
        FROM
            datalake_rental_guarantee_platform_clean.fiancavelo_proposehistory_legacy
        WHERE
            text_key = 10 --10 indicates that the propose has ended
            AND id_history_type = 1 -- alteration by the system
        GROUP BY
            1 -- some proposes can have multiple same status
    ),
    propose_started_date AS (
        SELECT
            id_propose,
            MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_propose_started
        FROM
            datalake_rental_guarantee_platform_clean.fiancavelo_proposehistory_legacy
        WHERE
            text_key = 2 --2 indicates that the propose has started
            AND id_history_type = 1 -- alteration by the system
        GROUP BY
            1 -- some proposes can have multiple same status
    ),
    propose_waiting_new_docs_date AS (
        SELECT
            id_propose,
            MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_waiting_new_docs
        FROM
            datalake_rental_guarantee_platform_clean.fiancavelo_proposehistory_legacy
        WHERE
            text_key = 3 -- indicates that the propose is waiting for more docs
            AND id_history_type = 1 -- alteration by the system
        GROUP BY
            1 -- some proposes can have multiple same status
    ),
    propose_evaluation_started_date AS (
        SELECT
            id_propose,
            MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_evaluation_started
        FROM
            datalake_rental_guarantee_platform_clean.fiancavelo_proposehistory_legacy
        WHERE
            text_key > 2
            AND text_key < 10
            AND id_history_type = 1 -- alteration by the system
        GROUP BY
            1 -- some proposes can have multiple same status
    ),
    propose_rejected_date AS (
        SELECT
            id_propose,
            MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_rejected
        FROM
            datalake_rental_guarantee_platform_clean.fiancavelo_proposehistory_legacy
        WHERE
            text_key = 5 -- indicates that the propose was rejected
            AND id_history_type = 1 -- alteration by the system
        GROUP BY
            1 -- some proposes can have multiple same status
    ),
    propose_sign_started_date AS (
        SELECT
            id_propose,
            MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_sign_started
        FROM
            datalake_rental_guarantee_platform_clean.fiancavelo_proposehistory_legacy
        WHERE
            text_key = 6 -- indicates that the sign has started
            AND id_history_type = 1 -- alteration by the system
        GROUP BY
            1 -- some proposes can have multiple same status
    ),
    propose_signed_date AS (
        SELECT
            id_propose,
            MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_signed
        FROM
            datalake_rental_guarantee_platform_clean.fiancavelo_proposehistory_legacy
        WHERE
            text_key = 7 -- indicates that the propose has been paid
            AND id_history_type = 1 -- alteration by the system
        GROUP BY
            1 -- some proposes can have multiple same status
    ),
    propose_paid_date AS (
        SELECT
            id_propose,
            MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_paid
        FROM
            datalake_rental_guarantee_platform_clean.fiancavelo_proposehistory_legacy
        WHERE
            text_key = 8 -- indicates that the propose has been paid
            AND id_history_type = 1 -- alteration by the system
        GROUP BY
            1 -- some proposes can have multiple same status
    ),
    propose_activation_date AS (
        SELECT
            id_propose,
            MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_activation
        FROM
            datalake_rental_guarantee_platform_clean.fiancavelo_proposehistory_legacy
        WHERE
            text_key = 8 -- indicates that the propose is active
            AND id_history_type = 1 -- alteration by the system
        GROUP BY
            1 -- some proposes can have multiple same status
    ),
    propose_secured_date AS (
        SELECT
            id_propose,
            MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_secured
        FROM
            datalake_rental_guarantee_platform_clean.fiancavelo_proposehistory_legacy
        WHERE
            text_key = 9 -- indicates that the propose is secured
            AND id_history_type = 1 -- alteration by the system
        GROUP BY
            1 -- some proposes can have multiple same status
    ),
    propose_activation_analysis_date AS (
        SELECT
            id_propose,
            MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_activation_analysis
        FROM
            datalake_rental_guarantee_platform_clean.fiancavelo_proposehistory_legacy
        WHERE
            text_key = 11 -- indicates that the propose is active but in analysis
            AND id_history_type = 1 -- alteration by the system
        GROUP BY
            1 -- some proposes can have multiple same status
    ),
    propose_secure_pending_date AS (
        SELECT
            id_propose,
            MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_secure_pending
        FROM
            datalake_rental_guarantee_platform_clean.fiancavelo_proposehistory_legacy
        WHERE
            text_key = 12 -- indicates that the propose is waiting to be secured
            AND id_history_type = 1 -- alteration by the system
        GROUP BY
            1 -- some proposes can have multiple same status
    ),
    fiancavelo_fianca_last_updated AS (
        SELECT *
        FROM
            datalake_rental_guarantee_platform_clean.fiancavelo_fianca_legacy AS f
        QUALIFY
            ROW_NUMBER() OVER (PARTITION BY id_propose ORDER BY ts_updated DESC) = 1
    )
    SELECT
        p.id AS id_propose,
        f.id AS id_contract,
        DATE(f.dt_begin) AS dt_contract_started,
        COALESCE(f.dt_ended, DATE(pcd.ts_ended)) AS dt_ended,
        COALESCE(DATE(pcd.ts_ended), f.dt_ended) AS dt_analyst_annulment_input,
        COALESCE(sd.ts_propose_started, p.ts_inserted) AS ts_propose_started,
        wndd.ts_waiting_new_docs,
        esd.ts_evaluation_started,
        rd.ts_rejected,
        ssd.ts_sign_started,
        psd.ts_signed,
        pd.ts_paid,
        ad.ts_activation,
        sed.ts_secured,
        aad.ts_activation_analysis,
        spd.ts_secure_pending
    FROM
        datalake_rental_guarantee_platform_clean.fiancavelo_propose_legacy AS p
    LEFT JOIN
        fiancavelo_fianca_last_updated AS f
            ON f.id_propose = p.id
    LEFT JOIN
        propose_canceled_date AS pcd
            ON pcd.id_propose = p.id
    LEFT JOIN
        propose_started_date AS sd
            ON sd.id_propose = p.id
    LEFT JOIN
        propose_waiting_new_docs_date AS wndd
            ON wndd.id_propose = p.id
    LEFT JOIN
        propose_evaluation_started_date AS esd
            ON esd.id_propose = p.id
    LEFT JOIN
        propose_rejected_date AS rd
            ON rd.id_propose = p.id
    LEFT JOIN
        propose_sign_started_date AS ssd
            ON ssd.id_propose = p.id
    LEFT JOIN
        propose_paid_date AS pd
            ON pd.id_propose = p.id
    LEFT JOIN
        propose_signed_date AS psd
            ON psd.id_propose = p.id
    LEFT JOIN
        propose_activation_date AS ad
            ON ad.id_propose = p.id
    LEFT JOIN
        propose_secured_date AS sed
            ON sed.id_propose = p.id
    LEFT JOIN
        propose_activation_analysis_date AS aad
            ON aad.id_propose = p.id
    LEFT JOIN
        propose_secure_pending_date AS spd
            ON spd.id_propose = p.id
),
propose_company AS (
    SELECT
        id_propose,
        id_company,
        ROW_NUMBER() OVER(PARTITION BY id_propose ORDER BY ts_updated DESC) AS rn
    FROM
        datalake_rental_guarantee_platform_clean.fiancavelo_proposecompany_legacy
    ),
prop_values_structure AS (
    WITH cte_values AS (
        SELECT
            id_propose,
            pi.value,
            it.name
        FROM
            datalake_rental_guarantee_platform_clean.propose_item AS pi
        LEFT JOIN
            datalake_rental_guarantee_platform_clean.item_type AS it
                ON pi.id_item_type = it.id
    )
    SELECT
        *
    FROM
        cte_values
    PIVOT(
        SUM(value)
        FOR name IN
        (
            'Aluguel' AS rent_amount,
            'Luz' AS light_amount,
            'Iptu' AS iptu_amount,
            'Condomínio' AS condo_amount,
            'Outros' AS other_amount
        )
    )
),

-- cte to get propose_values from propose_legacy proposes
old_prop_values AS (
    WITH old_duplicated_company_plan AS (
        SELECT
            pl.id AS id_plan,
            cp.id_company,
            COUNT(*) AS count_company_plan
        FROM
            datalake_rental_guarantee_platform_clean.plan AS pl
        LEFT JOIN
            datalake_rental_guarantee_platform_clean.company_plan AS cp
                ON pl.id = cp.id_plan
        GROUP BY 1, 2
    )
    SELECT
        p.id AS id_propose,
        CONCAT(p.id, COALESCE(cp.id, ''), pl.id) * -1 AS id_propose_values,
        COALESCE((pv.rent_amount + pv.condo_amount + pv.light_amount + pv.iptu_amount + pv.other_amount)*pl.pricing,0) AS monthly_guarantee
    FROM
        datalake_rental_guarantee_platform_clean.fiancavelo_propose_legacy AS p
    LEFT JOIN
        datalake_rental_guarantee_platform_clean.plan AS pl
            ON p.id_plan = pl.id_legacy
    LEFT JOIN
        old_duplicated_company_plan AS odcp
            ON pl.id = odcp.id_plan
            AND p.id_quintocred_company = odcp.id_company
    LEFT JOIN
        datalake_rental_guarantee_platform_clean.company_plan AS cp
            ON p.id_quintocred_company = cp.id_company
            AND pl.id = cp.id_plan
            AND odcp.count_company_plan = 1
    LEFT JOIN
        prop_values_structure AS pv
            ON p.id = pv.id_propose
),
    old_house AS (
    SELECT
        o.id_propose AS id_propose,
        py.id AS id_house,
        ROW_NUMBER() OVER (PARTITION BY o.id_propose ORDER BY o.ts_updated DESC, o.id_property DESC) AS rn -- House update order, there was a bug in product that created a new id for every update. To solve, order by the latest update date.
    FROM
        datalake_rental_guarantee_platform_clean.fiancavelo_object_legacy AS o
    LEFT JOIN
        datalake_rental_guarantee_platform_clean.fiancavelo_property_legacy AS py
        ON py.id = o.id_property
            AND py.is_active
    WHERE
        o.is_active
    ),
    old_main_client AS (
    SELECT
        pp.id_propose,
        pp.id_person AS id_primary_person,
        ROW_NUMBER() OVER(PARTITION BY pp.id_propose ORDER BY pp.ts_updated DESC) AS rn
        FROM
        datalake_rental_guarantee_platform_clean.fiancavelo_proposeperson_legacy AS pp
        WHERE
        pp.is_active
            AND pp.id_type = 1 -- bringing only main IQ
    ),
    main_person AS (
        SELECT
            id_person,
            id_propose,
            declared_income
        FROM
            datalake_velo.propose_person_legacy
        WHERE
            is_primary_person IS TRUE
    ),
    old_persons_metrics AS (
    SELECT
        pp.id_propose,
        MAX(mp.declared_income) / SUM(pp.declared_income) AS percentage_income_from_primary_person,
        COUNT(pp.id_person) AS count_persons_included,
        AVG(pp.serasa_score) AS avg_serasa_score,
        AVG(pp.risk_score) AS avg_risk_score,
        AVG(pp.declared_income) AS avg_declared_income,
        SUM(pp.declared_income) AS total_declared_income
    FROM
        datalake_velo.propose_person_legacy AS pp
    LEFT JOIN
        main_person AS mp
            ON mp.id_propose = pp.id_propose
    GROUP BY 1
    ),
old_payments_metrics AS (
    SELECT
        id_propose,
        SUM(IF(dt_paid IS NOT NULL, due_amount, 0)) AS total_paid_amount,
        SUM(due_amount) AS total_expected_amount,
        SUM(IF(dt_paid IS NULL, due_amount, 0)) AS total_due_amount,
        -- CAST(NULL AS DOUBLE) AS lmi,
        COUNT(id_payment) AS total_payments,
        SUM(IF(dt_paid IS NOT NULL, 1, 0)) AS total_payments_paid,
        SUM(IF(dt_paid IS NULL AND dt_due < current_date, 1, 0)) AS total_payments_expired,
        MAX(dt_paid) AS dt_last_payment
    FROM
        datalake_velo.payment_legacy
    GROUP BY 1
),
persons_metrics AS (
    SELECT
        pp.id_propose,
        MAX(mp.declared_income) / SUM(pp.declared_income) AS percentage_income_from_primary_person,
        COUNT(pp.id_person) AS count_persons_included,
        AVG(pp.serasa_score) AS avg_serasa_score,
        AVG(pp.risk_score) AS avg_risk_score,
        AVG(pp.declared_income) AS avg_declared_income,
        SUM(pp.declared_income) AS total_declared_income
    FROM
        datalake_velo.propose_person_legacy AS pp
    LEFT JOIN
        main_person AS mp
            ON mp.id_propose = pp.id_propose
    GROUP BY 1
),
credit_analysis AS (
    SELECT DISTINCT
        proposal_number AS id_propose,
        proposal_rating,
        analysis_result,
        serasa_score_hspn_api_v3_list,
        serasa_score_hspn_bureau,
        ts_operation,
        ROW_NUMBER() OVER (PARTITION BY proposal_number ORDER BY ts_operation DESC) AS rn
    FROM
        datalake_velo_neurotech_clean.logs_credit_granting
    WHERE 1=1
),
rescission AS (
    SELECT DISTINCT 
        id_propose
    FROM 
        datalake_rental_guarantee_platform_clean.delinquency
    WHERE 
        id_type = 2
        AND is_active
)

--query containing proposes from legacy table
SELECT DISTINCT
    p.id AS id_propose,
    pv.id_propose_values AS id_propose_values,
    p.id_quintocred_company AS id_broker,
    h.id_house * -1 AS id_house,
    p.realtor * -1 AS id_agent,
    pc.id_company AS id_propose_company,
    (mc.id_primary_person + 100) * -1 AS id_primary_person,
    jk1.id_junk AS id_origin,
    jk2.id_junk AS id_propose_status,
    CAST(NULL AS INT) AS id_guarantee_status,
    jk4.id_junk AS id_propose_type,
    pm.count_persons_included,
    CAST(NULL AS DECIMAL(38,6)) AS percentage_income_from_primary_person,
    CAST(NULL AS DECIMAL(14,4)) AS avg_serasa_score,
    CAST(NULL AS DOUBLE) AS avg_risk_score,
    CAST(NULL AS DECIMAL(38,22)) AS avg_declared_income,
    CAST(NULL AS DECIMAL(38,18)) total_declared_income,
    CAST(NULL AS DECIMAL(32,2)) AS dti,
    pym.total_paid_amount,
    pym.total_expected_amount,
    pym.total_due_amount,
    CAST(NULL AS DECIMAL(20,2)) AS total_occurrences_due_amount,
    CAST(NULL AS DECIMAL(22,2)) AS total_occurrences_paid_amount,
    pym.total_payments,
    pym.total_payments_paid,
    pym.total_payments_expired,
    CAST(NULL AS BIGINT) AS total_occurrences,
    CAST(NULL AS BIGINT) AS occurrences_solved,
    CASE
        WHEN ca.proposal_rating IS NULL OR ca.proposal_rating = 'NaN' THEN 'Missing'
        ELSE ca.proposal_rating
    END AS risk_category_neurotech,
    CASE
        WHEN CAST(ca.ts_operation AS TIMESTAMP) BETWEEN CAST('2024-03-15 00:00:00.000' AS TIMESTAMP) AND CAST('2024-03-18 18:30:00.000' AS TIMESTAMP) OR CAST(ca.ts_operation AS TIMESTAMP) >= CAST('2024-05-09 00:00:00.000' AS TIMESTAMP) THEN CAST(ARRAY_MAX(ca.serasa_score_hspn_api_v3_list) AS BIGINT)
        ELSE CAST(ARRAY_MAX(ca.serasa_score_hspn_bureau) AS BIGINT)
    END AS max_hspn,
    CASE
        WHEN CAST(ca.ts_operation AS TIMESTAMP) BETWEEN CAST('2024-03-15 00:00:00.000' AS TIMESTAMP) AND CAST('2024-03-18 18:30:00.000' AS TIMESTAMP) OR CAST(ca.ts_operation AS TIMESTAMP) >= CAST('2024-05-09 00:00:00.000' AS TIMESTAMP) THEN CAST(ARRAY_MIN(ca.serasa_score_hspn_api_v3_list) AS BIGINT)
        ELSE CAST(ARRAY_MIN(ca.serasa_score_hspn_bureau) AS BIGINT)
    END AS min_hspn,
    CASE
        WHEN ca.analysis_result = 'A' THEN '1)Aprovação automática'
        WHEN ca.analysis_result = 'REANALISE' THEN '2)Mesa'
        WHEN ca.analysis_result IN ('REPROVADO', 'REPROVADO - BACKGROUND') THEN '5)Clear No'
        WHEN ca.analysis_result = 'RESSUBMISSAO' THEN 'Solicitado reenvio'
        WHEN ca.analysis_result = 'FINALIZADO' THEN '3)Enviar DOC de Renda'
        WHEN ca.analysis_result = 'AD PROP' THEN '4)Adicionar Proponents'
        ELSE ca.analysis_result
    END AS last_analysis_result,
    old.id_contract IS NOT NULL AS is_contract,
    FALSE AS is_direct_billing,
    IFNULL(DATEDIFF(old.dt_ended, DATE(old.dt_contract_started)) <= 10, False) AS is_grace_period_cancelled,
    TRUE AS is_legacy,
    FALSE AS is_3p,
    pym.dt_last_payment,
    old.dt_contract_started AS dt_contract_started,
    old.dt_ended AS dt_ended,
    old.dt_analyst_annulment_input AS dt_analyst_annulment_input,
    IF(
        r.id_propose IS NULL,
        old.dt_ended,
        old.dt_analyst_annulment_input 
    ) AS dt_ended_official,
    COALESCE(p.ts_inserted, old.ts_propose_started) AS ts_propose_started,
    old.ts_waiting_new_docs AS ts_waiting_new_docs,
    old.ts_evaluation_started AS ts_evaluation_started,
    old.ts_rejected AS ts_rejected,
    old.ts_sign_started AS ts_sign_started,
    old.ts_signed AS ts_signed,
    old.ts_paid AS ts_paid,
    old.ts_activation AS ts_activation,
    old.ts_secured AS ts_secured,
    old.ts_activation_analysis AS ts_activation_analysis,
    old.ts_secure_pending AS ts_secure_pending
FROM
    datalake_rental_guarantee_platform_clean.fiancavelo_propose_legacy AS p
LEFT JOIN
    datalake_rental_guarantee_platform_clean.propose_status AS ps
        ON p.id_quintocred_status = ps.id
LEFT JOIN
    old_house AS h
        ON h.id_propose = p.id
        AND h.rn = 1 -- Gets only the latest updated id
LEFT JOIN
    old_main_client AS mc
        ON mc.id_propose = p.id
        AND mc.rn = 1 -- Gets only the latest updated id
LEFT JOIN
    old_payments_metrics AS pym
        ON pym.id_propose = p.id
LEFT JOIN
    propose_company AS pc
        ON pc.id_propose = p.id
        AND pc.rn = 1
LEFT JOIN
    datalake_velo.junk AS jk1
        ON jk1.id_lvl_1 = IF(pc.id_propose IS NOT NULL, 1, 2)
        AND jk1.desc_master_type = 'Origin'
LEFT JOIN
    datalake_velo.junk AS jk2
        ON jk2.desc_lvl_1 = ps.name
        AND jk2.desc_master_type = 'Propose Status'
LEFT JOIN
    datalake_rental_guarantee_platform_clean.bussines_type AS pbt
    ON pbt.id = p.id_business_type
LEFT JOIN
    datalake_velo.junk AS jk4
        ON jk4.desc_lvl_1 = pbt.name
        AND jk4.desc_master_type = 'Propose Type'
LEFT JOIN
    old_prop_values AS pv
        ON pv.id_propose = p.id
LEFT JOIN
    old_system_dates AS old
        ON old.id_propose = p.id
LEFT JOIN
    persons_metrics AS pm
        ON pm.id_propose = p.id
LEFT JOIN
    credit_analysis AS ca
        ON ca.id_propose = p.id
        AND ca.rn = 1
LEFT JOIN 
    rescission as r
        ON p.id = r.id_propose
WHERE
    p.id NOT IN (SELECT id FROM datalake_rental_guarantee_platform_clean.propose)
