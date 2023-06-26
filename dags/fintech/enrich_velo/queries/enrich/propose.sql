WITH new_system AS (

        WITH propose_canceled_date AS (
        SELECT
            id_propose,
            MAX(CAST(ts_updated AS TIMESTAMP)) AS ts_ended
        FROM
            datalake_rental_guarantee_platform_clean.propose_history
        WHERE
            value IN ('Contrato Cancelado', 'Proposta Cancelada')
            AND id_history_type = 5 -- Status update type
        GROUP BY
            1 -- some proposes can have multiple same status
        ),
        propose_waiting_new_docs_date AS (
        SELECT
            id_propose,
            MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_waiting_new_docs
        FROM
            datalake_rental_guarantee_platform_clean.propose_history
        WHERE
            value IN ('Mais documentos', 'Mais proponentes')
            AND id_history_type = 5 -- Status update type
        GROUP BY
            1 -- some proposes can have multiple same status
        ),
        propose_evaluation_started_date AS (
            WITH cte_propose_history AS (
                SELECT
                    id_propose,
                    MIN(ts_updated) AS ts_evaluation_started
                FROM datalake_rental_guarantee_platform_clean.propose_history
                WHERE value NOT IN ('Rascunho', 'Proposta Cancelada')
                AND id_history_type = 5
                GROUP BY 1
            ),
            cte_propose_aud AS (
                SELECT
                    p.id AS id_propose,
                    MIN(ts_created) AS ts_evaluation_started
                FROM
                    datalake_rental_guarantee_platform_clean.propose_aud AS p
                LEFT JOIN
                    datalake_rental_guarantee_platform_clean.rev_info AS r
                    ON r.rev = p.rev
                LEFT JOIN
                    datalake_rental_guarantee_platform_clean.propose_status AS ps
                    ON ps.id = p.id_propose_status
                WHERE
                    ps.name NOT IN ('Rascunho', 'Proposta Cancelada')
                GROUP BY 1
            )
        SELECT
            COALESCE(a.id_propose, ph.id_propose) AS id_propose,
            COALESCE(a.ts_evaluation_started, ph.ts_evaluation_started) AS ts_evaluation_started
        FROM
            cte_propose_aud AS a
        FULL OUTER JOIN
            cte_propose_history AS ph
            ON ph.id_propose = a.id_propose
        ),
        propose_rejected_date AS (
        SELECT
            id_propose,
            MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_rejected
        FROM
            datalake_rental_guarantee_platform_clean.propose_history
        WHERE
            value IN ('Reprovado pelo analista','Reprovado na análise humanizada')
            AND id_history_type = 5 -- Status update type
        GROUP BY
            1 -- some proposes can have multiple same status
        ),
        propose_sign_started_date AS (
        SELECT
            id_propose,
            MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_sign_started
        FROM
            datalake_rental_guarantee_platform_clean.propose_history
        WHERE
            value IN ('Aprovada pelo analista','Análise aprovada')
            AND id_history_type = 5 -- Status update type
        GROUP BY
            1 -- some proposes can have multiple same status
        ),
        propose_signed_date AS (
        SELECT
            id_propose,
            MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_signed
        FROM
            datalake_rental_guarantee_platform_clean.propose_history
        WHERE
            value IN ('Contrato Assinado mas não pago')
            AND id_history_type = 5 -- Status update type
        GROUP BY
            1 -- some proposes can have multiple same status
        ),
        propose_paid_date AS (
        SELECT
            id_propose,
            MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_paid
        FROM
            datalake_rental_guarantee_platform_clean.propose_history
        WHERE
            value IN ('Contrato pago mas não assinado','Contrato assinado e pago')
            AND id_history_type = 5 -- Status update type
        GROUP BY
            1 -- some proposes can have multiple same status
        ),
        propose_activation_date AS (
        SELECT
            id_propose,
            MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_activation
        FROM
            datalake_rental_guarantee_platform_clean.propose_history
        WHERE
            value = 'Contrato assinado e pago'
            AND id_history_type = 5 -- Status update type
        GROUP BY
            1 -- some proposes can have multiple same status
        ),
        propose_secured_date AS (
        SELECT
            id_propose,
            MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_secured
        FROM
            datalake_rental_guarantee_platform_clean.propose_history
        WHERE
            value = 'Contrato aprovado'
            AND id_history_type = 5 -- Status update type
        GROUP BY
            1 -- some proposes can have multiple same status
        ),
        propose_activation_analysis_date AS (
        SELECT
            id_propose,
            MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_activation_analysis
        FROM
            datalake_rental_guarantee_platform_clean.propose_history
        WHERE
            value = 'Análise humana do contrato de locação'
            AND id_history_type = 5 -- Status update type
        GROUP BY
            1 -- some proposes can have multiple same status
        ),
        propose_secure_pending_date AS (
        SELECT
            id_propose,
            MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_secure_pending
        FROM
            datalake_rental_guarantee_platform_clean.propose_history
        WHERE
            value = 'Reenviar contrato de aluguel'
            AND id_history_type = 5 -- Status update type
        GROUP BY
            1 -- some proposes can have multiple same status
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
        prop_values AS (
            SELECT
                p.id AS id_propose,
                CONCAT(p.id, cp.id, pl.id) AS id_propose_values,
                COALESCE((pv.rent_amount + pv.condo_amount + pv.light_amount + pv.iptu_amount + pv.other_amount)*pl.pricing,0) AS monthly_guarantee
            FROM
                datalake_rental_guarantee_platform_clean.propose AS p
            LEFT JOIN
                datalake_rental_guarantee_platform_clean.company_plan AS cp
                    ON p.id_company_plan = cp.id
            LEFT JOIN
                datalake_rental_guarantee_platform_clean.plan AS pl
                    ON cp.id_plan = pl.id
            LEFT JOIN
                prop_values_structure AS pv
                    ON p.id = pv.id_propose
            WHERE
                p.id >= 5000000
        ),
        main_person AS (
            SELECT
                id_person,
                id_propose,
                declared_income
            FROM
                datalake_velo.propose_person
            WHERE
                is_legacy IS FALSE
                AND is_primary_person IS TRUE
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
                datalake_velo.propose_person AS pp
            LEFT JOIN
                main_person AS mp
                ON mp.id_propose = pp.id_propose
            WHERE
                pp.is_legacy IS FALSE
            GROUP BY 1
        ),
        payments_metrics AS (
            SELECT
                id_propose,
                SUM(IF(dt_paid IS NOT NULL, due_amount, 0)) AS total_paid_amount,
                SUM(due_amount) AS total_expected_amount,
                SUM(IF(dt_paid IS NULL, due_amount, 0)) AS total_due_amount,
                -- CAST(NULL AS DOUBLE) AS lmi,
                COUNT(id_payment) AS total_payments,
                COUNT(IF(dt_paid IS NOT NULL, 1, 0)) AS total_payments_paid,
                COUNT(IF(dt_paid IS NULL AND dt_due < current_date(), 1, 0)) AS total_payments_expired,
                MAX(dt_paid) AS dt_last_payment
            FROM
                datalake_velo.payment
            WHERE
                is_legacy IS FALSE
            GROUP BY 1
        ),
        occurrence_metrics AS (
            SELECT
                id_propose,
                SUM(IF(paid_amount IS NOT NULL, paid_amount, 0)) AS total_occurrences_paid_amount,
                SUM(due_amount) AS total_occurrences_due_amount,
                COUNT(id_occurrence) AS total_occurrences,
                COUNT(ts_paid) AS occurrences_solved
            FROM
                datalake_velo.occurrence AS o
            WHERE
                is_legacy IS FALSE
            GROUP BY 1
        ),
        property_propose AS (
            SELECT
                id_propose,
                id
            FROM
                datalake_rental_guarantee_platform_clean.property_propose
            QUALIFY
                ROW_NUMBER() OVER (PARTITION BY id_propose ORDER BY ts_updated DESC) = 1
        ),
        3p_proposes AS (
            SELECT
                pr.id AS id_propose
            FROM
                datalake_rental_guarantee_platform_clean.propose AS pr
            LEFT JOIN
                datalake_rental_guarantee_platform_clean.company_plan AS cp
                ON pr.id_company_plan = cp.id
            LEFT JOIN
                datalake_rental_guarantee_platform_clean.plan AS pl
                ON cp.id_plan = pl.id
            WHERE
                pl.plan_name LIKE '%3P%'
        )
        SELECT
            p.id AS id_propose,
            pv.id_propose_values AS id_propose_values,
            p.id_real_estate AS id_broker,
            pp.id + 5000000 AS id_house,
            ua.id AS id_agent,
            c.id AS id_contract,
            p.id_tenant_company + 5000000 AS id_propose_company,
            mp.id_person AS id_primary_person,
            jk1.id_junk AS id_origin,
            jk2.id_junk AS id_propose_status,
            NULL AS id_guarantee_status, -- TODO: Avaliar se já está no propose_status mesmo
            NULL AS id_propose_type,
            pm.count_persons_included,
            pm.percentage_income_from_primary_person,
            pm.avg_serasa_score,
            pm.avg_risk_score,
            pm.avg_declared_income,
            pm.total_declared_income,
            CAST(pv.monthly_guarantee / pm.total_declared_income AS DECIMAL(32,2)) AS dti,
            pym.total_paid_amount,
            pym.total_expected_amount,
            pym.total_due_amount,
            om.total_occurrences_due_amount,
            om.total_occurrences_paid_amount,
            pym.total_payments,
            pym.total_payments_paid,
            pym.total_payments_expired,
            om.total_occurrences,
            om.occurrences_solved,
            c.id IS NOT NULL AS is_contract,
            IFNULL(DATEDIFF(COALESCE(DATE(pcd.ts_ended), c.ts_done), DATE(c.ts_began)) <= 10, FALSE) AS is_grace_period_cancelled,
            FALSE AS is_legacy,
            IF(3p.id_propose IS NULL, FALSE, TRUE) AS is_3p,
            pym.dt_last_payment,
            DATE(c.ts_began) AS dt_contract_started,
            COALESCE(DATE(pcd.ts_ended), c.ts_done) AS dt_ended,
            p.ts_inserted AS ts_propose_started,
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
            datalake_rental_guarantee_platform_clean.propose AS p
        LEFT JOIN
            property_propose AS pp
            ON p.id = pp.id_propose
        LEFT JOIN
            datalake_rental_guarantee_platform_clean.contract AS c
            ON p.id = c.id_propose
        LEFT JOIN
            datalake_rental_guarantee_platform_clean.propose_status AS ps
            ON p.id_propose_status = ps.id
        LEFT JOIN
            propose_canceled_date AS pcd
                ON pcd.id_propose = p.id
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
        LEFT JOIN
            main_person AS mp
                ON p.id = mp.id_propose
        LEFT JOIN
            datalake_velo.junk AS jk1
            ON jk1.id_lvl_1 = IF(p.id_tenant_company IS NOT NULL, 1, 2)
                AND jk1.desc_master_type = 'Origin'
        LEFT JOIN
            datalake_velo.junk AS jk2
            ON jk2.desc_lvl_1 = ps.name
                AND jk2.desc_master_type = 'Propose Status'
        LEFT JOIN
            datalake_rental_guarantee_platform_clean.contract_status AS cts
            ON cts.id = c.id_status
        LEFT JOIN
            datalake_velo.junk AS jk3
            ON jk3.desc_lvl_1 = cts.name
                AND jk3.desc_master_type = 'Guarantee Status'
        LEFT JOIN
            datalake_rental_guarantee_platform_clean.user_account AS ua
            ON ua.uuid_person = p.realtor
        LEFT JOIN
        prop_values AS pv
            ON pv.id_propose = p.id
        lEFT JOIN
        persons_metrics AS pm
            ON pm.id_propose = p.id
        lEFT JOIN
        payments_metrics AS pym
            ON pym.id_propose = p.id
        lEFT JOIN
        occurrence_metrics AS om
            ON om.id_propose = p.id
        lEFT JOIN
        3p_proposes AS 3p
            ON 3p.id_propose = p.id
),
old_system AS (
    WITH propose_canceled_date AS (
    SELECT
        id_propose,
        MAX(CAST(ts_updated AS TIMESTAMP)) AS ts_ended
    FROM
        datalake_velo_clean.fiancavelo_proposehistory
    WHERE
        id_text_key = 10 --10 indicates that the propose has ended
        AND id_type_history = 1 -- alteration by the system
    GROUP BY
        1 -- some proposes can have multiple same status
    ),
    propose_started_date AS (
    SELECT
        id_propose,
        MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_propose_started
    FROM
        datalake_velo_clean.fiancavelo_proposehistory
    WHERE
        id_text_key = 2 --2 indicates that the propose has started
        AND id_type_history = 1 -- alteration by the system
    GROUP BY
        1 -- some proposes can have multiple same status
    ),
    propose_waiting_new_docs_date AS (
    SELECT
        id_propose,
        MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_waiting_new_docs
    FROM
        datalake_velo_clean.fiancavelo_proposehistory
    WHERE
        id_text_key = 3 -- indicates that the propose is waiting for more docs
        AND id_type_history = 1 -- alteration by the system
    GROUP BY
        1 -- some proposes can have multiple same status
    ),
    propose_evaluation_started_date AS (
    SELECT
        id_propose,
        MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_evaluation_started
    FROM
        datalake_velo_clean.fiancavelo_proposehistory
    WHERE
        id_text_key > 2
        AND id_text_key < 10
        AND id_type_history = 1 -- alteration by the system
    GROUP BY
        1 -- some proposes can have multiple same status
    ),
    propose_rejected_date AS (
    SELECT
        id_propose,
        MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_rejected
    FROM
        datalake_velo_clean.fiancavelo_proposehistory
    WHERE
        id_text_key = 5 -- indicates that the propose was rejected
        AND id_type_history = 1 -- alteration by the system
    GROUP BY
        1 -- some proposes can have multiple same status
    ),
    propose_sign_started_date AS (
    SELECT
        id_propose,
        MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_sign_started
    FROM
        datalake_velo_clean.fiancavelo_proposehistory
    WHERE
        id_text_key = 6 -- indicates that the sign has started
        AND id_type_history = 1 -- alteration by the system
    GROUP BY
        1 -- some proposes can have multiple same status
    ),
    propose_signed_date AS (
        SELECT
            id_propose,
            MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_signed
        FROM
            datalake_velo_clean.fiancavelo_proposehistory
        WHERE
            id_text_key = 7 -- indicates that the propose has been paid
            AND id_type_history = 1 -- alteration by the system
        GROUP BY
            1 -- some proposes can have multiple same status
    ),
    propose_paid_date AS (
    SELECT
        id_propose,
        MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_paid
    FROM
        datalake_velo_clean.fiancavelo_proposehistory
    WHERE
        id_text_key = 8 -- indicates that the propose has been paid
        AND id_type_history = 1 -- alteration by the system
    GROUP BY
        1 -- some proposes can have multiple same status
    ),
    propose_activation_date AS (
    SELECT
        id_propose,
        MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_activation
    FROM
        datalake_velo_clean.fiancavelo_proposehistory
    WHERE
        id_text_key = 8 -- indicates that the propose is active
        AND id_type_history = 1 -- alteration by the system
    GROUP BY
        1 -- some proposes can have multiple same status
    ),
    propose_secured_date AS (
    SELECT
        id_propose,
        MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_secured
    FROM
        datalake_velo_clean.fiancavelo_proposehistory
    WHERE
        id_text_key = 9 -- indicates that the propose is secured
        AND id_type_history = 1 -- alteration by the system
    GROUP BY
        1 -- some proposes can have multiple same status
    ),
    propose_activation_analysis_date AS (
    SELECT
        id_propose,
        MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_activation_analysis
    FROM
        datalake_velo_clean.fiancavelo_proposehistory
    WHERE
        id_text_key = 11 -- indicates that the propose is active but in analysis
        AND id_type_history = 1 -- alteration by the system
    GROUP BY
        1 -- some proposes can have multiple same status
    ),
    propose_secure_pending_date AS (
    SELECT
        id_propose,
        MIN(CAST(ts_updated AS TIMESTAMP)) AS ts_secure_pending
    FROM
        datalake_velo_clean.fiancavelo_proposehistory
    WHERE
        id_text_key = 12 -- indicates that the propose is waiting to be secured
        AND id_type_history = 1 -- alteration by the system
    GROUP BY
        1 -- some proposes can have multiple same status
    ),
    propose_company AS (
    SELECT
        id_propose,
        id_company,
        ROW_NUMBER() OVER(PARTITION BY id_propose ORDER BY ts_updated DESC) AS rn
    FROM
        datalake_velo_clean.fiancavelo_proposecompany
    ),
    house AS (
    SELECT
        o.id_propose AS id_propose,
        py.id AS id_house,
        ROW_NUMBER() OVER (PARTITION BY o.id_propose ORDER BY o.ts_updated DESC, o.id_property DESC) AS rn -- House update order, there was a bug in product that created a new id for every update. To solve, order by the latest update date.
    FROM
        datalake_velo_clean.fiancavelo_object AS o
    LEFT JOIN
        datalake_velo_clean.fiancavelo_property AS py
        ON py.id = o.id_property
            AND py.is_active
    WHERE
        o.is_active
    ),
    pack_values AS (
    SELECT
        pk.id_propose AS id_propose,
        SUM(COALESCE(pk.value,0)) AS total_package_amount
    FROM
        datalake_velo_clean.fiancavelo_packvalues AS pk
    WHERE
        pk.is_active
    GROUP BY
        1
    ),
    propose_values AS (
    SELECT
        CONCAT(p.id, a.id, pl.id) AS id_propose_values,
        p.id AS id_propose,
        plt.name AS plan_type,
        COALESCE(pk.total_package_amount*pl.percent*0.01,0) AS monthly_guarantee
    FROM
        datalake_velo_clean.fiancavelo_propose AS p
    LEFT JOIN
        datalake_velo_clean.fiancavelo_activator AS a
        ON a.id = p.id_activator
    LEFT JOIN
        datalake_velo_clean.fiancavelo_plans AS pl
        ON pl.id = p.id_plan
    LEFT JOIN
        datalake_velo_clean.fiancavelo_plantype AS plt
        ON plt.id = pl.id_type
        AND plt.is_active
    LEFT JOIN
        pack_values AS pk
        ON pk.id_propose = p.id
    ),
    person_score AS (
    SELECT
        c.id AS id_score_consultation,
        c.id_person,
        c.value AS score_value,
        c.risk,
        r.name AS risk_classification,
        c.id_bureau,
        b.name AS bureau_name,
        vp.value AS score_personal_value,
        vp.declared AS declared_income,
        vp.requested AS requested_income,
        ROW_NUMBER() OVER(PARTITION BY c.id_person ORDER BY c.ts_updated DESC, c.ts_inserted DESC) AS rn
    FROM
        datalake_velo_clean.veloscore_consultations AS c
    LEFT JOIN
        datalake_velo_clean.veloscore_bureau AS b
        ON b.id = c.id_bureau
    LEFT JOIN
        datalake_velo_clean.veloscore_personal AS vp
        ON vp.consultations = c.id
    LEFT JOIN
        datalake_velo_clean.veloscore_risk AS r
        ON r.id = c.risk
    ),
    main_client AS (
    SELECT
        pp.id_propose,
        pp.id_person AS id_primary_person,
        prs.declared_income,
        ROW_NUMBER() OVER(PARTITION BY pp.id_propose ORDER BY pp.ts_updated DESC) AS rn
        FROM
        datalake_velo_clean.fiancavelo_proposeperson AS pp
        LEFT JOIN
            person_score AS prs
            ON prs.id_person = pp.id_person
            AND prs.rn = 1
        WHERE
        pp.is_active
            AND pp.id_type = 1 -- bringing only main IQ
    ),
    persons_metrics AS (
    SELECT
        pp.id_propose,
        MAX(mc.declared_income) / SUM(prs.declared_income) AS percentage_income_from_primary_person,
        COUNT(cp.id) AS count_persons_included,
        AVG(prs.score_value) AS avg_serasa_score,
        AVG(prs.risk) AS avg_risk_score,
        AVG(prs.declared_income) AS avg_declared_income,
        SUM(prs.declared_income) AS total_declared_income
    FROM
        datalake_velo_clean.fiancavelo_proposeperson AS pp
    LEFT JOIN
        datalake_velo_clean.clientes_person AS cp
        ON cp.id = pp.id_person
    LEFT JOIN
        person_score AS prs
        ON prs.id_person = cp.id
            AND prs.rn = 1
    LEFT JOIN
        main_client AS mc
        ON mc.id_propose = pp.id_propose
        AND mc.rn = 1
    GROUP BY 1
    ),
    payments_metrics AS (
    SELECT
        id_propose,
        SUM(IF(dt_paid IS NOT NULL, due_amount, 0)) AS total_paid_amount,
        SUM(due_amount) AS total_expected_amount,
        SUM(IF(dt_paid IS NULL, due_amount, 0)) AS total_due_amount,
        -- CAST(NULL AS DOUBLE) AS lmi,
        COUNT(id_payment) AS total_payments,
        COUNT(IF(dt_paid IS NOT NULL, 1, 0)) AS total_payments_paid,
        COUNT(IF(dt_paid IS NULL AND dt_due < current_date(), 1, 0)) AS total_payments_expired,
        MAX(dt_paid) AS dt_last_payment
    FROM
        datalake_velo.payment
    GROUP BY 1
    ),
    occurrence_metrics AS (
    SELECT
        id_propose,
        SUM(IF(paid_amount IS NOT NULL, paid_amount, 0)) AS total_occurrences_paid_amount,
        SUM(due_amount) AS total_occurrences_due_amount,
        COUNT(id_occurrence) AS total_occurrences,
        COUNT(ts_paid) AS occurrences_solved
    FROM
        datalake_velo.occurrence AS o
    GROUP BY 1
    ),
    fiancavelo_fianca_last_updated AS (
    SELECT *
    FROM
        datalake_velo_clean.fiancavelo_fianca AS f
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_propose ORDER BY ts_updated DESC) = 1
    )
    SELECT
    p.id AS id_propose,
    pv.id_propose_values AS id_propose_values,
    r.id_company AS id_broker,
    h.id_house,
    p.id_realtor AS id_agent,
    f.id AS id_contract,
    pc.id_company AS id_propose_company,
    mc.id_primary_person,
    jk4.id_junk AS id_origin,
    jk1.id_junk AS id_propose_status,
    jk2.id_junk AS id_guarantee_status,
    jk3.id_junk AS id_propose_type,
    pm.count_persons_included,
    pm.percentage_income_from_primary_person,
    pm.avg_serasa_score,
    pm.avg_risk_score,
    pm.avg_declared_income,
    pm.total_declared_income,
    CAST(pv.monthly_guarantee / pm.total_declared_income AS DECIMAL(32,2)) AS dti,
    pym.total_paid_amount,
    pym.total_expected_amount,
    pym.total_due_amount,
    -- pym.lmi,
    om.total_occurrences_due_amount,
    om.total_occurrences_paid_amount,
    pym.total_payments,
    pym.total_payments_paid,
    pym.total_payments_expired,
    om.total_occurrences,
    om.occurrences_solved,
    f.id IS NOT NULL AS is_contract,
    IFNULL(DATEDIFF(COALESCE(DATE(pcd.ts_ended), f.dt_ended), DATE(f.dt_begin)) <= 10, False) AS is_grace_period_cancelled,
    TRUE AS is_legacy,
    FALSE AS is_3p,
    pym.dt_last_payment,
    DATE(f.dt_begin) AS dt_contract_started,
    COALESCE(DATE(pcd.ts_ended), f.dt_ended) AS dt_ended,
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
    datalake_velo_clean.fiancavelo_propose AS p
    LEFT JOIN
    fiancavelo_fianca_last_updated AS f
        ON f.id_propose = p.id
    LEFT JOIN
    datalake_velo_clean.fiancavelo_colaborador AS c
        ON c.id_user = p.id_realtor
        AND c.id_realestate <> 0
    LEFT JOIN
    datalake_velo_clean.fiancavelo_realestate AS r
        ON COALESCE(f.id_realestate, c.id_realestate) = r.id
    LEFT JOIN
    propose_canceled_date AS pcd
        ON pcd.id_propose = p.id
    LEFT JOIN
    propose_company AS pc
        ON pc.id_propose = p.id
        AND pc.rn = 1
    lEFT JOIN
    persons_metrics AS pm
        ON pm.id_propose = p.id
    lEFT JOIN
    payments_metrics AS pym
        ON pym.id_propose = p.id
    lEFT JOIN
    occurrence_metrics AS om
        ON om.id_propose = p.id
    LEFT JOIN
        datalake_velo_clean.fiancavelo_proposestatus AS fps
        ON fps.id = p.id_status
    LEFT JOIN
    datalake_velo.junk AS jk1
        ON jk1.desc_lvl_1 = fps.name
        AND jk1.desc_master_type = 'Propose Status'
    LEFT JOIN
        datalake_velo_clean.fiancavelo_status AS ffs
        ON ffs.id = f.id_status
    LEFT JOIN
    datalake_velo.junk AS jk2
        ON jk2.desc_lvl_1 = ffs.name
        AND jk2.desc_master_type = 'Guarantee Status'
    LEFT JOIN
        datalake_velo_clean.fiancavelo_proposetype AS fpt
        ON fpt.id = p.id_type
    LEFT JOIN
    datalake_velo.junk AS jk3
        ON jk3.desc_lvl_1 = fpt.name
        AND jk3.desc_master_type = 'Propose Type'
    LEFT JOIN
    datalake_velo.junk AS jk4
        ON jk4.id_lvl_1 = IF(pc.id_propose IS NOT NULL, 1, 2)
        AND jk4.desc_master_type = 'Origin'
    LEFT JOIN
    house AS h
        ON h.id_propose = p.id
        AND h.rn = 1 -- Gets only the latest updated id
    LEFT JOIN
    propose_values AS pv
        ON pv.id_propose = p.id
    LEFT JOIN
    main_client AS mc
        ON mc.id_propose = p.id
        AND mc.rn = 1 -- Gets only the latest updated id
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
    WHERE
    p.is_active
),
cte_union AS (
(
    SELECT
        id_propose,
        id_propose_values,
        id_broker,
        id_house,
        id_agent,
        id_contract,
        id_propose_company,
        id_primary_person,
        id_origin,
        id_propose_status,
        id_guarantee_status,
        id_propose_type,
        count_persons_included,
        percentage_income_from_primary_person,
        avg_serasa_score,
        avg_risk_score,
        avg_declared_income,
        total_declared_income,
        dti,
        total_paid_amount,
        total_expected_amount,
        total_due_amount,
        total_occurrences_due_amount,
        total_occurrences_paid_amount,
        total_payments,
        total_payments_paid,
        total_payments_expired,
        total_occurrences,
        occurrences_solved,
        is_contract,
        is_grace_period_cancelled,
        is_legacy,
        is_3p,
        dt_last_payment,
        dt_contract_started,
        dt_ended,
        ts_propose_started,
        ts_waiting_new_docs,
        ts_evaluation_started,
        ts_rejected,
        ts_sign_started,
        ts_signed,
        ts_paid,
        ts_activation,
        ts_secured,
        ts_activation_analysis,
        ts_secure_pending
    FROM
        old_system
)
UNION ALL
(
    SELECT
        id_propose,
        id_propose_values,
        id_broker,
        id_house,
        id_agent,
        id_contract,
        id_propose_company,
        id_primary_person,
        id_origin,
        id_propose_status,
        id_guarantee_status,
        id_propose_type,
        count_persons_included,
        percentage_income_from_primary_person,
        avg_serasa_score,
        avg_risk_score,
        avg_declared_income,
        total_declared_income,
        dti,
        total_paid_amount,
        total_expected_amount,
        total_due_amount,
        total_occurrences_due_amount,
        total_occurrences_paid_amount,
        total_payments,
        total_payments_paid,
        total_payments_expired,
        total_occurrences,
        occurrences_solved,
        is_contract,
        is_grace_period_cancelled,
        is_legacy,
        is_3p,
        dt_last_payment,
        dt_contract_started,
        dt_ended,
        ts_propose_started,
        ts_waiting_new_docs,
        ts_evaluation_started,
        ts_rejected,
        ts_sign_started,
        ts_signed,
        ts_paid,
        ts_activation,
        ts_secured,
        ts_activation_analysis,
        ts_secure_pending
    FROM
        new_system
  WHERE
      id_propose >= 5000000
)
ORDER BY 1
)

SELECT
    id_propose,
    id_propose_values AS id_propose_values,
    id_broker,
    id_house,
    id_agent,
    id_contract,
    id_propose_company,
    id_primary_person,
    id_origin,
    id_propose_status,
    id_guarantee_status,
    id_propose_type,
    count_persons_included,
    percentage_income_from_primary_person,
    avg_serasa_score,
    avg_risk_score,
    avg_declared_income,
    total_declared_income,
    dti,
    total_paid_amount,
    total_expected_amount,
    total_due_amount,
    total_occurrences_due_amount,
    total_occurrences_paid_amount,
    total_payments,
    total_payments_paid,
    total_payments_expired,
    total_occurrences,
    occurrences_solved,
    is_contract,
    is_grace_period_cancelled,
    is_legacy,
    is_3p,
    dt_last_payment,
    dt_contract_started,
    dt_ended,
    ts_propose_started,
    ts_waiting_new_docs,
    ts_evaluation_started,
    ts_rejected,
    ts_sign_started,
    ts_signed,
    ts_paid,
    ts_activation,
    ts_secured,
    ts_activation_analysis,
    ts_secure_pending
FROM
    cte_union
