WITH actual_pps AS (
    SELECT 
        dohq.dt_houses_owned AS date,
        DATE_TRUNC('month', dohq.dt_houses_owned) AS month_year,
        dohq.id_owner AS sk_owner,
        dohq.id_account_manager,
        dohq.dt_houses_owned,
        doc.cluster_pp_multi,
        dohq.ongoing_houses,
        ROW_NUMBER() OVER (
            PARTITION BY dohq.id_owner, DATE_TRUNC('month', dohq.dt_houses_owned)
            ORDER BY dohq.dt_houses_owned DESC
        ) AS order_month
    FROM datalake_pro_owners.daily_owner_houses_quantity_history dohq
    LEFT JOIN datalake_pro_owners.daily_owner_category doc
        ON dohq.id_owner = doc.id_owner
        AND dohq.dt_houses_owned = doc.dt_owner_category
    LEFT JOIN dw_public.dim_user dup 
        ON dup.sk_user = dohq.id_owner
    WHERE dohq.is_pp_multi_active
),
ppm_ongoing_rentals AS (
    SELECT DISTINCT
        fhl.sk_owner,
        CASE 
            WHEN ppmh_month.cluster_pp_multi LIKE '%Long-tail%' THEN 'Long-Tail'
            WHEN ppmh_month.cluster_pp_multi LIKE '%Corporate%' THEN 'Corporate'
            WHEN ppmh_month.cluster_pp_multi LIKE '%Investors%' THEN 'Investors'
            WHEN ppmh_month.cluster_pp_multi LIKE '%Short Stay%' THEN 'Short-Stay'
            ELSE 'Amateur'
        END AS cluster_ppm,
        dc.sk_contract
    FROM dw_rent.dim_contract dc
    JOIN dw_public.dim_date dd 
        ON dd.date BETWEEN COALESCE(dc.dt_start, dc.dt_entrance)
        AND COALESCE(dc.dt_annulment, DATE('{load_start_date}') - INTERVAL '1' DAY)
    LEFT JOIN dw_public.fact_house_listings fhl 
        ON fhl.sk_contract = dc.sk_contract
    JOIN actual_pps ppmh
        ON ppmh.sk_owner = fhl.sk_owner
        AND dd.date = ppmh.dt_houses_owned 
    LEFT JOIN actual_pps ppmh_month
        ON ppmh_month.sk_owner = fhl.sk_owner
        AND dd.month_start = ppmh_month.month_year
        AND ppmh_month.order_month = 1
    WHERE 
        dc.status IN ('Ativo', 'Finalizado')
        AND dd.date = dd.month_end
        AND COALESCE(dc.dt_start, dc.dt_entrance) < DATE('{load_start_date}')
        AND dd.date < DATE('{load_start_date}')
        AND dc.type <> 'DealOnly'
        AND EXTRACT(YEAR FROM dd.date) >= 2024
), db_terminator_offboarding AS (
  SELECT
    MAX(t.id) AS id_request,
    t.id_contract,
    MAX(t.ts_created) AS termination_Request,
    MAX(t.dt_termination) AS dt_termination,
    MAX(DATE(dc.ts_analyst_annulment_input)) AS ended_confirmed,
    MAX(
      CASE
        WHEN dt.id_exit_inspection IS NOT NULL THEN DATE(dt_last_inspection_synched)
      END
    ) AS inspected_date,
    MAX(dt.ts_termination_finished) AS ts_termination_finished,
    t.status,
    COALESCE(CAST(t.id_exit_inspection AS STRING), f.sk_inspection) AS id_exit_inspection,
    dt.has_repairs,
    dt.is_repair_tenant_duty,
    dt.repair_resolution,
    dt.repair_cost,
    CASE
      WHEN w.id_termination IS NOT NULL THEN 'Workflow'
      ELSE NULL
    END AS workflow,
    w.current_step,
    dt.reason,
    dhl.id_house,
    dc.is_exit_inspection_opted_out,
    dc.b2b_type,
    dc.status AS status_contrato,
    dr.city_group
  FROM
    datalake_terminator_clean.termination t
      LEFT JOIN datalake_offboarding.contract_termination dt
        ON dt.id_termination = t.id
        AND dt.status NOT IN ('CANCELED')
      LEFT JOIN datalake_terminator_clean.termination_workflow w
        ON w.id_termination = t.id
      LEFT JOIN dw_public.fact_house_listings fhl
        ON t.id_contract = fhl.sk_contract
      LEFT JOIN dw_public.dim_region dr
        ON fhl.sk_region = dr.sk_region
      LEFT JOIN dw_public.dim_house_listing dhl
        ON fhl.sk_house_listing = dhl.sk_house_listing
      LEFT JOIN dw_rent.dim_contract dc
        ON dc.sk_contract = t.id_contract
      LEFT JOIN dw_inspections.fact_inspection f
        ON f.sk_contract = t.id_contract
      LEFT JOIN dw_inspections.dim_inspection d
        ON f.sk_inspection = d.sk_inspection
        AND d.inspection_type IN ('offboarding', 'verification')
        AND d.status NOT IN ('cancelled')
  WHERE
    (
      (
        t.dt_termination >= DATE_ADD(WEEK, -50, DATE('{load_start_date}'))
        OR dt.ts_termination_finished >= DATE_ADD(WEEK, -50, DATE('{load_start_date}'))
      )
      AND (
        dt.ts_termination_finished <= DATE_ADD(WEEK, 1, DATE('{load_start_date}'))
        OR t.dt_termination <= DATE_ADD(WEEK, 10, DATE('{load_start_date}'))
      )
      AND t.status NOT IN ('CANCELED')
    )
    AND DC.country_code = 'BR'
    OR (
      t.dt_termination <= DATE_ADD(WEEK, 10, DATE('{load_start_date}'))
      AND t.status NOT IN ('CANCELED', 'DONE')
    )
    AND DC.country_code = 'BR'
    AND t.status NOT IN ('cancelled', 'CANCELED')
  GROUP BY
    2,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20,
    21
),
base_nps AS (
  SELECT
    ans.sk_nps_answer,
    disp.sk_user,
    disp.sk_contract,
    CASE
      WHEN camp.customer_type = 'IQ' THEN 'tenant'
      WHEN camp.customer_type = 'PP' THEN 'landlord'
      ELSE NULL
    END AS customer_type,
    CASE
      WHEN metric_group LIKE '%onboarding%' THEN 'onboarding'
      WHEN metric_group LIKE '%ongoing%' THEN 'ongoing'
      WHEN metric_group LIKE '%offboarding%' THEN 'offboarding'
      ELSE NULL
    END AS campanha_nps,
    disp.score,
    ans.score_category,
    ans.comment,
    ans.ts_answered,
    DATE_FORMAT(ans.ts_answered, 'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'') AS data_resposta_nps,
    pub.day,
    pub.month,
    pub.year,
    c.dt_start AS data_inicio_contrato,
    CONCAT(CAST(disp.sk_user AS STRING), CAST(disp.sk_contract AS STRING)) AS user_contrato,
    c.rent,
    DATE(c.ts_signature) AS contract_signed,
    DATE(COALESCE(c.dt_start,c.dt_entrance)) AS entrance_date,
    DATE(dt.ts_created) AS termination_request,
    DATE(dt.dt_termination) AS termination_date,
    DATE(dt.ts_termination_finished) AS termination_finished,
    case when multi.sk_contract is not null then TRUE else FALSE end as pro_owner_property,
    CASE
      WHEN DAYOFWEEK(ans.ts_answered) = 1 THEN ans.ts_answered
      ELSE DATE_ADD(DAY, -(dayofweek(ans.ts_answered) - 1), ans.ts_answered)
    END AS inicio_semana_nps
  FROM
    dw_customer_satisfaction.dim_nps_answer AS ans
      LEFT JOIN dw_customer_satisfaction.fact_nps_dispatches AS disp
        ON ans.sk_nps_answer = disp.sk_nps_answer
      INNER JOIN dw_customer_satisfaction.dim_nps_campaign AS camp
        ON disp.sk_nps_campaign = camp.sk_nps_campaign
      INNER JOIN dw_public.dim_date AS pub
        ON disp.sk_answered_date = pub.sk_date
      LEFT JOIN dw_rent.dim_contract c
        ON c.sk_contract = disp.sk_contract
      LEFT JOIN datalake_terminator_clean.termination t 
        ON t.id_contract = disp.sk_contract
         AND t.status NOT IN ('cancelled')
      LEFT JOIN datalake_offboarding.contract_termination dt 
        ON dt.id_termination = t.id
        AND dt.status NOT IN ('CANCELED')
      LEFT JOIN ppm_ongoing_rentals multi 
        ON multi.sk_contract = c.sk_contract
  WHERE
    disp.sk_nps_answer > 0
    AND camp.metric_group IN ('iqoffboarding', 'ppoffboarding')
    AND camp.business_context = 'forRent'
    AND year >= 2024
    AND ans.ts_answered >= DATE('2024-01-01')
),
base_off AS (
  SELECT DISTINCT
    t.id_contract,
    t.termination_request,
    t.dt_termination,
    t.is_exit_inspection_opted_out,
    CASE
      WHEN t.is_exit_inspection_opted_out = TRUE THEN NULL
      ELSE t.is_repair_tenant_duty
    END AS is_repair_tenant_duty,
    t.ended_confirmed,
    DATE(t.ts_termination_finished) AS dt_tf,
    CASE
      WHEN DATE(t.ts_termination_finished) < t.dt_termination THEN 0
      ELSE DATE_DIFF(DAY, t.dt_termination, DATE(t.ts_termination_finished))
    END AS lt_off,
    t.repair_resolution,
    t.city_group
  FROM
    db_terminator_offboarding t
),
listings AS (
  SELECT
    hl.id_house,
    hl.sk_house_listing,
    dc.sk_contract,
    TO_CHAR(DATE(dc.ts_signature), 'yyyy-mm-dd') AS ts_signature,
    TO_CHAR(DATE(COALESCE(dc.dt_start, dc.dt_entrance)), 'yyyy-mm-dd') AS inicio_contrato,
    TO_CHAR(DATE(dc.dt_annulment), 'yyyy-mm-dd') AS dt_annulment,
    TO_CHAR(DATE(hl.ts_early_demand_started), 'yyyy-mm-dd') AS early_demand_started,
    rl.sk_house_listing AS sk_relisting,
    TO_CHAR(DATE(rl.ts_listing_version_start), 'yyyy-mm-dd') AS dt_relisting
  FROM
    dw_rent.dim_contract dc
      LEFT JOIN dw_rent.fact_listing_rent_flows AS fhl
        ON fhl.sk_contract = dc.sk_contract
      LEFT JOIN dw_public.dim_house_listing AS hl
        ON hl.sk_house_listing = fhl.sk_house_listing
      LEFT JOIN dw_public.dim_house_listing AS rl
        ON rl.sk_house_listing = hl.sk_house_listing + 1
  WHERE
    dc.status = 'Finalizado'
    AND (
      dc.country_code <> 'MX'
      OR dc.country_code IS NULL
    )
    AND TO_CHAR(DATE(dc.dt_annulment), 'yyyy-mm-dd') >= '2022-01-01'
),
base_rescisoes AS (
  SELECT
    id_house,
    id_contract,
    DATE(ts_created) AS dt_rescission_created,
    dt_termination,
    DATE(ts_canceled) AS dt_rescission_canceled,
    status AS status_rescission,
    is_before_contract_start,
    requested_by,
    id_region,
    reason
  FROM
    datalake_offboarding.contract_termination ct
  WHERE
    ts_created >= DATE('2021-01-01')
    AND dt_termination <= DATE('{load_start_date}')
    AND status <> 'CANCELED'
),
bd_relisting AS (
  SELECT DISTINCT
    dc.sk_contract AS contrato_relisting,
    CASE
      WHEN br.id_house IS NOT NULL THEN 'Early-Listing'
      WHEN br2.id_house IS NOT NULL THEN 'Re-Listing'
      ELSE NULL
    END AS early_listing,
    COUNT(l.sk_relisting) AS indicador_relisting
  FROM
    listings l
      LEFT JOIN dw_rent.fact_listing_rent_flows fhl
        ON fhl.sk_house_listing = l.sk_relisting
      LEFT JOIN dw_public.dim_house_listing hl
        ON hl.sk_house_listing = fhl.sk_house_listing
      LEFT JOIN dw_rent.dim_contract dc
        ON dc.sk_contract = fhl.sk_contract
      INNER JOIN dw_public.dim_date dd
        ON dd.sk_date = fhl.sk_offer_approved_date
      INNER JOIN dw_public.dim_date dd2
        ON dd2.sk_date = fhl.sk_offer_submitted_date
      LEFT JOIN base_rescisoes AS br
        ON br.id_house = hl.id_house
        AND dd2.date >= br.dt_rescission_created
        AND dd2.date < br.dt_termination
      LEFT JOIN base_rescisoes AS br2
        ON br2.id_house = hl.id_house
        AND dd2.date >= br2.dt_termination
  WHERE
    dc.sk_contract > 0
    AND dc.status <> 'Cancelado'
  GROUP BY
    1,
    2
),
repair_termination AS (
  SELECT
    sk_contract,
    sk_termination,
    sk_house,
    ts_termination_finished AS dt_termination_rt,
    total_tentant_repair_ar,
    repairs_added_by_owner_review,
    repairs_exempted_by_owner_review,
    total_tentant_repair_review,
    repairs_exempted_ac,
    repairs_absorbed_ac,
    total_tentant_repair_ac,
    CASE
      WHEN repairs_absorbed_ac + total_tentant_repair_ac > 0 THEN TRUE
      WHEN repairs_absorbed_ac + total_tentant_repair_ac <= 0 THEN FALSE
    END AS com_ou_sem_reparos
  FROM
    dw_offboarding.fact_terminations
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY sk_contract ORDER BY sk_termination_date DESC) = 1
),
bd_intermediacao AS (
  SELECT
    ft.sk_ticket,
    ft.sk_contract,
    agt.email,
    CASE
      WHEN agt.email LIKE '%atento%' THEN 'atento'
      WHEN agt.email LIKE '%webhelp%' THEN 'webhelp'
      ELSE 'outra'
    END AS parceira,
    dimt.group_name,
    ft.ts_created,
    ft.ts_solved,
    CAST(
      GET_JSON_OBJECT(
        dimt.custom_fields, '$["Como os reparos foram ou vão ser solucionados?"]'
      ) AS STRING
    ) AS repair_resolution,
    CAST(
      REPLACE(
        CAST(
          GET_JSON_OBJECT(
            dimt.custom_fields, '$["Valor original do orçamento da tabela"]'
          ) AS STRING
        ),
        '.',
        ''
      ) AS DECIMAL
    ) AS first_bud_price,
    CAST(
      REPLACE(
        CAST(
          GET_JSON_OBJECT(
            dimt.custom_fields, '$["Orçamento Final - Valor total que o PP será reembolsado"]'
          ) AS STRING
        ),
        '.',
        ''
      ) AS DECIMAL
    ) AS final_reimbursement_pp_value,
    CAST(
      REPLACE(
        CAST(GET_JSON_OBJECT(dimt.custom_fields, '$["Valor que será pago pelo IQ"]') AS STRING),
        '.',
        ''
      ) AS DECIMAL
    ) AS final_reimbursement_value_iq_pay,
    CAST(
      GET_JSON_OBJECT(dimt.custom_fields, '$["Qualidade do laudo"]') AS STRING
    ) AS contest_quality,
    CAST(GET_JSON_OBJECT(dimt.custom_fields, '$["Tipo de Cliente"]') AS STRING) AS customer_type
  FROM
    dw_customer_support.fact_tickets ft
      LEFT JOIN dw_customer_support.dim_analyst agt
        ON ft.sk_last_analyst = agt.sk_analyst
      LEFT JOIN dw_customer_support.dim_ticket dimt
        ON ft.sk_ticket = dimt.sk_ticket
  WHERE
    DATE(ft.ts_created) >= DATE('2023-01-01')
    AND dimt.group_name = 'Offboarding Reparos [OFF] [POS] [BACK]'
    AND dimt.tags NOT LIKE '%ezsend%'
    AND CAST(GET_JSON_OBJECT(dimt.custom_fields, '$["Tipo de Demanda"]') AS STRING) IN (
      'demanda_pos_saida'
    )
    AND dimt.tags NOT LIKE '%closed_by_merge%'
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY ft.sk_contract ORDER BY ft.ts_created ASC) = 1
),
bd_tkt_escalado AS (
  SELECT
    ft.sk_ticket,
    ft.sk_user,
    ft.sk_contract,
    dep.channel,
    dep.department,
    ft.ts_created,
    ft.ts_closed,
    ft.ts_solved,
    agt.email,
    CASE
      WHEN agt.email LIKE '%atento%' THEN 'atento'
      WHEN agt.email LIKE '%webhelp%' THEN 'webhelp'
      ELSE 'outra'
    END AS parceira,
    csat.first_csat_score,
    csat.first_csat_comment,
    csat.ts_first_responde,
    dt.customer_type,
    dt.request_type,
    dt.theme,
    dt.theme_detail,
    dt.motivation,
    dt.step_tag,
    dt.sub_journey
  FROM
    dw_customer_support.fact_tickets ft
      LEFT JOIN dw_customer_support.dim_taxonomy dt
        ON ft.sk_taxonomy = dt.sk_taxonomy
      LEFT JOIN dw_customer_support.dim_department dep
        ON ft.sk_main_department = dep.sk_department
      LEFT JOIN dw_customer_support.dim_analyst agt
        ON agt.sk_analyst = ft.sk_last_analyst
      LEFT JOIN dw_customer_support.dim_ticket dimt
        ON ft.sk_ticket = dimt.sk_ticket
      LEFT JOIN dw_satisfaction_rating.fact_ticket_csat csat
        ON ft.sk_ticket = csat.sk_ticket
      LEFT JOIN base_nps AS nps
        ON nps.sk_user = ft.sk_user
  WHERE
    dep.department = 'Atendimento Escalado [OFF] [POS] [BACK]'
    AND ft.ts_created >= DATE((nps.data_inicio_contrato) - INTERVAL '30' day)
    AND ft.ts_created BETWEEN DATE((nps.ts_answered) - INTERVAL '90' day) AND DATE(nps.ts_answered)
    AND ft.sk_user <> -1
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY ft.sk_user ORDER BY ft.ts_created DESC) = 1
),
bd_front_off AS (
  SELECT
    tkt.sk_user,
    MAX(
      CASE
        WHEN
          csat.first_csat_score IS NOT NULL
          AND csat.first_csat_score < 3
        THEN
          1
        ELSE 0
      END
    ) AS have_dsat_front,
    COALESCE(
      COUNT(DISTINCT
        CASE
          WHEN tkt.is_ticket_rate = TRUE THEN tkt.sk_ticket
          ELSE NULL
        END
      ),
      0
    ) AS vol_ticket_tr_L3M,
    COALESCE(
      COUNT(DISTINCT
        CASE
          WHEN
            tkt.is_ticket_rate = TRUE
            AND tkt.front_or_back = 'front'
          THEN
            tkt.sk_ticket
          ELSE NULL
        END
      ),
      0
    ) AS vol_ticket_tr_L3M_front,
    COALESCE(
      COUNT(DISTINCT
        CASE
          WHEN
            tkt.is_ticket_rate = TRUE
            AND tkt.front_or_back = 'front'
            AND dt.theme = 'rent_contract_termination'
          THEN
            tkt.sk_ticket
          ELSE NULL
        END
      ),
      0
    ) AS theme_contract_termination,
    COALESCE(
      COUNT(DISTINCT
        CASE
          WHEN
            tkt.is_ticket_rate = TRUE
            AND tkt.front_or_back = 'front'
            AND dt.theme = 'rent_termination_inspection'
          THEN
            tkt.sk_ticket
          ELSE NULL
        END
      ),
      0
    ) AS theme_termination_inspection,
    COALESCE(
      COUNT(DISTINCT
        CASE
          WHEN
            tkt.is_ticket_rate = TRUE
            AND tkt.front_or_back = 'front'
            AND dt.theme = 'rental_termination_house_repairs_and_improvements'
          THEN
            tkt.sk_ticket
          ELSE NULL
        END
      ),
      0
    ) AS theme_repairs,
    COALESCE(
      COUNT(DISTINCT
        CASE
          WHEN
            tkt.is_ticket_rate = TRUE
            AND tkt.front_or_back = 'front'
            AND dt.theme IN (
              'rental_termination_billet_payment',
              'rental_termination_condo',
              'rental_termination_utility_bills',
              'rental_value_transfer',
              'rent_billet_detailing'
            )
          THEN
            tkt.sk_ticket
          ELSE NULL
        END
      ),
      0
    ) AS theme_contas_consumo,
    COALESCE(
      COUNT(DISTINCT
        CASE
          WHEN
            tkt.is_ticket_rate = TRUE
            AND tkt.front_or_back = 'front'
            AND dt.theme NOT IN (
              'rent_contract_termination',
              'rent_termination_inspection',
              'rental_termination_house_repairs_and_improvements',
              'rental_termination_billet_payment',
              'rental_termination_condo',
              'rental_termination_utility_bills',
              'rental_value_transfer',
              'rent_billet_detailing'
            )
          THEN
            tkt.sk_ticket
          ELSE NULL
        END
      ),
      0
    ) AS theme_front_Others
  FROM
    dw_customer_support.fact_tickets tkt
      LEFT JOIN dw_customer_support.dim_department dd
        ON dd.sk_department = tkt.sk_main_department
      LEFT JOIN dw_customer_support.dim_taxonomy dt
        ON dt.sk_taxonomy = tkt.sk_taxonomy
      LEFT JOIN base_nps nps
        ON tkt.sk_user = nps.sk_user
      LEFT JOIN dw_satisfaction_rating.fact_ticket_csat as csat
        ON tkt.sk_ticket = csat.sk_ticket
  WHERE
    tkt.sk_user > 0
    AND tkt.ts_created >= DATE((nps.data_inicio_contrato) - INTERVAL '30' day)
    AND tkt.ts_created BETWEEN DATE((nps.ts_answered) - INTERVAL '90' day) AND DATE(nps.ts_answered)
    AND journey_step = 'Offboarding'
  GROUP BY
    1
),
status AS (
  SELECT DISTINCT
    fhls.*
  FROM
    dw_offboarding.fact_house_listing_terminations as tr
      LEFT JOIN dw_public.dim_date AS dd
        ON tr.sk_next_house_listing_publication_date = dd.sk_date
      RIGHT JOIN dw_rent.fact_house_listing_status fhls
        ON fhls.sk_house_listing / 1000 = tr.sk_house_listing / 1000
        AND DATE(fhls.ts_status_start) >= dd.`date`
  WHERE
    (
      fhls.ts_status_end IS NULL
      OR fhls.ts_status_start <> fhls.ts_status_end
    )
    AND fhls.is_last_status_of_day = TRUE
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY fhls.sk_house_listing / 1000 ORDER BY fhls.ts_status_start DESC)
    = 1
),
status_ended_rental AS (
  SELECT DISTINCT
    sk_contract,
    fhlt.sk_house_listing,
    erc.date AS erc_date,
    rl.date AS relisting_date,
    cs.date AS contract_signed_date,
    CASE
      WHEN
        st.status_history IN ('UNPUBLISHED', 'OPTED_OUT', 'SUSPENDED')
        AND status_change_reason NOT IN (
          'ContractDraft', 'HouseReserved', 'PaidGuarantee', 'RENTED'
        )
        AND fhlt.sk_next_contract_signature_date = -1
      THEN
        DATE(st.ts_status_start)
    END AS churn_date,
    CASE
      WHEN
        fhlt.sk_next_contract_signature_date != -1
        AND cs.date <= DATE_ADD(DAY, 28, erc.date)
      THEN
        TRUE
      ELSE FALSE
    END AS re_rental_4W,
    CASE
      WHEN
        st.status_history IN ('UNPUBLISHED', 'OPTED_OUT', 'SUSPENDED')
        AND status_change_reason NOT IN (
          'ContractDraft', 'HouseReserved', 'PaidGuarantee', 'RENTED'
        )
        AND fhlt.sk_next_contract_signature_date = -1
      THEN
        TRUE
      WHEN fhlt.sk_next_house_listing_publication_date = -1 THEN TRUE
      ELSE FALSE
    END AS churn,
    CASE
      WHEN
        (
          st.status_history = 'SUSPENDED'
          AND st.status_change_reason = 'RENTED'
        )
        OR fhlt.sk_next_contract_signature_date != -1
      THEN
        'RENTED'
      ELSE st.status_history
    END AS status,
    CASE
      WHEN
        (
          st.status_history = 'SUSPENDED'
          AND st.status_change_reason = 'RENTED'
        )
        OR fhlt.sk_next_contract_signature_date != -1
      THEN
        '-'
      WHEN
        status_change_reason IN ('ContractDraft', 'HouseReserved', 'PaidGuarantee')
      THEN
        'Negociação avançada'
      ELSE st.status_change_reason
    END AS status_reason
  FROM
    dw_offboarding.fact_house_listing_terminations fhlt
      LEFT JOIN status st
        ON st.sk_house_listing = fhlt.sk_next_house_listing_consolidated
        AND DATE_ADD(DAY, -1, DATE('{load_start_date}')) >= st.ts_status_start
        AND DATE_ADD(DAY, -1, DATE('{load_start_date}')) <= COALESCE(st.ts_status_end, DATE('{load_start_date}'))
      LEFT JOIN dw_public.dim_date erc
        ON erc.sk_date = fhlt.sk_ended_rental_confirmed_date
      LEFT JOIN dw_public.dim_date rl
        ON rl.sk_date = fhlt.sk_next_house_listing_publication_date
      LEFT JOIN dw_public.dim_date cs
        ON cs.sk_date = fhlt.sk_next_contract_signature_date
      LEFT JOIN dw_offboarding.dim_termination dt USING (sk_termination)
  WHERE
    dt.status != 'CANCELED'
)
SELECT DISTINCT
  nps.sk_nps_answer AS feedback_id,
  nps.sk_user AS author_id,
  CONCAT(CAST(nps.sk_contract AS STRING), '_', nps.customer_type) AS account_id,
  nps.customer_type,
  nps.campanha_nps AS nps_campanha,
  nps.score AS rating,
  nps.score_category,
  CAST(
    CASE
      WHEN NULLIF(nps.comment, '') IS NULL THEN NULL
      WHEN nps.score BETWEEN 0 AND 6 THEN CONCAT('Motivo da minha insatisfação: ', nps.comment)
      WHEN nps.score BETWEEN 7 AND 8 THEN CONCAT('Motivo da minha nota: ', nps.comment)
      WHEN nps.score BETWEEN 9 AND 10 THEN CONCAT('Motivo da minha satisfação: ', nps.comment)
      ELSE nps.comment
    END AS VARCHAR(100000000)
  ) AS text,
  date_format(nps.data_resposta_nps, 'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'') AS posted_at,
  CASE
    WHEN b.lt_off BETWEEN 0 AND 7 THEN '0d - 7d'
    WHEN b.lt_off BETWEEN 8 AND 20 THEN '8d - 20d'
    WHEN b.lt_off > 20 THEN '+20d'
    ELSE NULL
  END AS range_lt_off,
  b.is_exit_inspection_opted_out,
  CASE
    WHEN
      nps.ts_answered >= DATE('2024-05-01')
      AND com_ou_sem_reparos = TRUE
    THEN
      TRUE
    WHEN
      nps.ts_answered >= DATE('2024-05-01')
      AND (
        com_ou_sem_reparos = FALSE
        OR com_ou_sem_reparos IS NULL
      )
    THEN
      FALSE
    WHEN
      nps.ts_answered < DATE('2024-05-01')
      AND is_repair_tenant_duty = TRUE
    THEN
      TRUE
    WHEN
      nps.ts_answered < DATE('2024-05-01')
      AND (
        is_repair_tenant_duty = FALSE
        OR is_repair_tenant_duty IS NULL
      )
    THEN
      FALSE
  END AS com_ou_sem_reparos,
  CASE
    WHEN DATE_DIFF(DAY, nps.data_inicio_contrato, b.dt_termination) <= 182 THEN '0 - 6m'
    WHEN
      DATE_DIFF(DAY, nps.data_inicio_contrato, b.dt_termination) > 180
      AND DATE_DIFF(DAY, nps.data_inicio_contrato, b.dt_termination) <= 365
    THEN
      '6m - 1a'
    WHEN
      DATE_DIFF(DAY, nps.data_inicio_contrato, b.dt_termination) > 365
      AND DATE_DIFF(DAY, nps.data_inicio_contrato, b.dt_termination) <= 730
    THEN
      '1a - 2a'
    WHEN DATE_DIFF(DAY, nps.data_inicio_contrato, b.dt_termination) > 730 THEN '+2a'
    ELSE NULL
  END AS range_contract_lifetime,
  CASE
    WHEN nps.rent > 2500 THEN '+R$ 2.5k'
    WHEN nps.rent <= 2500 THEN 'Até R$ 2.5k'
    ELSE NULL
  END AS range_rent,
  CASE
    WHEN rlst.contrato_relisting > 0 THEN rlst.early_listing
    ELSE NULL
  END AS relisting,
  CASE
    WHEN COUNT(DISTINCT inter.sk_ticket) > 0 THEN TRUE
    ELSE FALSE
  END AS intermed,
  CASE
    WHEN inter.parceira IS NULL THEN 'sem med'
    ELSE inter.parceira
  END AS parceira_intermed,
  CASE
    WHEN COUNT(DISTINCT esc.sk_ticket) > 0 THEN TRUE
    ELSE FALSE
  END AS nps_off_escalado,
  CASE
    WHEN esc.parceira IS NULL THEN 'sem esc'
    ELSE esc.parceira
  END AS parceira_escalado,
  CASE
    WHEN front.vol_ticket_tr_L3M_front IS NULL THEN 'FALSE'
    WHEN front.vol_ticket_tr_L3M_front = 0 THEN 'FALSE'
    ELSE 'TRUE'
  END AS nps_off_tickets_front,
  CASE
    WHEN
      front.vol_ticket_tr_L3M_front > 0
      AND front.vol_ticket_tr_L3M_front <= 2
    THEN
      '1 - 2 Tickets'
    WHEN front.vol_ticket_tr_L3M_front > 2 THEN '+3 Tickets'
    ELSE 'Sem Tickets'
  END AS nps_off_range_tickets_front,
  inter.repair_resolution AS nps_off_repair_resolution,
  CASE
    WHEN inter.first_bud_price <= 0.5 THEN 'Até R$ 500'
    WHEN
      inter.first_bud_price > 500
      AND inter.first_bud_price <= 1000
    THEN
      'R$ 500 - R$ 1k'
    WHEN
      inter.first_bud_price > 1000
      AND inter.first_bud_price <= 2000
    THEN
      'R$ 1k - R$ 2k'
    WHEN inter.first_bud_price > 2000 THEN '+R$ 2k'
    ELSE NULL
  END AS nps_off_range_repair_value,
  CASE
    WHEN inter.first_bud_price / nps.rent <= 0.5 THEN 'Até 50%'
    WHEN
      inter.first_bud_price / nps.rent > 0.5
      AND inter.first_bud_price / nps.rent <= 1
    THEN
      '50% - 100%'
    WHEN inter.first_bud_price / nps.rent > 1 THEN '+100%'
    ELSE NULL
  END AS nps_off_range_repair_valuerent,
  CONCAT_WS(
    ' | ',
    CASE
      WHEN front.theme_contract_termination > 0 THEN 'Contract Termination'
    END,
    CASE
      WHEN front.theme_termination_inspection > 0 THEN 'Termination Inspection'
    END,
    CASE
      WHEN front.theme_repairs > 0 THEN 'Repairs'
    END,
    CASE
      WHEN front.theme_contas_consumo > 0 THEN 'Contas Consumo'
    END,
    CASE
      WHEN front.theme_front_Others > 0 THEN 'Front Others'
    END,
    CASE
      WHEN front.vol_ticket_tr_L3M_front = 0 THEN 'Front Seamless'
    END
  ) AS nps_off_taxonomy,
  b.city_group,
  CASE
    WHEN ser.re_rental_4W != TRUE THEN FALSE
    ELSE TRUE
  END AS re_rental,
  CASE
    WHEN dt.is_spoc_contract = TRUE THEN TRUE
    ELSE FALSE
  END AS spoc,
  CASE
    WHEN churn_date < nps.ts_answered THEN TRUE
    ELSE FALSE
  END AS churn,
  nps.contract_signed,
  nps.entrance_date,
  MAX(nps.termination_request) AS termination_request,
  MAX(nps.termination_date) AS termination_date,
  MAX(nps.termination_finished) AS termination_finished,
  nps.pro_owner_property,
  year(nps.data_resposta_nps) AS year,
  month(nps.data_resposta_nps) AS month,
  day(nps.data_resposta_nps) AS day,
  NOW() AS ts_load
FROM
  base_nps AS nps
    LEFT JOIN base_off AS b
      ON b.id_contract = nps.sk_contract
    LEFT JOIN bd_relisting AS rlst
      ON rlst.contrato_relisting = nps.sk_contract
    LEFT JOIN bd_intermediacao AS inter
      ON inter.sk_contract = nps.sk_contract
    LEFT JOIN bd_tkt_escalado AS esc
      ON esc.sk_user = nps.sk_user
    LEFT JOIN bd_front_off AS front
      ON front.sk_user = nps.sk_user
    LEFT JOIN repair_termination AS rt
      ON rt.sk_contract = nps.sk_contract
    LEFT JOIN dw_offboarding.fact_terminations AS dt
      on dt.sk_contract = nps.sk_contract
    LEFT JOIN base_rescisoes AS resc
      ON resc.id_contract = nps.sk_contract
    LEFT JOIN status_ended_rental AS ser
      ON ser.sk_contract = nps.sk_contract
WHERE
  nps.data_resposta_nps >= DATE('{load_start_date}')
GROUP BY
  1,
  2,
  3,
  4,
  5,
  6,
  7,
  8,
  9,
  10,
  11,
  12,
  13,
  14,
  15,
  17,
  19,
  20,
  21,
  22,
  23,
  24,
  25,
  26,
  27,
  29,
  dt.is_spoc_contract,
  nps.data_resposta_nps,
  nps.contract_signed,
  nps.entrance_date,
  nps.pro_owner_property