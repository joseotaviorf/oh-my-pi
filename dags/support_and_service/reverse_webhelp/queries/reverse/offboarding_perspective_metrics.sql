WITH tof AS (
    SELECT
        t.id_contract,
        MAX(t.ts_created) AS termination_request,
        MAX(t.dt_vacancy) AS dt_termination,
        MAX(DATE(dc.ts_analyst_annulment_input)) AS ended_confirmed,
        MAX(ct.ts_termination_finished) AS ts_termination_finished,
        t.status AS inspection_status,
        ct.has_repairs,
        ct.is_repair_tenant_duty,
        ct.repair_resolution,
        ct.repair_cost,
        CASE
            WHEN tw.id_termination IS NOT NULL THEN 'Workflow'
            ELSE NULL
        END AS workflow,
        tw.current_step,
        ct.reason,
        ct.category,
        dhl.id_house,
        dc.is_exit_inspection_opted_out,
        dc.b2b_type,
        dc.status AS contract_status,
        dc.rent,
        dr.short_region_name AS reg_state,
        dr.city_name,
        dr.city_id,
        ft.is_spoc_contract,
        ft.spoc_wave,
        ft.is_spoc_control_group,
        dit.team AS spoc_team,
        da.email AS spoc_agent_email,
        ft.total_tentant_repair_ar,
        ft.total_tentant_repair_ac,
        ft.repairs_absorbed_ac,
        CASE
            WHEN MIN(DATE(ins.ts_synced)) > MAX(DATE(t.ts_created)) THEN MIN(DATE(ins.ts_synced))
            ELSE NULL
        END AS sync_date
    FROM
        datalake_terminator_clean.termination AS t
    LEFT JOIN
        datalake_offboarding.contract_termination AS ct ON t.id = ct.id_termination
    LEFT JOIN
        datalake_terminator_clean.termination_workflow AS tw ON t.id = tw.id_termination
    LEFT JOIN
        dw_offboarding.fact_terminations AS ft ON t.id = ft.sk_termination
    LEFT JOIN
        dw_rent.fact_house_listings AS fhl ON t.id_contract = fhl.sk_contract
    LEFT JOIN
        dw_rent.dim_house_listing AS dhl ON fhl.sk_house_listing = dhl.sk_house_listing
    LEFT JOIN
        dw_rent.dim_contract AS dc ON t.id_contract = dc.sk_contract
    LEFT JOIN
        dw_public.dim_region AS dr ON fhl.sk_region = dr.sk_region
    LEFT JOIN (
        SELECT
            fi.sk_contract,
            fi.ts_synced,
            fi.sk_inspection,
            di.inspection_type,
            ROW_NUMBER() OVER (PARTITION BY fi.sk_contract ORDER BY fi.ts_synced DESC) AS rn
        FROM
            dw_inspections.fact_inspection AS fi
        LEFT JOIN
            dw_inspections.dim_inspection AS di ON fi.sk_inspection = di.sk_inspection
        WHERE
            di.inspection_type IN ('offboarding')
    ) AS ins ON t.id_contract = ins.sk_contract AND ins.rn = 1
    LEFT JOIN
        dw_customer_support.dim_analyst AS da ON ft.sk_analyst = da.sk_analyst
    LEFT JOIN
        dw_offboarding.dim_termination AS dit ON t.id = dit.sk_termination
    WHERE
        t.dt_vacancy <= DATE_ADD(MONTH, 1, '{load_start_date}')
        AND t.status NOT IN ('CANCELED')
        AND dc.country_code = 'BR'
        AND t.ts_created >= DATE('2024-01-01')
        AND t.ts_created <= '{load_start_date}'
        AND t.id_contract NOT IN (764418) --ano de recisão está trocado
    GROUP BY
        1, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30
),
---
inspections AS (
    SELECT
        fi.sk_contract,
        fi.ts_created,
        fi.sk_inspection,
        fi.ts_inspected,
        di.status,
        ROW_NUMBER() OVER (PARTITION BY fi.sk_contract ORDER BY fi.ts_created DESC) AS rn
    FROM
        dw_inspections.fact_inspection AS fi
    LEFT JOIN
        dw_inspections.dim_inspection AS di ON fi.sk_inspection = di.sk_inspection
    LEFT JOIN
        datalake_terminator.termination AS t ON fi.sk_contract = t.id_contract
    WHERE
        di.inspection_type IN ('offboarding', 'verification')
        AND di.status NOT IN ('cancelled')
        AND fi.ts_created >= t.ts_termination_request
        AND fi.ts_created >= DATE('2024-01-01')
),
---
new_repairs_analysis AS (
    SELECT
        t.id_contract AS sk_contract,
        ts.id_external AS sk_ticket,
        DATE(ts.ts_created) AS created_date,
        DATE(ft.ts_solved) AS solved_date,
        ROW_NUMBER() OVER (PARTITION BY t.id_contract ORDER BY ts.ts_created DESC) AS rn
    FROM
        datalake_terminator_clean.termination AS t
    RIGHT JOIN
        datalake_terminator_clean.termination_task AS ts ON t.id = ts.id_termination
    LEFT JOIN
        dw_customer_support.fact_tickets AS ft ON CAST(ft.sk_ticket AS VARCHAR(20)) = ts.id_external
    WHERE
        ts.type = 'TERMINATION_INSPECTION_REVIEW'
        AND t.ts_created >= DATE('2024-01-01')
),
---
new_contestation_analysis AS (
    SELECT
        t.id_contract AS sk_contract,
        ts.id_external AS sk_ticket,
        DATE(ts.ts_created) AS created_date,
        DATE(ft.ts_solved) AS solved_date,
        ROW_NUMBER() OVER (PARTITION BY t.id_contract ORDER BY ts.ts_created DESC) AS rn
    FROM
        datalake_terminator_clean.termination AS t
    RIGHT JOIN
        datalake_terminator_clean.termination_task AS ts ON t.id = ts.id_termination
    LEFT JOIN
        dw_customer_support.fact_tickets AS ft ON CAST(ft.sk_ticket AS VARCHAR(20)) = ts.id_external
    WHERE
        ts.type = 'TERMINATION_CONTESTATION'
        AND t.ts_created >= DATE('2024-01-01')
),
---
new_mediation AS (
    SELECT
        t.id_contract AS sk_contract,
        ts.id_external AS sk_ticket,
        (ts.ts_created - INTERVAL '1' HOUR) AS created_date,
        DATE(ft.ts_solved) AS solved_date,
        da.email AS agent_email,
        CASE
            WHEN ts.id_external IS NULL THEN NULL
            WHEN dt.tags LIKE '%checkout_wkf_budg_appr_by_ll%' AND dt.tags LIKE '%checkout_wkf_budg_appr_by_tt%' THEN 'both_agreed'
            WHEN dt.tags LIKE '%checkout_wkf_budg_appr_by_ll%' AND dt.tags NOT LIKE '%checkout_wkf_budg_appr_by_tt%' THEN 'll_agreed'
            WHEN dt.tags LIKE '%checkout_wkf_budg_appr_by_tt%' AND dt.tags NOT LIKE '%checkout_wkf_budg_appr_by_ll%' THEN 'tt_agreed'
            WHEN dt.tags NOT LIKE '%checkout_wkf_budg_appr_by_tt%' AND dt.tags NOT LIKE '%checkout_wkf_budg_appr_by_ll%' THEN 'both_disagreed_no_answer'
            ELSE NULL
        END AS squad,
        ROW_NUMBER() OVER (PARTITION BY t.id_contract ORDER BY ts.ts_created DESC) AS rn
    FROM
        datalake_terminator_clean.termination AS t
    RIGHT JOIN
        datalake_terminator_clean.termination_task AS ts ON t.id = ts.id_termination
    LEFT JOIN
        dw_customer_support.fact_tickets AS ft ON CAST(ft.sk_ticket AS VARCHAR(20)) = ts.id_external
    LEFT JOIN
        dw_customer_support.dim_ticket AS dt ON ft.sk_ticket = dt.sk_ticket
    LEFT JOIN
        dw_customer_support.dim_analyst AS da ON ft.sk_first_analyst = da.sk_analyst
    WHERE
        ts.type = 'TERMINATION_LANDLORD'
        AND t.ts_created >= DATE('2024-01-01')
        AND dt.group_name LIKE '%[POS] [BACK]'
),
---
report_comments_pre AS (
    SELECT
        fi.sk_contract,
        SUM(frr.total_repair_request) total_repair_request,
        DATE(frr.ts_sent_to_owner_review) AS ts_sent_to_owner_review,
        DATE(frr.ts_sent_to_contestation_analysis) AS ts_sent_to_contestation_analysis,
        ts_sent_to_repair_analysis
       -- ROW_NUMBER() OVER (PARTITION BY fi.sk_contract ORDER BY frr.ts_sent_to_repair_analysis ASC) AS rn
    FROM
        dw_inspections.fact_report_review AS frr
    LEFT JOIN
        dw_inspections.fact_inspection AS fi ON fi.sk_inspection = frr.sk_inspection AND fi.sk_assessment = frr.sk_assessment
    WHERE
        DATE(frr.ts_sent_to_repair_analysis) BETWEEN DATE('2024-01-01') AND DATE('{load_start_date}')
    GROUP BY 1,3,4,5
),
report_comments AS (
    SELECT*,
    ROW_NUMBER() OVER (PARTITION BY sk_contract ORDER BY ts_sent_to_repair_analysis ASC) AS rn
    FROM report_comments_pre
)
---
,budget_approval AS (
    SELECT
        ia.id_contract,
        ia.ts_updated,
        ROW_NUMBER() OVER (PARTITION BY ia.id_contract ORDER BY ia.ts_updated ASC) AS rn
    FROM
        datalake_inspection_services_clean.inspection_aud AS ia
    WHERE
        ia.status IN ('budget_approval_sent_to_owner', 'budget_approval')
        AND ia.ts_updated >= DATE('2024-04-01')
),
---
despejo AS (
    SELECT
        ft.sk_contract,
        ft.sk_ticket,
        DATE(dt.ts_created_brt) AS created_date,
        DATE(ft.ts_solved) AS solved_date,
        ROW_NUMBER() OVER (PARTITION BY ft.sk_contract ORDER BY dt.ts_created_brt DESC) AS rn
    FROM
        dw_customer_support.fact_tickets AS ft
    LEFT JOIN
        dw_customer_support.dim_ticket AS dt ON ft.sk_ticket = dt.sk_ticket
    WHERE
        dt.group_name = 'Rescisão por Inadimplência [OFF][POS][BACK]'
        AND COALESCE(CAST(GET_JSON_OBJECT(dt.custom_fields, '$.Tipo de Cliente [PRE-SAIDA]') AS VARCHAR(100)), CAST(GET_JSON_OBJECT(dt.custom_fields, '$.Tipo de Cliente') AS VARCHAR(100))) LIKE '%inquilino%'
        AND CAST(GET_JSON_OBJECT(dt.custom_fields, '$.Tipo de Demanda') AS VARCHAR(100)) IN ('demanda_de_processos')
        AND CAST(GET_JSON_OBJECT(dt.custom_fields, '$.Tipo de processo') AS VARCHAR(100)) IN ('despejo/fraude')
        AND dt.subject LIKE '%Rescisão do contrato%'
        AND ft.ts_created >= DATE('2024-01-01')
),
---
contestacao AS (
    WITH base_pp AS (
        SELECT
            sk_inspection,
            CASE
                WHEN has_owner_access_review = TRUE THEN 1
                ELSE 0
            END AS pp_open,
            CASE
                WHEN ts_sent_to_tenant_review IS NULL THEN DATE(ts_reviewed)
                ELSE DATE(ts_sent_to_tenant_review)
            END AS reviewed_date_pp,
            total_repairs_requested_by_owner
        FROM
            dw_inspections.fact_report_inspections AS fri
    ),
    base_iq AS (
        SELECT
            sk_inspection,
            CASE
                WHEN has_tenant_access_review = TRUE THEN 1
                ELSE 0
            END AS iq_open,
            CASE
                WHEN ts_sent_to_contestation_analysis IS NULL THEN DATE(ts_reviewed)
                ELSE DATE(ts_sent_to_contestation_analysis)
            END AS reviwed_date_iq,
            CASE
                WHEN ts_sent_to_tenant_review IS NULL AND ts_review_started_by_tenant IS NULL THEN 0
                ELSE 1
            END AS tenant_review,
            total_tenant_contestation
        FROM
            dw_inspections.fact_report_inspections
    ),
    pp_contestacao AS (
        SELECT
            sk_inspection,
            bpp.reviewed_date_pp AS pp_date_ref,
            bpp.pp_open AS pp_open,
            CASE WHEN bpp.pp_open = 1 AND bpp.total_repairs_requested_by_owner > 0 THEN 1 ELSE 0 END AS pp_contestation
        FROM
            base_pp AS bpp
    ),
    iq_contestacao AS (
        SELECT
            sk_inspection,
            biq.reviwed_date_iq AS iq_date_ref,
            biq.iq_open AS iq_open,
            CASE WHEN biq.iq_open = 1 AND biq.total_tenant_contestation > 0 THEN 1 ELSE 0 END AS iq_contestation
        FROM
            base_iq AS biq
    ),
    final AS (
        SELECT
            sk_inspection
        FROM
            pp_contestacao
        UNION ALL
        SELECT
            sk_inspection
        FROM
            iq_contestacao
    )
    SELECT DISTINCT
        fi.sk_contract,
        MAX(pc.pp_date_ref) AS pp_date_ref,
        CASE WHEN SUM(pc.pp_open) > 0 THEN 1 ELSE 0 END AS pp_open,
        CASE WHEN SUM(pc.pp_contestation) > 0 THEN 1 ELSE 0 END AS pp_contestation,
        MAX(ic.iq_date_ref) AS iq_date_ref,
        CASE WHEN SUM(ic.iq_open) > 0 THEN 1 ELSE 0 END AS iq_open,
        CASE WHEN SUM(ic.iq_contestation) > 0 THEN 1 ELSE 0 END AS iq_contestation
    FROM
        final AS f
    LEFT JOIN
        dw_inspections.fact_inspection AS fi ON CAST(f.sk_inspection AS VARCHAR(20)) = fi.sk_inspection
    LEFT JOIN
        pp_contestacao AS pc ON f.sk_inspection = pc.sk_inspection
    LEFT JOIN
        iq_contestacao AS ic ON f.sk_inspection = ic.sk_inspection
    GROUP BY
        1
),
---
base AS (
    SELECT DISTINCT
        ins.id_contract,
        frr.*,
        frv.ts_reviewed
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (PARTITION BY sk_repair_request ORDER BY ts_updated DESC) AS rn
        FROM
            dw_inspections.fact_repair_request AS rr
    ) AS frr
    LEFT JOIN (
        SELECT DISTINCT
            id_inspection,
            id_contract
        FROM
            datalake_inspection_services_clean.inspection
    ) AS ins ON frr.sk_inspection = ins.id_inspection
    LEFT JOIN
        dw_inspections.fact_report_review AS frv ON frr.sk_assessment = frv.sk_assessment
    WHERE
        frr.rn = 1
        AND frr.is_exempted = FALSE
        AND ts_reviewed IS NOT NULL
),
---
reports AS (
    SELECT
        sk_inspection,
        id_contract,
        sk_assessment,
        ts_reviewed
    FROM
        base
    GROUP BY
        sk_inspection, id_contract, sk_assessment, ts_reviewed
),
---
bains AS (
    SELECT
        id_inspection
    FROM
        datalake_inspection_services_clean.inspection_aud
    WHERE
        status IN ('budget_approval_sent_to_owner', 'budget_approval')
),
---
partial_ba_final_query AS (
    SELECT
        r.*,
        ap1.is_approved AS tenant_approval,
        ap2.is_approved AS landlord_approval
    FROM
        reports AS r
    LEFT JOIN (
        SELECT
            fra.*,
            dr.reviewer_type
        FROM
            dw_inspections.fact_reviewer_approval AS fra
        LEFT JOIN
            dw_inspections.dim_reviewer AS dr ON fra.sk_reviewer = dr.sk_reviewer
        WHERE
            fra.approval_type = 'BUDGET_APPROVAL'
            AND reviewer_type = 'TENANT'
    ) AS ap1 ON r.sk_assessment = ap1.sk_assessment
    LEFT JOIN (
        SELECT
            fra.*,
            dr.reviewer_type
        FROM
            dw_inspections.fact_reviewer_approval AS fra
        LEFT JOIN
            dw_inspections.dim_reviewer AS dr ON fra.sk_reviewer = dr.sk_reviewer
        WHERE
            fra.approval_type = 'BUDGET_APPROVAL'
            AND reviewer_type = 'OWNER'
    ) AS ap2 ON r.sk_assessment = ap2.sk_assessment
    LEFT JOIN
        bains AS bi ON r.sk_inspection = bi.id_inspection
    WHERE
        bi.id_inspection IS NOT NULL
),
---
a AS (
    SELECT
        *,
        CASE
            WHEN tenant_approval = TRUE AND landlord_approval = TRUE THEN 'Both Agreed'
            WHEN tenant_approval = FALSE AND landlord_approval = FALSE THEN 'Both Disagree'
            WHEN tenant_approval = FALSE AND landlord_approval = TRUE THEN 'LL Agreed TT Disagreed'
            WHEN tenant_approval = TRUE AND landlord_approval = FALSE THEN 'LL Disagreed TT Agreed'
            WHEN tenant_approval IS NULL AND landlord_approval IS NULL THEN 'No answer'
            WHEN tenant_approval IS NULL AND landlord_approval = TRUE THEN 'LL Agreed TT no answer'
            WHEN tenant_approval IS NULL AND landlord_approval = FALSE THEN 'LL Disagreed TT no answer'
            WHEN tenant_approval = TRUE AND landlord_approval IS NULL THEN 'TT Agreed LL no answer'
            WHEN tenant_approval = FALSE AND landlord_approval IS NULL THEN 'TT Disagreed LL no answer'
        END AS type_ba
    FROM
        partial_ba_final_query
),
---
budget_approval_detailed AS (
    SELECT
        bad.id_contract,
        bad.type_ba,
        ROW_NUMBER() OVER (PARTITION BY id_contract ORDER BY id_contract DESC) AS rn
    FROM
        a AS bad
),
---
status AS (
    SELECT DISTINCT
        sk_house_listing,
        status_history,
        ts_status_start,
        ts_status_end,
        ROW_NUMBER() OVER (PARTITION BY sk_house_listing / 1000 ORDER BY ts_status_start DESC) AS rn_property
    FROM
        dw_rent.fact_house_listing_status
    WHERE
        (ts_status_end IS NULL OR ts_status_start <> ts_status_end)
),
---
prep AS (
    SELECT
        ct.id_contract,
        dc.dt_ended_rental_confirmed AS erc_dt,
        sw1_erc.status_history AS status_1w_after_erc,
        sw2_erc.status_history AS status_2w_after_erc,
        sw3_erc.status_history AS status_3w_after_erc,
        sw4_erc.status_history AS status_4w_after_erc,
        DATE(dc_next.ts_signature) AS ct_date,
        ROW_NUMBER() OVER (PARTITION BY ct.id_contract ORDER BY dc.dt_ended_rental_confirmed DESC) AS rn
    FROM
        datalake_offboarding.contract_termination AS ct
    LEFT JOIN
        dw_rent.dim_contract AS dc ON ct.id_contract = dc.sk_contract
    LEFT JOIN
        dw_rent.fact_house_listings AS fhl ON ct.id_house_listing = fhl.sk_house_listing
    LEFT JOIN
        dw_rent.dim_contract AS dc_next ON fhl.sk_next_contract = dc_next.sk_contract
    LEFT JOIN
        status AS sw1_erc ON ct.id_house_listing / 1000 = sw1_erc.sk_house_listing / 1000
        AND DATE_ADD(day, 7, dc.dt_ended_rental_confirmed) >= sw1_erc.ts_status_start
        AND DATE_ADD(day, 7, dc.dt_ended_rental_confirmed) <= COALESCE(sw1_erc.ts_status_end, '{load_start_date}')
    LEFT JOIN
        status AS sw2_erc ON ct.id_house_listing / 1000 = sw2_erc.sk_house_listing / 1000
        AND DATE_ADD(day, 14, dc.dt_ended_rental_confirmed) >= sw2_erc.ts_status_start
        AND DATE_ADD(day, 14, dc.dt_ended_rental_confirmed) <= COALESCE(sw2_erc.ts_status_end, '{load_start_date}')
    LEFT JOIN
        status AS sw3_erc ON ct.id_house_listing / 1000 = sw3_erc.sk_house_listing / 1000
        AND DATE_ADD(day, 21, dc.dt_ended_rental_confirmed) >= sw3_erc.ts_status_start
        AND DATE_ADD(day, 21, dc.dt_ended_rental_confirmed) <= COALESCE(sw3_erc.ts_status_end, '{load_start_date}')
    LEFT JOIN
        status AS sw4_erc ON ct.id_house_listing / 1000 = sw4_erc.sk_house_listing / 1000
        AND DATE_ADD(day, 28, dc.dt_ended_rental_confirmed) >= sw4_erc.ts_status_start
        AND DATE_ADD(day, 28, dc.dt_ended_rental_confirmed) <= COALESCE(sw4_erc.ts_status_end, '{load_start_date}')
    LEFT JOIN
        dw_rent.dim_house_listing AS dhl_last ON ct.id_house_listing / 1000 = dhl_last.id_house
        AND dhl_last.sk_house_listing > ct.id_house_listing
        AND dhl_last.is_last_version
    WHERE
        ct.status <> 'CANCELED'
        AND DATE(ct.ts_created) >= DATE_ADD(month, -12, DATE_TRUNC('month', '{load_start_date}'))
        AND dc.country_code <> 'MX'
),
---
ac_comments AS (
SELECT DISTINCT
  i.sk_contract,
  rr.responsibility,
  rr.cost
FROM datalake_inspection_services_clean.repair_request rr
LEFT JOIN datalake_inspection_services_clean.reviewer createdBy
  ON createdBy.id_reviewer = rr.id_reviewer
INNER JOIN datalake_inspection_services_clean.item_group ig
  ON rr.id_item_group = ig.id_item_group
INNER JOIN datalake_inspection_services_clean.room r
  ON ig.id_room = r.id_room
LEFT JOIN datalake_inspection_services_clean.reviewer grantedBy
  ON grantedBy.id_reviewer = rr.id_granted_by
LEFT JOIN dw_inspections.fact_repair_request frr
  ON rr.id_repair_request = frr.sk_repair_request
LEFT JOIN dw_inspections.fact_inspection i
  ON CAST(frr.sk_inspection AS VARCHAR(20)) = i.sk_inspection
WHERE NOT (createdBy.reviewer_type = 'INSPECTIONS_SERVICE' AND (rr.has_automatic_identification_accepted = FALSE OR rr.has_automatic_identification_accepted IS NULL))
AND grantedBy.approval_type = 'CONTESTATION_ANALYSIS'
AND rr.ts_granted >= DATE('2024-01-01')
),
---
ac_itens AS (
    SELECT
        acc.sk_contract,
        SUM(CASE WHEN acc.responsibility = 'TENANT' THEN 1 ELSE 0 END) AS itens_tt,
        SUM(IF(acc.responsibility = 'TENANT', acc.cost, NULL)) AS itens_tt_cost,
        SUM(CASE WHEN acc.responsibility IS NOT NULL THEN 1 ELSE 0 END) AS total_itens,
        SUM(IF(acc.responsibility IS NOT NULL, acc.cost, NULL)) AS total_itens_cost
    FROM
        ac_comments AS acc
    GROUP BY
        1
),
---
main_query AS (
    SELECT
        to.id_contract,
        DATE(to.termination_request) AS termination_request,
        to.dt_termination,
        to.is_exit_inspection_opted_out,
        to.ts_termination_finished,
        DATE(insp.ts_created) AS booking_insp_created_dt,
        insp.sk_inspection AS sk_inspection,
        DATE(insp.ts_inspected) AS ts_inspected,
        to.ended_confirmed,
        ar.sk_ticket AS ar_ticket,
        ar.created_date AS ar_created_dt,
        ar.solved_date AS ar_solved_dt,
        rep.ts_sent_to_owner_review AS report_comments_created_dt,
        ac.created_date AS report_comments_solved_dt,
        ac.sk_ticket AS ac_ticket,
        ac.created_date AS ac_created_dt,
        ac.solved_date AS ac_solved_dt,
        DATE(ba.ts_updated) AS ba_created_dt,
        med.created_date AS ba_solved_dt,
        med.sk_ticket AS med_ticket,
        med.created_date AS med_created_dt,
        med.solved_date AS med_solved_dt,
        IF(med.agent_email LIKE '%webhelp%', med.agent_email, NULL) AS med_agent_email,
        des.sk_ticket AS des_ticket,
        des.created_date AS des_created_dt,
        des.solved_date AS des_solved_dt,
        ct.pp_date_ref AS ct_pp_date_ref,
        ct.pp_open AS ct_pp_open,
        ct.pp_contestation AS ct_pp_contestation,
        ct.iq_date_ref AS ct_iq_date_ref,
        ct.iq_open AS ct_iq_open,
        ct.iq_contestation AS ct_iq_contestation,
        CASE
            WHEN to.rent >= 2500 THEN 'high_value'
            ELSE 'FALSE'
        END AS value,
        CASE
            WHEN IF(DATE_DIFF(day, to.dt_termination, '{load_start_date}') > 30, 1, 0) = 1 THEN 'anomaly'
            ELSE 'FALSE'
        END AS anomaly,
        to.city_name,
        to.reg_state,
        to.category,
        rep.ts_sent_to_contestation_analysis,
        to.id_house,
        to.sync_date,
        to.spoc_wave,
        CASE
            WHEN to.termination_request < DATE('2025-05-22') AND to.is_spoc_contract = TRUE THEN 'before_wave_6'
            WHEN to.termination_request >= DATE('2025-05-22') AND to.is_spoc_contract = TRUE AND (to.is_spoc_control_group = FALSE OR to.is_spoc_control_group IS NULL) AND (to.spoc_team = 'ROLLOUT' OR to.spoc_team IS NULL) THEN 'rollout'
            WHEN to.termination_request >= DATE('2025-05-22') AND to.is_spoc_contract = TRUE AND (to.is_spoc_control_group = FALSE OR to.is_spoc_control_group IS NULL) AND to.spoc_team = 'LAB' THEN 'lab_test'
            WHEN to.termination_request >= DATE('2025-05-22') AND to.is_spoc_contract = TRUE AND to.is_spoc_control_group = TRUE THEN 'lab_control'
            ELSE NULL
        END AS spoc_class,
        IF(to.spoc_agent_email LIKE '%webhelp%', to.spoc_agent_email, NULL) AS spoc_agent_email,
        to.has_repairs,
        rep.total_repair_request,
        to.total_tentant_repair_ar,
        to.total_tentant_repair_ac,
        to.repairs_absorbed_ac,
        to.repair_resolution,
        med.squad,
        CASE WHEN to.total_tentant_repair_ac > 0 OR to.repairs_absorbed_ac > 0 THEN 1 ELSE 0 END AS has_repair_ac,
        bad.type_ba,
        cac.status_1w_after_erc,
        cac.status_2w_after_erc,
        cac.status_3w_after_erc,
        cac.status_4w_after_erc,
        IF(cac.erc_dt IS NOT NULL AND cac.ct_date IS NOT NULL, DATE_DIFF(day, cac.erc_dt, cac.ct_date), NULL) AS ldt_erc_rr,
        aci.itens_tt,
        aci.itens_tt_cost,
        aci.total_itens,
        aci.total_itens_cost
    FROM
        ToF AS to
    LEFT JOIN
        inspections AS insp ON to.id_contract = insp.sk_contract AND insp.rn = 1
    LEFT JOIN
        new_repairs_analysis AS ar ON to.id_contract = ar.sk_contract AND ar.rn = 1
    LEFT JOIN
        new_contestation_analysis AS ac ON to.id_contract = ac.sk_contract AND ac.rn = 1
    LEFT JOIN
        new_mediation AS med ON to.id_contract = med.sk_contract AND med.rn = 1
    LEFT JOIN
        budget_approval AS ba ON to.id_contract = ba.id_contract AND ba.rn = 1
    LEFT JOIN
        despejo AS des ON to.id_contract = des.sk_contract AND des.rn = 1
    LEFT JOIN
        report_comments AS rep ON to.id_contract = rep.sk_contract AND rep.rn = 1
    LEFT JOIN
        contestacao AS ct ON to.id_contract = ct.sk_contract
    LEFT JOIN
        budget_approval_detailed AS bad ON to.id_contract = bad.id_contract AND bad.rn = 1
    LEFT JOIN
        prep AS cac ON to.id_contract = cac.id_contract AND cac.rn = 1
    LEFT JOIN
        ac_itens AS aci ON to.id_contract = aci.sk_contract
),
---
mascara AS (
    SELECT
        m.*,
        CASE
            WHEN m.is_exit_inspection_opted_out = TRUE THEN 'Isento de VT apenas dar TF'
            WHEN m.ts_termination_finished IS NOT NULL THEN 'TF'
            WHEN m.med_solved_dt IS NOT NULL THEN 'Aguardando TF'
            WHEN m.med_created_dt IS NOT NULL THEN 'Mediação'
            WHEN m.ac_solved_dt IS NOT NULL AND m.category = 'EVICTION' THEN 'Despejo'
            WHEN m.ac_solved_dt IS NOT NULL THEN 'Budget Approval'
            WHEN m.ts_sent_to_contestation_analysis IS NOT NULL THEN 'AC'
            WHEN (m.ar_solved_dt IS NOT NULL) THEN 'Prazo PP/IQ'
            WHEN (m.ar_created_dt IS NOT NULL) OR ((m.ended_confirmed IS NOT NULL) AND (m.ts_inspected IS NOT NULL)) THEN 'AR'
            WHEN m.category = 'EVICTION' THEN 'Despejo'
            WHEN m.ts_inspected IS NOT NULL THEN 'ERC'
            WHEN m.dt_termination IS NOT NULL THEN 'VT'
        END AS status_atual,
        CASE
            WHEN DATE_DIFF(day, m.dt_termination, COALESCE(m.ts_termination_finished, '{load_start_date}')) < 0 THEN 0
            ELSE DATE_DIFF(day, m.dt_termination, COALESCE(m.ts_termination_finished, '{load_start_date}'))
        END AS aging_esteira,
        DATE_DIFF(day, m.med_created_dt, m.med_solved_dt) AS leadtime_mediacao,
        DATE_DIFF(day, m.med_solved_dt, m.ts_termination_finished) AS leadtime_aguardando_tf,
        DATE_DIFF(day, m.ts_sent_to_contestation_analysis, m.ac_solved_dt) AS leadtime_ac,
        DATE_DIFF(day, m.ar_created_dt, m.ar_solved_dt) AS leadtime_ar,
        DATE_DIFF(day, m.ts_inspected, m.ar_created_dt) AS leadtime_erc,
        DATE_DIFF(day, m.dt_termination, m.ts_inspected) AS leadtime_vt,
        DATE_DIFF(day, m.ar_solved_dt, COALESCE(m.ts_sent_to_contestation_analysis, m.ac_created_dt)) AS leadtime_prazo_pp_iq,
        DATE_DIFF(day, m.ac_solved_dt, COALESCE(m.med_created_dt, m.ts_termination_finished)) AS leadtime_budget_approval,
        DATE_DIFF(day, m.dt_termination, m.ts_termination_finished) AS leadtime_total
    FROM
        main_query AS m
)
---
SELECT
    *,
    CASE WHEN leadtime_vt > 10 THEN 'atraso' ELSE 'normal' END AS vt_em_atraso,
    CASE WHEN leadtime_mediacao > 10 THEN 'atraso' ELSE 'normal' END AS med_em_atraso,
    CASE WHEN leadtime_ar > 5 THEN 'atraso' ELSE 'normal' END AS ar_em_atraso,
    CASE WHEN leadtime_ac > 5 THEN 'atraso' ELSE 'normal' END AS ac_em_atraso,
    CASE WHEN leadtime_prazo_pp_iq > 10 THEN 'atraso' ELSE 'normal' END AS prazo_pp_iq_em_atraso,
    CASE WHEN leadtime_budget_approval > 5 THEN 'atraso' ELSE 'normal' END AS ba_em_atraso,
    CASE WHEN leadtime_erc > 3 THEN 'atraso' ELSE 'normal' END AS erc_em_atraso,
    COALESCE(leadtime_mediacao, DATE_DIFF(day, med_created_dt, '{load_start_date}')) AS aging_med,
    YEAR(CURRENT_DATE - 1) AS year,
    MONTH(CURRENT_DATE - 1) AS month,
    DAY(CURRENT_DATE - 1) AS day,
    NOW() AS ts_load
FROM
    mascara
WHERE
    termination_request >= DATE('2025-01-01')
    AND termination_request >= DATE('{load_start_date}') - INTERVAL '12' MONTH 
    AND (spoc_class IS NOT NULL OR med_ticket IS NOT NULL)
