WITH contract_termination AS (
    SELECT
        ct.id_termination,
        ct.id_contract,
        ct.id_house,
        ct.id_house_listing,
        ct.ts_created,
        CASE
            WHEN ct.reason = 'DISLIKES_QUINTOANDAR' THEN 1
            ELSE 0
        END AS reason_DISLIKES_QUINTOANDAR,
        CASE
            WHEN ct.reason = 'PROBLEMS_WITH_HOUSE' THEN 1
            ELSE 0
        END AS reason_PROBLEMS_WITH_HOUSE,
        CASE
            WHEN ct.reason = 'NEEDS_CHANGE' THEN 1
            ELSE 0
        END AS reason_NEEDS_CHANGE,
        CASE
            WHEN ct.reason = 'MOVING_OWN_HOUSE' THEN 1
            ELSE 0
        END AS reason_MOVING_OWN_HOUSE,
        CASE
            WHEN ct.reason = 'OTHER' THEN 1
            ELSE 0
        END AS reason_OTHER,
        CASE
            WHEN ct.reason = 'JOB_TRANSFER' THEN 1
            ELSE 0
        END AS reason_JOB_TRANSFER,
        CASE
            WHEN ct.reason = 'MOVING_TO_FRIENDS_OR_FAMILY' THEN 1
            ELSE 0
        END AS reason_MOVING_TO_FRIENDS_OR_FAMILY,
        CASE
            WHEN ct.has_one_year_fine = false AND ct.has_prior_notice_fine = true THEN 1
            ELSE 0
        END AS type_of_termination_fine_WITHOUT_NOTICE,
        ct.dt_termination
    FROM
        datalake_offboarding.contract_termination AS ct
    WHERE
        ct.status <> 'CANCELED'
        AND DATE(ct.ts_created) = DATE('{year}-{month}-{day}')
),
dim_contract AS (
    SELECT
        ct.id_termination,
        dc.ts_created,
        CASE
            WHEN DATEDIFF(ct.dt_termination, COALESCE(dc.dt_entrance, dc.dt_start)) > 1100 THEN 1100
            WHEN DATEDIFF(ct.dt_termination, COALESCE(dc.dt_entrance, dc.dt_start)) IS NULL THEN 378
            ELSE DATEDIFF(ct.dt_termination, COALESCE(dc.dt_entrance, dc.dt_start))
        END AS contract_lifetime
    FROM
        contract_termination AS ct
    LEFT JOIN
        dw_rent.dim_contract AS dc
            ON dc.sk_contract = ct.id_contract
),
dim_house_listing AS (
    SELECT
        ct.id_termination,
        dhl.house_bedrooms,
        CASE
            WHEN dhl.house_type = 'Casa' THEN 1
            ELSE 0
        END AS house_type_Casa
    FROM
        contract_termination AS ct
    LEFT JOIN
        dw_rent.dim_house_listing AS dhl
            ON ct.id_house_listing = dhl.sk_house_listing
),
iq_nps AS (
    SELECT
        ct.id_termination,
        fnd.score,
        dnc.metric_group,
        dd.date AS dt_nps_answered
    FROM
        contract_termination AS ct
    JOIN
        dw_tracksale.fact_nps_dispatches AS fnd
            ON fnd.sk_contract = ct.id_contract
    LEFT JOIN
        dw_tracksale.dim_nps_campaign AS dnc
            ON dnc.sk_nps_campaign = fnd.sk_nps_campaign
    LEFT JOIN
        dw_public.dim_date AS dd
            ON dd.sk_date = sk_answered_date
    WHERE
        dnc.metric_group IN ('iqongoing', 'ongoing','iqonboarding', 'onboarding')
        AND dnc.customer_type = 'IQ'
),
iq_last_ongoing_nps AS (
    SELECT
        id_termination,
        score
    FROM
        iq_nps
    WHERE
        metric_group IN ('iqongoing', 'ongoing')
    QUALIFY ROW_NUMBER() OVER(PARTITION BY id_termination ORDER BY dt_nps_answered DESC, score DESC) = 1
),
tbl_all_nps_info AS (
    SELECT
        iq_nps.id_termination,
        SUM(
            CASE
                WHEN iq_nps.score BETWEEN 9 AND 10 THEN 1
                ELSE 0
            END
        ) AS iq_nps_promotor_jornada,
        SUM(
          CASE
              WHEN iq_nps.score BETWEEN 0 AND 6 THEN 1
              ELSE 0
          END
        ) AS iq_nps_detrator_jornada,
        CASE
            WHEN MAX(iq_last_ongoing_nps.score) > 8 THEN 1
            ELSE 0
        END AS last_nps_promotor
    FROM
        iq_nps
    LEFT JOIN
        iq_last_ongoing_nps
            ON iq_last_ongoing_nps.id_termination = iq_nps.id_termination
    GROUP BY
        1
),
tenants AS (
    SELECT
        sk_contract,
        sk_user,
        CASE
            WHEN is_first_contract = True THEN 1
            ELSE 0
        END AS is_first_contract,
        is_contract_user
    FROM
        dw_rent.fact_contract_people
    WHERE
        contract_role = 'tenant'
    UNION ALL
    SELECT DISTINCT
        ft.sk_contract,
        ft.sk_user,
        NULL AS is_first_contract,
        NULL AS is_contract_user
    FROM
        dw_customer_support.fact_ticket AS ft
    LEFT JOIN
        dw_customer_support.dim_taxonomy AS dt
            ON ft.sk_taxonomy = dt.sk_taxonomy
    WHERE
        sk_contract IS NOT NULL
        AND dt.customer_type_tag = 'tenant'
),
tickets_segments AS (
    SELECT
        fs.sk_ticket,
        SUM(CASE
                WHEN is_sla = false THEN 1
                ELSE 0
            END
        ) AS segments_not_sla
    FROM
        dw_customer_support.fact_segment fs
    GROUP BY
        1
),
tbl_tickets_refined AS (
    SELECT
        ft.sk_ticket,
        ft.front_or_back,
        ft.csat_score,
        ft.sk_user,
        ft.sk_contract,
        dd.journey_step,
        ft.ts_started,
        dt.motivation,
        CAST(dmt.is_ticket_solved_within_sla AS INTEGER) AS is_ticket_solved_within_sla,
        COALESCE(ts.segments_not_sla,0) AS segments_not_sla
    FROM
        dw_customer_support.fact_ticket AS ft
    LEFT JOIN
        dw_customer_support.dim_taxonomy AS dt
            ON ft.sk_taxonomy = dt.sk_taxonomy
    LEFT JOIN
        dw_customer_support.dim_ticket_tags AS dtt
            ON dtt.sk_tags = ft.sk_tags
    LEFT JOIN
        dw_customer_support.dim_department AS dd
            ON dd.sk_department = ft.sk_main_department
    LEFT JOIN
        dw_customer_support.fact_demand_metrics_tasks AS dmt
            ON dmt.sk_task = CAST(ft.sk_ticket AS STRING)
            AND dmt.ts_solved IS NOT NULL
    LEFT JOIN
        tickets_segments AS ts
            ON ts.sk_ticket = ft.sk_ticket
    WHERE
        dd.area = 'CX'
        AND dd.journey_step IN ('Ongoing', 'Onboarding', 'Cross')
        AND ft.status = 'closed'
        AND dt.customer_type_tag = 'tenant'
),
tickets_by_contract AS (
    SELECT
        ct.id_termination,
        SUM(CASE
                WHEN tickets.journey_step <> 'Cross' AND tickets.front_or_back = 'front' THEN 1
                ELSE 0
            END
        ) AS front_tickets_jornada,
        SUM(CASE
                WHEN tickets.journey_step <> 'Cross' AND tickets.motivation = 'complaint' THEN 1
                ELSE 0
            END
        ) AS complaint_tickets_jornada,
        SUM(CASE
                WHEN tickets.journey_step = 'Cross' AND tickets.ts_started < ct.ts_created THEN 1
            END
        ) AS total_tickets_especiais,
        SUM(CASE
                WHEN tickets.journey_step <> 'Cross' AND tickets.csat_score IN (1,2) THEN 1
                ELSE 0 END
        ) AS csat_disatisfied_jornada,
        SUM(CASE
                WHEN tickets.journey_step <> 'Cross' AND tickets.csat_score IN (4,5) THEN 1
                ELSE 0
            END
        ) AS csat_satisfied_jornada,
        SUM(CASE
                WHEN tickets.is_ticket_solved_within_sla = 0 AND tickets.journey_step <> 'Cross' THEN 1
                ELSE 0
            END
        ) AS back_tickets_not_sla_jornada,
        SUM(tickets.segments_not_sla) AS total_segments_not_sla
    FROM
        contract_termination AS ct
    LEFT JOIN
        tbl_tickets_refined AS tickets
            ON tickets.sk_contract = ct.id_contract
    GROUP BY
        1
),
unique_tenants_by_contract AS (
    SELECT DISTINCT
        sk_contract,
        sk_user
    FROM
        tenants
),
tickets_by_tenant AS (
    SELECT
        ct.id_termination,
        SUM(CASE
                WHEN tickets.journey_step <> 'Cross' AND tickets.front_or_back = 'front' THEN 1
                ELSE 0
            END
        ) AS front_tickets_jornada,
        SUM(CASE
                WHEN tickets.journey_step <> 'Cross' AND tickets.motivation = 'complaint' THEN 1
                ELSE 0
            END
        ) AS complaint_tickets_jornada,
        SUM(CASE
                WHEN tickets.journey_step = 'Cross' AND tickets.ts_started < ct.ts_created THEN 1
            END
        ) AS total_tickets_especiais,
        SUM(CASE
                WHEN tickets.journey_step <> 'Cross' AND tickets.csat_score IN (1,2) THEN 1
                ELSE 0
            END
        ) AS csat_disatisfied_jornada,
        SUM(CASE
                WHEN tickets.journey_step <> 'Cross' AND tickets.csat_score IN (4,5) THEN 1
                ELSE 0
            END
        ) AS csat_satisfied_jornada,
        SUM(CASE
                WHEN tickets.is_ticket_solved_within_sla = 0 AND tickets.journey_step <> 'Cross' THEN 1
                ELSE 0
            END
        ) AS back_tickets_not_sla_jornada,
        SUM(tickets.segments_not_sla) AS total_segments_not_sla
    FROM
        contract_termination AS ct
    LEFT JOIN
        unique_tenants_by_contract AS tn
            ON ct.id_contract = tn.sk_contract
    LEFT JOIN
        tbl_tickets_refined AS tickets
            ON tickets.sk_user = tn.sk_user
    LEFT JOIN
        dim_contract AS dc
            ON dc.id_termination = ct.id_termination
    WHERE
        tickets.sk_contract IS NULL
        AND tickets.ts_started >= dc.ts_created
        AND tickets.ts_started <= ct.dt_termination
    GROUP BY 1
),
tickets_union AS (
    SELECT
        *
    FROM
        tickets_by_tenant
    UNION
    SELECT
        *
    FROM
        tickets_by_contract
),
total_tickets AS (
    SELECT
        id_termination,
        SUM(front_tickets_jornada) AS front_tickets_jornada,
        SUM(complaint_tickets_jornada) AS complaint_tickets_jornada,
        SUM(total_tickets_especiais) AS total_tickets_especiais,
        SUM(csat_disatisfied_jornada) AS csat_disatisfied_jornada,
        SUM(csat_satisfied_jornada) AS csat_satisfied_jornada,
        SUM(back_tickets_not_sla_jornada) AS back_tickets_not_sla_jornada
    FROM
        tickets_union
    GROUP BY 1
),
tenant_first_listing AS (
    SELECT
        sk_contract,
        CASE
            WHEN SUM(is_first_contract) > 1 THEN 1
            ELSE 0
        END AS iq_first_contract
    FROM
        tenants
    WHERE
        is_contract_user = True
    GROUP BY
        1
)
SELECT
    ct.id_termination,
    ct.id_contract,
    ct.id_house,
    'offboarding_tenant' AS model_name,
    'nps_reversion_off_tenant_reglog_v0' AS model_version,
    DATE(ct.ts_created) AS dt_termination_request,
    ct.dt_termination,
    ct.reason_DISLIKES_QUINTOANDAR,
    ct.reason_PROBLEMS_WITH_HOUSE,
    ct.reason_NEEDS_CHANGE,
    ct.reason_MOVING_OWN_HOUSE,
    ct.reason_OTHER,
    ct.reason_JOB_TRANSFER,
    ct.reason_MOVING_TO_FRIENDS_OR_FAMILY,
    ct.type_of_termination_fine_WITHOUT_NOTICE,
    dc.contract_lifetime,
    COALESCE(dhl.house_type_Casa,0) AS house_type_Casa,
    COALESCE(dhl.house_bedrooms,0) AS house_bedrooms,
    COALESCE(tni.last_nps_promotor, 0) AS last_nps_promotor,
    COALESCE(tni.iq_nps_promotor_jornada, 0) AS iq_nps_promotor_jornada,
    COALESCE(tni.iq_nps_detrator_jornada, 0) AS iq_nps_detrator_jornada,
    COALESCE(tt.front_tickets_jornada,0) AS front_tickets_jornada,
    COALESCE(tt.complaint_tickets_jornada,0) AS complaint_tickets_jornada,
    COALESCE(tt.total_tickets_especiais,0) AS total_tickets_especiais,
    COALESCE(tt.csat_disatisfied_jornada,0) AS csat_disatisfied_jornada,
    COALESCE(tt.csat_satisfied_jornada,0) AS csat_satisfied_jornada,
    COALESCE(tt.back_tickets_not_sla_jornada,0) AS back_tickets_not_sla_jornada,
    COALESCE(tfl.iq_first_contract,0) AS iq_first_contract
FROM
    contract_termination AS ct
LEFT JOIN
    dim_contract AS dc
        ON ct.id_termination = dc.id_termination
LEFT JOIN
    dim_house_listing AS dhl
        ON ct.id_termination = dhl.id_termination
LEFT JOIN
    tbl_all_nps_info AS tni
        ON ct.id_termination = tni.id_termination
LEFT JOIN
    total_tickets AS tt
        ON ct.id_termination = tt.id_termination
LEFT JOIN
    tenant_first_listing AS tfl
        ON ct.id_contract = tfl.sk_contract
