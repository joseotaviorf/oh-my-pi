WITH contract_termination AS (
    SELECT
        ct.id_termination,
        ct.id_contract,
        ct.ts_created,
        ct.dt_termination,
        ct.id_house_listing,
        ct.id_house,
        CAST(ct.has_one_year_fine AS INTEGER) AS has_one_year_fine,
        CASE
            WHEN ct.utility_bill_in_condominium IS NULL THEN 0
            WHEN CARDINALITY(SPLIT(ct.utility_bill_in_condominium, ',')) > 0 THEN 1
            ELSE 0
        END AS utility_bill_in_condominium,
        DATEDIFF(ct.dt_termination, COALESCE(ct.dt_contract_entrance, ct.dt_contract_started)) AS contract_lifetime
    FROM
        datalake_offboarding.contract_termination AS ct
    WHERE
        ct.status <> 'CANCELED'
        AND DATE(ct.ts_created) = DATE('{year}-{month}-{day}')
),
house_listing_fix AS (
    SELECT
        sk_contract,
        MAX(sk_house_listing) AS sk_house_listing
    FROM
        dw_public.fact_listing_rent_flows
    GROUP BY
        1
),
house_listing AS (
    SELECT DISTINCT
        ct.id_termination,
        CASE
            WHEN dhl.house_type = 'Apartamento' THEN 1
            ELSE 0
        END AS is_apartment,
        CASE
            WHEN dhl.house_entrance = 'horas24' THEN 1
            ELSE 0
        END AS has_24hdoorman,
        ROUND(dhl.house_total_value/nullif(dhl.house_total_area*1.0, 0), 2) AS house_total_value_per_m2,
        CAST(dhl.is_house_furnished AS INTEGER) AS is_house_furnished,
        CASE
            WHEN COALESCE(dam.maintenance_condition, 'NOT_SPECIFIED') = 'PERFECT_STATE' THEN 1
            ELSE 0
        END AS perfect_state_condition
    FROM
        contract_termination AS ct
    LEFT JOIN
        house_listing_fix AS fix
            ON fix.sk_contract = ct.id_contract
    LEFT JOIN
        dw_public.dim_house_listing AS dhl
            ON COALESCE(ct.id_house_listing, fix.sk_house_listing) = dhl.sk_house_listing
    LEFT JOIN
        datalake_ebdb_clean.house_maintenance_condition AS dam
            ON CAST(dam.id_house AS BIGINT) = dhl.id_house
),
base_comment AS (
    SELECT
        fib.sk_contract,
        MAX(CASE
                WHEN di.has_tenant_comment = True THEN 1
                ELSE 0
            END
        ) AS has_tenant_comment_inpection
    FROM
        dw_public.fact_inspection_bookings AS fib
    LEFT JOIN
        datalake_ebdb_listing_jobs.inspection AS di
            ON di.id = fib.sk_inspection
    WHERE
        di.type = 'Entrada'
    GROUP BY 1
),
base_comment_adj AS (
    SELECT
        ct.id_termination,
        COALESCE(com.has_tenant_comment_inpection, 0) AS has_tenant_comment_inpection
    FROM
        contract_termination AS ct
    LEFT JOIN
        base_comment AS com
            ON ct.id_contract = com.sk_contract
),
contract_hist AS (
    SELECT
        fcp.sk_personal_document,
        fcp.sk_contract,
        dc.ts_signature,
        fcp.contract_role,
        fcp.is_contract_user
    FROM
        dw_quintoandar.fact_contract_people AS fcp
    LEFT JOIN
        dw_public.dim_contract AS dc
            ON dc.sk_contract = fcp.sk_contract
),
tbl_first_contract AS (
    SELECT
        actual.sk_personal_document,
        actual.sk_contract,
        CASE
            WHEN COUNT(DISTINCT hist.sk_contract) > 1 THEN 0
            ELSE 1
        END AS first_contract
    FROM
        contract_hist AS actual
    LEFT JOIN
        contract_hist AS hist
            ON actual.sk_personal_document = hist.sk_personal_document
            AND hist.ts_signature <= actual.ts_signature
    GROUP BY
        actual.sk_personal_document,
        actual.sk_contract
),
tbl_actual_contracts AS (
    SELECT
        ct.id_contract,
        actual.contract_role,
        COUNT(DISTINCT CASE
                WHEN contract_hist.ts_signature >= actual.ts_signature THEN contract_hist.sk_contract
            END
        ) AS actual_contracts,
        COUNT(DISTINCT contract_hist.sk_contract) AS total_contracts
    FROM
        contract_termination AS ct
    LEFT JOIN
        contract_hist AS actual
            ON ct.id_contract = actual.sk_contract
    LEFT JOIN
        contract_hist
            ON contract_hist.sk_personal_document = actual.sk_personal_document
            AND contract_hist.ts_signature <= ct.ts_created
    WHERE
        actual.contract_role IN ('landlord')
    GROUP BY
        ct.id_contract,
        actual.contract_role
),
tbl_first_contracts_adjusted AS (
SELECT
    fcp.sk_contract,
    fcp.contract_role,
    COALESCE(
        MAX(
            CASE
                WHEN fcp.is_contract_user = True THEN tfc.first_contract
            END
        ),
        MAX(
            CASE
                WHEN fcp.is_contract_user <> True THEN tfc.first_contract
            END
        )
    ) AS first_contract
    FROM
        contract_hist AS fcp
    LEFT JOIN
        tbl_first_contract AS tfc
            ON tfc.sk_personal_document = fcp.sk_personal_document
            AND tfc.sk_contract = fcp.sk_contract
    WHERE
        fcp.contract_role IN ('landlord')
    GROUP BY
        fcp.sk_contract,
        fcp.contract_role
),
people AS (
    SELECT
        fcp.sk_contract,
        fcp.sk_contract_person,
        dcp.personal_document,
        fcp.contract_role,
        fcp.sk_user,
        dcp.phone_number,
        dcp.email,
        dc.ts_created
    FROM
        dw_quintoandar.fact_contract_people AS fcp
    LEFT JOIN
        dw_quintoandar.dim_contract_person AS dcp
            ON dcp.sk_contract_person = fcp.sk_contract_person
    LEFT JOIN
        dw_public.dim_contract AS dc
            ON dc.sk_contract = fcp.sk_contract
    WHERE
        fcp.contract_role IN ('tenant', 'landlord', 'dweller')
),
contract_people_togather AS (
    SELECT
        people.sk_contract,
        people.sk_contract_person,
        people.sk_user,
        people.contract_role
    FROM
        people
    WHERE
        people.sk_user <> -1
    UNION ALL
    SELECT
        people.sk_contract,
        people.sk_contract_person,
        cci.id_user AS sk_user,
        people.contract_role
    FROM
        people
    LEFT JOIN
        datalake_ebdb_customer_contact_identification.customer_contact_identification AS cci
            ON cci.cpf = people.personal_document
            AND cci.id_user IS NOT NULL
    WHERE
        people.sk_user = -1
    UNION ALL
    SELECT
        people.sk_contract,
        people.sk_contract_person,
        cci.id_user AS sk_user,
        people.contract_role
    FROM
        people
    LEFT JOIN
        datalake_ebdb_customer_contact_identification.customer_contact_identification AS cci
            ON cci.customer_contact = people.email
            AND cci.id_user IS NOT NULL
    WHERE
        people.sk_user = -1
    UNION ALL
    SELECT
        people.sk_contract,
        people.sk_contract_person,
        cci.id_user AS sk_user,
        people.contract_role
    FROM
        people
    LEFT JOIN
        datalake_ebdb_customer_contact_identification.customer_contact_identification AS cci
            ON cci.customer_contact = people.phone_number
            AND cci.id_user IS NOT NULL
    WHERE
        people.sk_user = -1
),
unique_users AS (
    SELECT DISTINCT
        clientes.sk_contract,
        clientes.sk_user,
        clientes.contract_role
    FROM
        contract_people_togather AS clientes
    WHERE
        clientes.contract_role IS NOT NULL
),
segments AS (
    SELECT
        sk_ticket,
        SUM(CASE
                WHEN transference_reason = 'wrong_queue' THEN 1
                ELSE 0
            END
        ) AS wrong_queue,
        SUM(CASE
                WHEN is_sla = false THEN 1
                ELSE 0
            END
        ) segments_not_sla
    FROM
        dw_customer_support.fact_segment
    GROUP BY
        1
),
tbl_final_tickets AS (
    SELECT
        ct.id_termination,
        unique_users.contract_role,
        COALESCE(
            SUM(CASE
                    WHEN dd.journey_step <> 'Cross' AND ft.front_or_back = 'back' THEN 1
                    ELSE 0
                END
            ), 0
        ) AS back_tickets_jornada,
        COALESCE(
            SUM(CASE
                    WHEN dd.journey_step <> 'Cross' AND dt.motivation = 'complaint' THEN 1
                    ELSE 0
                END
            ), 0
        ) AS complaint_tickets_jornada,
        COALESCE(
            SUM(CASE
                    WHEN dd.journey_step = 'Cross' THEN 1
                    ELSE 0
                END
            ), 0
        ) AS total_tickets_especiais,
        COALESCE(
            SUM(CASE
                    WHEN dd.journey_step <> 'Cross' AND ft.csat_score IN (1, 2) THEN 1
                    ELSE 0
                END
            ), 0
        ) AS csat_disatisfied_jornada,
        COALESCE(
            SUM(CASE
                    WHEN dd.journey_step <> 'Cross' AND ft.csat_score IN (4, 5) THEN 1
                    ELSE 0
                END
            ), 0
        ) AS csat_satisfied_jornada,
        COALESCE(
            SUM(CASE
                    WHEN dd.journey_step <> 'Cross' AND ft.front_or_back = 'front' THEN fs.segments_not_sla
                END
            ), 0
        ) AS total_segments_not_sla,
        COALESCE(
            SUM(CASE
                    WHEN dd.journey_step <> 'Cross' AND ft.front_or_back = 'front' THEN ft.total_segments
                END
            ), 0
        ) AS total_segments,
        COALESCE(
            AVG(CASE
                    WHEN dd.journey_step <> 'Cross' AND ft.front_or_back = 'front' THEN ft.total_minutes_talk_time
                END
            ), 0
        ) AS avg_minutes_talk_time,
        COALESCE(
            AVG(CASE
                    WHEN dd.journey_step <> 'Cross' AND ft.front_or_back = 'front' THEN ft.total_minutes_reception_time + ft.total_minutes_queue_time
                END
            ), 0
        ) AS avg_minutes_waiting_time,
        COALESCE(
            SUM(CASE
                    WHEN dd.journey_step <> 'Cross' THEN CAST(ft.resolution_survey AS INTEGER)
                    ELSE 0
                END
            ), 0
        ) AS resolution_survey_jornada,
        COALESCE(
            AVG(CASE
                    WHEN dd.journey_step <> 'Cross' AND ft.front_or_back = 'back' THEN zendesk.total_assignee_stations
                    ELSE 0
                END
            ), 0
        ) AS avg_assignee_stations
    FROM
        contract_termination AS ct
    LEFT JOIN
        unique_users
            ON unique_users.sk_contract = ct.id_contract
    LEFT JOIN
        dw_public.dim_contract AS dc
            ON dc.sk_contract = ct.id_contract
    LEFT JOIN
        dw_customer_support.fact_ticket AS ft
            ON unique_users.sk_user = ft.sk_user
    LEFT JOIN
        dw_customer_support.dim_taxonomy AS dt
            ON ft.sk_taxonomy = dt.sk_taxonomy
    LEFT JOIN
        dw_customer_support.dim_ticket_tags AS dtt
            ON dtt.sk_tags = ft.sk_tags
    LEFT JOIN
        segments AS fs
            ON fs.sk_ticket = ft.sk_ticket
    LEFT JOIN
        dw_customer_support.dim_department AS dd
            ON dd.sk_department = ft.sk_main_department
    LEFT JOIN
        dw_tickets.fact_tickets AS zendesk
            ON ft.sk_ticket = zendesk.sk_ticket
    WHERE
        dd.area = 'CX'
        AND dd.journey_step IN ('Onboarding', 'Ongoing', 'Cross')
        AND ft.ts_started >= dc.ts_created
        AND ft.ts_started <= ct.ts_created
        AND unique_users.contract_role = 'landlord'
    GROUP BY 1,2
),
repair_request AS (
   SELECT
    	rr.id AS sk_request,
    	rr.id_contract AS sk_contract,
    	ROW_NUMBER() OVER(PARTITION BY rr.id ORDER BY ts_updated desc) rn
    FROM
    	datalake_repairs_clean.repair_request AS rr
),
tbl_repair_request_adjusted AS (
    SELECT
        ct.id_termination,
        CAST(COUNT(DISTINCT rr.sk_request) > 0 AS INT) AS has_ongoing_repairs
    FROM
        contract_termination AS ct
    LEFT JOIN
        repair_request AS rr
            ON rr.sk_contract = ct.id_contract
    GROUP BY
        ct.id_termination
),
tbl_surveys_sent AS (
    SELECT
        ct.id_termination,
        ct.id_contract AS sk_contract,
        fnd.sk_nps_dispatch,
        fnd.score,
        fnd.is_answered,
        dd.date AS dt_survey_sent,
        ddd.date AS dt_nps_answered
    FROM
        contract_termination AS ct
    LEFT JOIN
        unique_users
            ON unique_users.sk_contract = ct.id_contract
    LEFT JOIN
        dw_tracksale.fact_nps_dispatches AS fnd
            ON fnd.sk_user = unique_users.sk_user
    LEFT JOIN
        dw_tracksale.dim_nps_campaign AS dnc
            ON dnc.sk_nps_campaign = fnd.sk_nps_campaign
    LEFT JOIN
        dw_public.dim_date AS dd
            ON dd.sk_date = fnd.sk_sent_date
    LEFT JOIN
        dw_public.dim_date AS ddd
            ON ddd.sk_date = fnd.sk_answered_date
    LEFT JOIN
        dw_public.dim_contract AS dc
            ON dc.sk_contract = ct.id_contract
    WHERE
        dnc.metric_group IN ('onboarding', 'ongoing', 'pponboarding', 'ppongoing', 'offboarding', 'ppoffboarding')
        AND dnc.customer_type IN ('PP')
        AND dd.date >= dc.ts_created
        AND dd.date <= ct.ts_created
        AND fnd.sk_sent_date IS NOT NULL
),
last_nps_answered AS (
    SELECT
        id_termination,
        CAST(score < 7 AS INT) AS last_nps_detractor
    FROM
        tbl_surveys_sent
    WHERE
        score IS NOT NULL
    QUALIFY ROW_NUMBER() OVER(PARTITION BY id_termination ORDER BY dt_nps_answered DESC) = 1
),
total_nps_answered AS (
    SELECT
        id_termination,
        SUM(CASE
                WHEN score BETWEEN 9 AND 10 THEN 1
                ELSE 0
            END
        ) AS total_nps_promotor,
        SUM(CASE
                WHEN score BETWEEN 0 AND 6 THEN 1
                ELSE 0
            END
        ) AS total_nps_detractor,
        CASE
            WHEN COUNT(sk_contract) > 0
                THEN SUM(
                    CASE
                        WHEN score > -1 THEN 1
                    END
                ) / COUNT(DISTINCT sk_nps_dispatch)
            ELSE 0.11
        END AS prob_answer_nps
    FROM
        tbl_surveys_sent
    GROUP BY
        1
),
pp_multi AS (
    SELECT DISTINCT
        dd.date,
        po.id_owner AS sk_user,
        CAST(po.is_pro_owner AS INTEGER) AS is_pro_owner
    FROM
        datalake_pro_owners.pro_owner_history AS po
    INNER JOIN
        dw_public.dim_date AS dd
            ON dd.date BETWEEN date(po.ts_pro_owner_started) AND coalesce(date(po.ts_pro_owner_ended),current_date - interval '1' day)
    LEFT JOIN
        dw_public.dim_user AS du
            ON po.id_owner = du.sk_user
    WHERE
        is_pro_owner = true
),
pp_multi_adjusted AS (
    SELECT
        ct.id_termination,
        CASE
            WHEN COALESCE(SUM(pp_multi.is_pro_owner), 0) > 0 THEN 1
            ELSE 0
        END AS is_pro_owner
    FROM
        contract_termination AS ct
    LEFT JOIN
        unique_users
            ON unique_users.sk_contract = ct.id_contract
    LEFT JOIN
        pp_multi
            ON unique_users.sk_user = pp_multi.sk_user
            AND CAST(ct.ts_created AS DATE) = pp_multi.date
    GROUP BY
        ct.id_termination
)
SELECT
    ct.id_termination,
    ct.id_contract,
    ct.id_house,
    'offboarding_landlord' AS model_name,
    'nps_reversion_off_landlord_rf_v0' AS model_version,
    DATE(ct.ts_created) AS dt_termination_request,
    ct.dt_termination,
    ct.has_one_year_fine,
    ct.utility_bill_in_condominium,
    ct.contract_lifetime,
    hl.has_24hdoorman,
    hl.house_total_value_per_m2,
    hl.is_house_furnished,
    hl.is_apartment,
    hl.perfect_state_condition,
    bca.has_tenant_comment_inpection,
    tra.has_ongoing_repairs,
    COALESCE(tfca.first_contract, 0) AS first_contract,
    CASE
        WHEN tac.actual_contracts > 1 THEN 1
        ELSE 0
    END AS actual_contracts,
    COALESCE(tac.total_contracts, 0) AS total_contracts,
    COALESCE(tft.back_tickets_jornada, 0) AS back_tickets_jornada,
    CASE
        WHEN tft.complaint_tickets_jornada > 0 THEN 1
        ELSE 0
    END AS complaint_tickets_jornada,
    CASE
        WHEN tft.total_tickets_especiais > 0 THEN 1
        ELSE 0
    END AS total_tickets_especiais,
    COALESCE(tft.csat_disatisfied_jornada, 0) AS csat_disatisfied_jornada,
    COALESCE(tft.csat_satisfied_jornada, 0) AS csat_satisfied_jornada,
    COALESCE(tft.total_segments_not_sla, 0) AS total_segments_not_sla,
    COALESCE(tft.total_segments, 0) AS total_segments,
    COALESCE(tft.avg_minutes_talk_time, 0) AS avg_minutes_talk_time,
    COALESCE(tft.avg_minutes_waiting_time, 0) AS avg_minutes_waiting_time,
    COALESCE(tft.resolution_survey_jornada, 0) AS resolution_survey_jornada,
    COALESCE(tft.avg_assignee_stations, 0) AS avg_assignee_stations,
    COALESCE(nps.total_nps_promotor, 0) AS total_nps_promotor,
    COALESCE(nps.total_nps_detractor, 0) AS total_nps_detractor,
    COALESCE(nps.prob_answer_nps, 0.11) AS prob_answer_nps,
    COALESCE(tbl_last.last_nps_detractor, 0) AS last_nps_detractor,
    COALESCE(pma.is_pro_owner, 0) AS is_pro_owner
FROM
    contract_termination ct
LEFT JOIN
    house_listing AS hl
        ON hl.id_termination = ct.id_termination
LEFT JOIN
    base_comment_adj AS bca
        ON bca.id_termination = ct.id_termination
LEFT JOIN
    tbl_repair_request_adjusted AS tra
        ON tra.id_termination = ct.id_termination
LEFT JOIN
    tbl_first_contracts_adjusted AS tfca
        ON ct.id_contract = tfca.sk_contract
LEFT JOIN
    tbl_actual_contracts AS tac
        ON tac.id_contract = ct.id_contract
LEFT JOIN
    tbl_final_tickets AS tft
        ON tft.id_termination = ct.id_termination
LEFT JOIN
    total_nps_answered AS nps
        ON nps.id_termination = ct.id_termination
LEFT JOIN
    last_nps_answered AS tbl_last
        ON tbl_last.id_termination = ct.id_termination
LEFT JOIN
    pp_multi_adjusted AS pma
        ON pma.id_termination = ct.id_termination
WHERE
    pma.is_pro_owner = 0
    AND tac.total_contracts IS NOT NULL
