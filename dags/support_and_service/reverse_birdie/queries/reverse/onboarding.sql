WITH filters AS (
  SELECT
    cast('2024-01-01' AS date) dt_ref
),
 actual_pps AS (
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
        ON dd.date BETWEEN COALESCE(dc.dt_start, dc.dt_entrance) AND COALESCE(dc.dt_annulment, '{load_start_date}' - INTERVAL '1' DAY)
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
        AND COALESCE(dc.dt_start, dc.dt_entrance) < '{load_start_date}'
        AND dd.date < '{load_start_date}'
        AND dc.type <> 'DealOnly'
        AND EXTRACT(YEAR FROM dd.date) >= 2024
),
onb_nps_infos AS (
  SELECT
    fnd.sk_nps_answer,
    fnd.sk_user,
    fnd.sk_contract,
    dna.comment,
    dnc.customer_type,
    fnd.score,
    dna.score_category,
    dna.ts_answered,
    dc.dt_start,
    dnc.metric_group,
    DATE(dc.ts_signature) AS contract_signed,
    DATE(COALESCE(dc.dt_start, dc.dt_entrance)) AS entrance_date,
    CASE WHEN multi.sk_contract IS NOT NULL THEN TRUE ELSE FALSE END AS pro_owner_property
  FROM
    dw_customer_satisfaction.fact_nps_dispatches fnd
  JOIN dw_customer_satisfaction.dim_nps_answer dna 
    ON fnd.sk_nps_answer = dna.sk_nps_answer
  JOIN dw_customer_satisfaction.dim_nps_campaign AS dnc 
    ON fnd.sk_nps_campaign = dnc.sk_nps_campaign
    AND dnc.metric_group IN ('iqonboarding', 'pponboarding')
    AND dnc.business_context = 'forRent'
  LEFT JOIN dw_rent.dim_contract dc 
    ON dc.sk_contract = fnd.sk_contract
  JOIN dw_public.dim_date AS dd 
    ON fnd.sk_answered_date = dd.sk_date
    AND dd.date >= DATE('2024-01-01')
  LEFT JOIN ppm_ongoing_rentals multi 
    ON multi.sk_contract = dc.sk_contract
  WHERE
    fnd.sk_nps_answer > 0
),
listing_infos AS (
  SELECT
    fhl.sk_house_listing,
    dhl.id_house sk_house,
    fhl.sk_contract,
    lag(fhl.sk_contract) over w_house sk_prev_contract,
    row_number() over w_house house_contract_rank,
    -- Can I use the last number of sk_house_listing?
    fhl.order_renting,
    dc.rent rent_value,
    dc.ts_signature,
    dc.dt_entrance,
    coalesce(dc.ts_analyst_annulment_input, dc.dt_annulment) dt_annulment,
    lag(
      cast(
        coalesce(dc.ts_analyst_annulment_input, dc.dt_annulment) AS date
      )
    ) over w_house dt_prev_annulment
  FROM
    dw_rent.fact_house_listings fhl
    LEFT JOIN dw_rent.dim_house_listing dhl ON fhl.sk_house_listing = dhl.sk_house_listing
    LEFT JOIN dw_rent.dim_contract dc ON fhl.sk_contract = dc.sk_contract
  WHERE
    fhl.sk_contract > -1
    AND fhl.country_code = 'BR' WINDOW w_house AS (
      PARTITION BY dhl.id_house
      ORDER BY
        dc.ts_signature
    )
),
contracts AS (
  SELECT
    li.sk_contract,
    li.dt_entrance,
    li.house_contract_rank,
    li.rent_value,
    date_diff(DAY, li.dt_prev_annulment, li.ts_signature) ndays_to_rerental,
    CASE
      WHEN date_diff(DAY, li.dt_prev_annulment, li.ts_signature) <= 84 THEN 1
      ELSE 0
    END flg_rerental_12w
  FROM
    listing_infos li --LEFT JOIN
),
closing_counts AS (
  SELECT
    fct.sk_contract,
    count(DISTINCT fct.sk_task) n_task_closed_manually
  FROM
    dw_crm.fact_closing_tasks fct
    JOIN dw_crm.dim_closing_task dct ON fct.sk_task = dct.sk_task
    AND dct.ts_completed IS NOT NULL
    AND dct.type = 'Manual'
  WHERE
    fct.sk_contract > 0
  GROUP BY
    1
),
onb_inspections AS (
  SELECT
    fi.sk_inspection,
    fi.sk_contract,
    fi.sk_booking,
    di.status inspection_status,
    fi.ts_inspected,
    fi.ts_synced,
    fi.ts_booking_cancelled,
    bi.ts_cancel_local,
    bi.is_first_booking_auto
  FROM
    dw_inspections.fact_inspection fi
    INNER JOIN dw_inspections.dim_inspection di ON fi.sk_inspection = di.sk_inspection
    AND di.inspection_type = 'onboarding'
    LEFT JOIN dw_public.dim_booking bi ON fi.sk_booking = bi.sk_booking
    AND bi.type like '%Vistoria%'
),
inspection_booking_cancelled_counts AS (
  SELECT
    oi.sk_contract,
    count(sk_contract) filter(
      WHERE
        oi.ts_cancel_local IS NOT NULL
        AND (
          not(oi.is_first_booking_auto)
          OR oi.is_first_booking_auto is NULL
        )
    ) n_insp_cancelled
  FROM
    onb_inspections oi
  GROUP BY
    1
),
inspection_review_counts AS (
  SELECT
    fi.sk_inspection,
    oi.sk_contract,
    oi.ts_inspected,
    oi.ts_synced,
    count(DISTINCT fia.sk_item_review) filter(
      WHERE
        coalesce(review_creator, reviewer_type) = 'TENANT'
        AND review_comment IS NOT NULL
    ) n_tcomments,
    count(DISTINCT fia.sk_item_media) filter(
      WHERE
        coalesce(review_creator, reviewer_type) = 'TENANT'
        AND media_type = 'PHOTO'
    ) n_tphotos,
    count(DISTINCT fia.sk_item_review) filter(
      WHERE
        coalesce(review_creator, reviewer_type) = 'OWNER'
        AND review_comment IS NOT NULL
    ) n_lcomments
  FROM
    dw_inspections.fact_item fi
    INNER JOIN dw_inspections.dim_item_group dig ON fi.sk_item_group = dig.sk_item_group
    AND dig.item_group_type not in ('room_overview', 'house_supply')
    INNER JOIN onb_inspections oi ON fi.sk_inspection = oi.sk_inspection
    AND oi.ts_synced >= (
      SELECT
        dt_ref - interval '1' month
      from
        filters
    )
    AND oi.inspection_status not in (
      'Nova',
      'cancelled',
      'scheduled',
      'ContratoCancelado'
    )
    LEFT JOIN dw_inspections.fact_item_attachment fia ON fi.sk_item = fia.sk_item
    LEFT JOIN dw_inspections.dim_item_review dir ON fia.sk_item_review = dir.sk_item_review
    LEFT JOIN dw_inspections.dim_item_media dim ON fia.sk_item_media = dim.sk_item_media
    LEFT JOIN (
      SELECT
        DISTINCT sk_reviewer,
        reviewer_type
      from
        dw_inspections.dim_reviewer
    ) dr ON fia.sk_reviewer = dr.sk_reviewer
  GROUP BY
    1,
    2,
    3,
    4
),
inspection_review_counts_ordered AS (
  SELECT
    *,
    row_number() over(
      PARTITION BY sk_contract
      ORDER BY
        ts_synced desc
    ) desc_rn
  FROM
    inspection_review_counts
),
nps_ticket_counts AS (
  SELECT
    oni.sk_nps_answer,
    oni.sk_user,
    oni.sk_contract,
    oni.sk_contract AS sk_contract_2,
    oni.customer_type,
    oni.score,
    oni.score_category,
    oni.ts_answered,
    DATE_FORMAT(
            oni.ts_answered,
            'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''
        ) AS data_resposta_nps,
    --oni.dt_start,
    oni.comment,
    oni.metric_group,
    --[REPAIRS]
    count(
      DISTINCT CASE
        WHEN ft.front_or_back = 'back'
        AND dd.team = 'Repairs/Ongoing Back' THEN ft.sk_ticket
        ELSE NULL
      END
    ) n_ticket_repairs_back,
    count(
      DISTINCT CASE
        WHEN ft.front_or_back = 'front'
        AND dd.team = 'Repairs/Ongoing Front' THEN ft.sk_ticket
        ELSE NULL
      END
    ) n_ticket_repairs_front,
    count(
      DISTINCT CASE
        WHEN dt.theme = 'ongoing_rental_house_repairs_and_improvements' THEN ft.sk_ticket
        ELSE NULL
      END
    ) AS n_ticket_repairs_theme,
    --[PAYMENTS]
    count(
      DISTINCT CASE
        WHEN dd.area = 'CX'
        AND ft.front_or_back = 'back'
        AND dd.team = 'Payments Ativo Back' THEN ft.sk_ticket
        ELSE NULL
      END
    ) n_ticket_payments_back,
    count(
      DISTINCT CASE
        WHEN dd.area = 'CX'
        AND ft.front_or_back = 'front'
        AND dd.team = 'Payments' THEN ft.sk_ticket
        ELSE NULL
      END
    ) n_ticket_payments_front,
    count(
      DISTINCT CASE
        WHEN ft.sk_main_department in (
          'Serv. Financeiros - IQ Paga/Captura de boletos [SO]',
          'Serv. Financeiros - Faturas [SO]',
          'Serv. Financeiros - Tarefas Invisíveis Correções [SO]',
          'Serv. Financeiros - Condomínio V0V8 [SO]',
          'Serv. Financeiros - Correções [SO]',
          'Serv. Financeiros - Reembolsos [SO]'
        ) THEN ft.sk_ticket
        ELSE NULL
      END
    ) n_ticket_payments_serfin,
    count(
      DISTINCT CASE
        WHEN dt.theme in (
          'rental_ongoing_condo',
          'rent_billet_detailing',
          'rental_value_transfer',
          'iptu_rent_property_tax',
          'partner_remuneration',
          'rental_value_transfer_missing',
          'ongoing_customer_records_edit_bank_details'
        ) THEN ft.sk_ticket
        ELSE NULL
      END
    ) n_ticket_payments_theme,
    count(
      DISTINCT CASE
        WHEN dt.theme in ('rental_ongoing_condo') THEN ft.sk_ticket
        ELSE NULL
      END
    ) n_ticket_rental_ongoing_condo,
    count(
      DISTINCT CASE
        WHEN dt.theme in ('rent_billet_detailing') THEN ft.sk_ticket
        ELSE NULL
      END
    ) n_ticket_rent_billet_detailing,
    count(
      DISTINCT CASE
        WHEN dt.theme in ('rental_value_transfer') THEN ft.sk_ticket
        ELSE NULL
      END
    ) n_ticket_rental_value_transfer,
    --[KEYS]
    count(
      DISTINCT CASE
        WHEN ft.sk_main_department in (
          'Solicitação de Movimentação Chaves [Corridas] [SO]',
          'Logística Chaves Onboarding [SO]',
          'Lockbox - Pedidos da FAQ [SO]',
          'Logística Chaves Offboarding [SO]'
        ) THEN ft.sk_ticket
        ELSE NULL
      END
    ) n_ticket_keys,
    count(
      DISTINCT CASE
        WHEN dt.theme_detail in (
          'rental_entrance_instructions_key_deliver',
          'rental_entrance_instructions_key_info_before_entrance',
          'rental_entrance_instructions_key_info_access_items',
          'rental_entrance_instructions_key_not_received',
          'rental_house_entry_conditions_confirm_delivery_keys',
          'rental_house_entry_conditions_where_keys_localization'
        ) THEN ft.sk_ticket
        ELSE NULL
      END
    ) n_ticket_keys_theme,
    --[CONSUMPTION BILLS]
    count(
      DISTINCT CASE
        WHEN dt.theme in ('rent_utility_bills') THEN ft.sk_ticket
        ELSE NULL
      END
    ) n_ticket_consumption_bills,
    --[MOVING]
    count(
      DISTINCT CASE
        WHEN dt.theme in (
          'rental_house_info_and_condo_rules',
          'confuse_communication',
          'owner_tenant_chat_usage',
          'site_and_app_usage',
          'rental_house_entry_conditions',
          'rental_ongoing_contract_data_edit',
          'ongoing_customer_records_management'
        )
        OR dt.theme_detail in (
          'rental_entrance_instructions_authorization_info',
          'rental_entrance_instructions_authorization',
          'rental_entrance_instructions_dash_list_info',
          'rental_entrance_instructions_correct_contract_address',
          'rental_entrance_instructions_include_residents',
          'rental_entrance_instructions_authorization_problem',
          'rental_entrance_instructions_include_residents_after_signature_info',
          'rental_entrance_instructions_dash_list_problem',
          'rental_entrance_instructions_resident_not_included',
          'rental_entrance_instructions_remove_items',
          'rental_entrance_instructions_remove_items_info',
          'rental_entrance_instructions_negotiate_items',
          'rental_entrance_instructions_items_not_removed'
        ) THEN ft.sk_ticket
        ELSE NULL
      END
    ) AS n_ticket_moving,
    --[PRE-CONTRACT: OTHER SUBJECTS]
    count(
      DISTINCT CASE
        WHEN dt.theme = 'documents_credit_analysis' THEN ft.sk_ticket
        ELSE NULL
      END
    ) n_ticket_credit_theme,
    count(
      DISTINCT CASE
        WHEN dt.theme = 'rental_proposal_management' THEN ft.sk_ticket
        ELSE NULL
      END
    ) n_ticket_proposal_theme,
    count(
      DISTINCT CASE
        WHEN dt.theme in (
          'rental_visit_management',
          'rent_revisit',
          'sale_visit_management'
        ) THEN ft.sk_ticket
        ELSE NULL
      END
    ) n_visis_theme,
    count(
      DISTINCT CASE
        WHEN dt.theme in (
          'rental_listing_register_management',
          'rent_listing_info',
          'photoshoot_confirmation',
          'rent_listing_search',
          'incomplete_rental_listing_management'
        ) THEN ft.sk_ticket
        ELSE NULL
      END
    ) n_ticket_listing_theme,
    --[CLOSING]
    count(
      DISTINCT CASE
        WHEN ft.sk_main_department in (
          'OPS - Closing Rental Assinatura',
          'Closing B2C [CLO] [PRE] [BACK]',
          'Closing B2B [CLO] [PRE] [BACK]]',
          'OPS - FUP Documentação Rental OA2DS [CLO] [PRE]',
          'Closing Rental Acompanhamento Dados PP',
          'Closing Rental Assinatura [PRE] [BACK]',
          'Closing Aluguel [BACK] [PRE]',
          'CX Closing [BACK] [PRE]',
          'Carteirização IQ [CLO] [PRE] [BACK]',
          'Carteirização IQ [CLO] [PRE] [BACK]',
          'CLO Buyer Activation [PRE]'
        ) THEN ft.sk_ticket
        ELSE NULL
      END
    ) n_ticket_closing,
    count(
      DISTINCT CASE
        WHEN dt.theme in (
          'rent_and_rental_management_contracts_signature',
          'rental_signed_contract_term_change',
          'send_active_rent_contract',
          'send_ongoing_contract_request',
          'rent_and_rental_management_contracts_model'
        ) THEN ft.sk_ticket
        ELSE NULL
      END
    ) n_ticket_contract_theme,
    -- Abertura de Temas Específicos
    count(
      DISTINCT CASE
        WHEN dt.theme in ('rent_and_rental_management_contracts_signature') THEN ft.sk_ticket
        ELSE NULL
      END
    ) n_rent_and_rental_management_contracts_signature,
    count(
      DISTINCT CASE
        WHEN dt.theme in ('rent_and_rental_management_contracts_model') THEN ft.sk_ticket
        ELSE NULL
      END
    ) n_rent_and_rental_management_contracts_model,
    count(
      DISTINCT CASE
        WHEN dt.theme in ('rent_revisit') THEN ft.sk_ticket
        ELSE NULL
      END
    ) n_rent_revisit,
    count(
      DISTINCT CASE
        WHEN ft.front_or_back = 'back'
        AND dd.team = 'front_cx_proposals' THEN ft.sk_ticket
        ELSE NULL
      END
    ) n_front_cx_proposals_back,
    count(
      DISTINCT CASE
        WHEN ft.front_or_back = 'front'
        AND dd.team = 'front_cx_proposals' THEN ft.sk_ticket
        ELSE NULL
      END
    ) n_front_cx_proposals_front,
    --[INSPECTIONS]
    count(
      DISTINCT CASE
        WHEN ft.sk_main_department = 'Agendamento Vistoria Entrada [SO]' THEN ft.sk_ticket
        ELSE NULL
      END
    ) n_ticket_inspection_book,
    count(
      DISTINCT CASE
        WHEN ft.sk_main_department = 'CX Vistoria [BACK]' THEN ft.sk_ticket
        ELSE NULL
      END
    ) n_ticket_inspection_back,
    count(
      DISTINCT CASE
        WHEN dt.theme = 'rent_entrance_inspection' THEN ft.sk_ticket
        ELSE NULL
      END
    ) n_ticket_inspection_theme,
    --[GENERAL]
    count(DISTINCT sk_ticket) flg_ticket_all
  FROM
    onb_nps_infos oni
    LEFT JOIN dw_customer_support.fact_tickets ft ON oni.sk_user = ft.sk_user
    AND ft.ts_sla_started between (oni.dt_start - interval '30' day) AND oni.ts_answered --ft.ts_sla_started <  oni.ts_answered --
    AND ft.sk_user > 0
    AND oni.ts_answered >= DATE('{load_start_date}' - interval '7' day)
    LEFT JOIN dw_customer_support.dim_department dd ON ft.sk_main_department = dd.sk_department
    LEFT JOIN dw_customer_support.dim_taxonomy dt ON ft.sk_taxonomy = dt.sk_taxonomy
    WHERE DATE(oni.ts_answered) >= DATE('{load_start_date}')
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
    11
),
offboarding AS (
  SELECT
    DISTINCT t.id_contract,
    t.id_house,
    t.dt_termination,
    t.ts_termination_finished,
    t.ts_created,
    t.requested_by,
    t.reason,
    CASE
      WHEN t.ts_termination_finished IS NULL THEN NULL
      WHEN t.ts_termination_finished < t.dt_termination THEN 0
      WHEN t.ts_termination_finished >= t.dt_termination THEN date_diff(DAY, t.dt_termination, t.ts_termination_finished)
      ELSE NULL
    END AS lt_off,
    t.is_exit_inspection_opted_out,
    CASE
      WHEN t.is_exit_inspection_opted_out = true THEN NULL
      ELSE t.is_repair_tenant_duty
    END AS is_repair_tenant_duty,
    row_number() over (
      PARTITION BY t.id_contract
      ORDER BY
        t.ts_termination_finished DESC,
        t.is_repair_tenant_duty DESC,
        t.ts_created DESC
    ) AS rk
  from
    datalake_offboarding.contract_termination t
),
rent_flow_offer AS (
  SELECT
    DISTINCT fhl.sk_house_listing,
    hl.id_house,
    fhl.sk_contract,
    fhl.sk_offer_approved_date,
    fhl.sk_offer_submitted_date,
    fhl.sk_visit_date,
    fhl.flg_visit_completed
  from
    dw_rent.fact_listing_rent_flows fhl
    LEFT JOIN dw_public.dim_house_listing AS hl ON hl.sk_house_listing = fhl.sk_house_listing
    INNER JOIN dw_public.dim_date dd2 ON dd2.sk_date = fhl.sk_offer_submitted_date
    LEFT JOIN offboarding t2 ON t2.id_house = hl.id_house
    AND dd2.date >= t2.ts_created
    AND dd2.date < t2.dt_termination
  WHERE
    t2.rk = NULL
    OR t2.rk = 1
),
rent_flow_vb AS (
  SELECT
    DISTINCT fhl.sk_house_listing,
    hl.id_house,
    fhl.sk_contract,
    fhl.sk_offer_approved_date,
    fhl.sk_offer_submitted_date,
    fhl.sk_visit_date,
    fhl.flg_visit_completed
  from
    dw_rent.fact_listing_rent_flows fhl
    LEFT JOIN dw_public.dim_house_listing AS hl ON hl.sk_house_listing = fhl.sk_house_listing
    INNER JOIN dw_public.dim_date dd2 ON dd2.sk_date = fhl.sk_visit_date
    LEFT JOIN offboarding t2 ON t2.id_house = hl.id_house
    AND dd2.date >= t2.ts_created
    AND dd2.date < t2.dt_termination
  WHERE
    t2.rk = NULL
    OR t2.rk = 1
),
rent_flow_vc AS (
  SELECT
    DISTINCT fhl.sk_house_listing,
    hl.id_house,
    fhl.sk_contract,
    fhl.sk_offer_approved_date,
    fhl.sk_offer_submitted_date,
    fhl.sk_visit_date,
    fhl.flg_visit_completed,
    count(
      CASE
        WHEN v.behavior in (
          'CONFIRMATION_TENANT_LIVING_REQUIRED',
          'CONFIRMATION_TENANT_LIVING_ASSURED'
        ) THEN v.id
        ELSE NULL
      END
    ) AS vc_occupied_property
  from
    dw_rent.fact_listing_rent_flows fhl
    LEFT JOIN dw_public.dim_house_listing AS hl ON hl.sk_house_listing = fhl.sk_house_listing
    INNER JOIN dw_public.dim_date dd2 ON dd2.sk_date = fhl.sk_visit_date
    LEFT JOIN offboarding t2 ON t2.id_house = hl.id_house
    AND dd2.date >= t2.ts_created
    AND dd2.date < t2.dt_termination
    LEFT JOIN datalake_ebdb_clean.booking b ON b.id_house = hl.id_house
    LEFT JOIN datalake_ebdb_clean.visit v ON v.id = b.id_visit
  WHERE
    (
      t2.rk = NULL
      OR t2.rk = 1
    )
    AND fhl.flg_visit_completed = true
  group by
    1,
    2,
    3,
    4,
    5,
    6,
    7
),
contrato_anterior AS (
  SELECT
    DISTINCT dhl.sk_house_listing,
    DATE_FORMAT(dhl.ts_listing_version_start, 'yyyy-mm-dd') AS dt_relisting,
    rl.sk_house_listing AS sk_house_listing_anterior,
    dc.sk_contract AS sk_contract_anterior,
    DATE_FORMAT(
      COALESCE(dc.ts_analyst_annulment_input, dc.dt_annulment),
      'yyyy-mm-dd'
    ) AS dt_ended_rental_confirmed,
    DATE_FORMAT(
      COALESCE(dc.ts_analyst_annulment_input, dc.dt_annulment), 'yyyy-mm-dd'
    ) AS date_erc,
    date_diff(
      DAY,
      date(
        COALESCE(dc.ts_analyst_annulment_input, dc.dt_annulment)
      ),
      dhl.ts_listing_version_start
    ) AS er2rl,
    DATE_FORMAT(dhl.ts_early_demand_started, 'yyyy-mm-dd') AS early_demand_started -- relisting
,
    DATE_FORMAT(dhl.ts_last_de_publication, 'yyyy-mm-dd') AS dt_despublicado -- relisting
,
    dc.rent,
    t.is_repair_tenant_duty,
    t.ts_termination_finished,CASE
      WHEN rfo.id_house IS NOT NULL THEN 'Offer before TD'
      ELSE NULL
    END AS early_demand_offer,CASE
      WHEN rfvb.id_house IS NOT NULL THEN 'VB before TD'
      ELSE NULL
    END AS early_demand_vb,CASE
      WHEN rfvc.id_house IS NOT NULL THEN 'VC before TD'
      ELSE NULL
    END AS early_demand_vc,CASE
      WHEN rfvc.vc_occupied_property > 0 THEN 'VC_occupied_property'
      ELSE NULL
    END AS vc_occupied_property,
    t.dt_termination,
    t.ts_created,
    row_number() over (
      PARTITION BY rl.sk_house_listing
      ORDER BY
        dc.sk_contract DESC,
        t.ts_termination_finished DESC
    ) AS rk
  from
    dw_public.dim_house_listing AS dhl
    LEFT JOIN dw_public.dim_house_listing AS rl ON rl.sk_house_listing = dhl.sk_house_listing - 1
    LEFT JOIN dw_rent.fact_listing_rent_flows AS fhl ON rl.sk_house_listing = fhl.sk_house_listing
    LEFT JOIN dw_rent.dim_contract AS dc ON fhl.sk_contract = dc.sk_contract
    LEFT JOIN datalake_offboarding.contract_termination t ON t.id_contract = dc.sk_contract
    LEFT JOIN rent_flow_offer rfo ON rfo.sk_house_listing = dhl.sk_house_listing
    LEFT JOIN rent_flow_vb rfvb ON rfvb.sk_house_listing = dhl.sk_house_listing
    LEFT JOIN rent_flow_vc rfvc ON rfvc.sk_house_listing = dhl.sk_house_listing
  WHERE
    dhl.listing_category_start = 'Re-Listing'
    AND dc.sk_contract > 0
    AND dc.status <> 'Cancelado'
),
contrato_anterior_new_relisting AS (
  SELECT
    DISTINCT dhl.sk_house_listing,
    DATE_FORMAT(dhl.ts_listing_version_start, 'yyyy-mm-dd') AS dt_relisting,
    rl.sk_house_listing AS sk_house_listing_anterior,
    dc.sk_contract AS sk_contract_anterior,
    DATE_FORMAT(
      COALESCE(dc.ts_analyst_annulment_input, dc.dt_annulment),
      'yyyy-mm-dd'
    ) AS dt_ended_rental_confirmed,
    date(
      COALESCE(dc.ts_analyst_annulment_input, dc.dt_annulment)
    ) AS date_erc,
    date_diff(
      DAY,
      date(
        COALESCE(dc.ts_analyst_annulment_input, dc.dt_annulment)
      ),
      dhl.ts_listing_version_start
    ) AS er2rl,
    DATE_FORMAT(dhl.ts_early_demand_started, 'yyyy-mm-dd') AS early_demand_started,
    DATE_FORMAT(dhl.ts_last_de_publication, 'yyyy-mm-dd') AS dt_despublicado,
    dc.rent,
    t.is_repair_tenant_duty,
    t.ts_termination_finished,CASE
      WHEN rfo.id_house IS NOT NULL THEN 'Offer before TD'
      ELSE NULL
    END AS early_demand_offer,CASE
      WHEN rfvb.id_house IS NOT NULL THEN 'VB before TD'
      ELSE NULL
    END AS early_demand_vb,CASE
      WHEN rfvc.id_house IS NOT NULL THEN 'VC before TD'
      ELSE NULL
    END AS early_demand_vc,CASE
      WHEN rfvc.vc_occupied_property > 0 THEN 'VC_occupied_property'
      ELSE NULL
    END AS vc_occupied_property,
    t.dt_termination,
    t.ts_created,
    row_number() over (
      PARTITION BY rl.sk_house_listing
      ORDER BY
        dc.sk_contract DESC,
        t.ts_termination_finished DESC
    ) AS rk
  from
    dw_public.dim_house_listing AS dhl
    LEFT JOIN dw_public.dim_house_listing AS rl ON rl.sk_house_listing = dhl.sk_house_listing - 1
    LEFT JOIN dw_rent.fact_listing_rent_flows AS fhl ON rl.sk_house_listing = fhl.sk_house_listing
    LEFT JOIN dw_rent.dim_contract AS dc ON fhl.sk_contract = dc.sk_contract
    LEFT JOIN datalake_offboarding.contract_termination t ON t.id_contract = dc.sk_contract
    LEFT JOIN rent_flow_offer rfo ON rfo.sk_house_listing = dhl.sk_house_listing
    LEFT JOIN rent_flow_vb rfvb ON rfvb.sk_house_listing = dhl.sk_house_listing
    LEFT JOIN rent_flow_vc rfvc ON rfvc.sk_house_listing = dhl.sk_house_listing
  WHERE
    dc.sk_contract > 0
    AND dc.status <> 'Cancelado'
),
inquilinos_em_contrato AS (
  SELECT
    fcp.sk_personal_document,
    fcp.sk_contract,
    fcp.contract_role,
    dhl.id_house,
    COALESCE(dc.dt_start, dc.dt_entrance) AS inicio_contrato,
    dc.dt_annulment AS fim_contrato,CASE
      WHEN LEAD(fcp.sk_contract) OVER(
        PARTITION BY fcp.sk_personal_document
        ORDER BY
          COALESCE(dc.dt_start, dc.dt_entrance)
      ) IS NOT NULL THEN 1
      ELSE NULL
    END AS is_retenant,CASE
      WHEN LEAD(fcp.sk_contract) OVER(
        PARTITION BY fcp.sk_personal_document
        ORDER BY
          COALESCE(dc.dt_start, dc.dt_entrance)
      ) IS NOT NULL
      AND dc.dt_annulment is NULL THEN 1
      WHEN dc.dt_annulment > LEAD(COALESCE(dc.dt_start, dc.dt_entrance)) OVER(
        PARTITION BY fcp.sk_personal_document
        ORDER BY
          COALESCE(dc.dt_start, dc.dt_entrance)
      ) THEN 1
      WHEN dc.dt_annulment <= LEAD(COALESCE(dc.dt_start, dc.dt_entrance)) OVER(
        PARTITION BY fcp.sk_personal_document
        ORDER BY
          COALESCE(dc.dt_start, dc.dt_entrance)
      )
      AND DATE_DIFF(
        DAY,
        dc.dt_annulment,
        LEAD(COALESCE(dc.dt_start, dc.dt_entrance)) OVER(
          PARTITION BY fcp.sk_personal_document
          ORDER BY
            COALESCE(dc.dt_start, dc.dt_entrance)
        )
      ) <= 84 THEN 1
      ELSE NULL
    END AS is_retenant_12W
  FROM
    dw_rent.fact_contract_people fcp
    LEFT JOIN dw_rent.dim_contract dc ON dc.sk_contract = fcp.sk_contract
    LEFT JOIN dw_public.fact_house_listings fhl ON fhl.sk_contract = dc.sk_contract
    LEFT JOIN dw_public.dim_house_listing dhl ON dhl.sk_house_listing = fhl.sk_house_listing
  WHERE
    fcp.contract_role in (
      'tenant'
      /*,'dweller'*/
    ) --AND fcp.is_contract_user = true
),
retenants AS (
  SELECT
    DISTINCT sk_contract,
    DATE_TRUNC('month', fim_contrato) AS fim_contrato,
    count(sk_personal_document) AS num_tenants,
    count(is_retenant) AS num_retenants,
    count(is_retenant_12W) AS num_retenants_12W
  FROM
    inquilinos_em_contrato
  GROUP BY
    1,
    2
),
tenant AS (
  SELECT
    ca.sk_contract_anterior,
    fcp.sk_user,
    fcp.sk_personal_document,
    fcp.contract_role
  from
    contrato_anterior ca
    LEFT JOIN dw_rent.fact_contract_people fcp ON ca.sk_contract_anterior = fcp.sk_contract
  WHERE
    contract_role = 'tenant' --AND is_first_contract = false
),
opt_out AS (
  SELECT
    t.id_contract,
    min(rev.ts_revision) AS ts_opt_out_flow
  FROM
    datalake_terminator_clean.termination t
    INNER JOIN datalake_ebdb_clean.contract c 
    ON c.id = t.id_contract
    LEFT JOIN datalake_ebdb_clean.listing_business_context_aud aud 
    ON aud.id_house = c.id_house
    AND aud.business_context = 'RENT'
    AND aud.suspension_reason = 'RELISTING'
    AND aud.mod_suspension_reason
    LEFT JOIN datalake_ebdb_user.user_revision_entity rev ON rev.id = aud.rev
    AND rev.ts_revision BETWEEN t.ts_created
    AND t.dt_vacancy
    AND rev.reason LIKE '[ED OPT-OUT]%'
  WHERE
    t.ts_created BETWEEN date('2024-05-01')
    AND '{load_start_date}' -- AND c.id_house = 893236927
  GROUP BY
    1
),
tb_reten AS (
  SELECT
    DISTINCT ans.sk_nps_answer,
    disp.sk_user,
    disp.sk_contract,
    camp.customer_type,CASE
      WHEN metric_group like '%onboarding%' THEN 'onboarding'
      WHEN metric_group like '%ongoing%' THEN 'ongoing'
      WHEN metric_group like '%offboarding%' THEN 'offboarding'
      ELSE NULL
    END AS campanha_nps,
    ans.score_category,
    ca.sk_house_listing_anterior,
    ca.sk_contract_anterior,
    DATE_FORMAT(
            ans.ts_answered,
            'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''
        ) AS data_resposta_nps,
CASE
      WHEN dhl.is_b2b = TRUE THEN 'B2B'
      WHEN dhl.is_for_rent = TRUE
      AND (
        dhl.consultant_type IS NOT NULL
        AND dhl.consultant_type <> 'Core'
      ) THEN dhl.consultant_type
      WHEN dhl.is_b2b = FALSE
      OR (
        dhl.consultant_type IS NULL
        OR dhl.consultant_type = 'Core'
      ) THEN 'FALSE'
    END AS is_b2b,
    DATE_FORMAT(dc.ts_signature, 'yyyy-mm-dd') AS dt_signature,
    COALESCE(dc.dt_start, dc.dt_entrance) AS dt_entrance,
    dhl.listing_category_start,
    dhl.sk_house_listing,
    ca.sk_house_listing_anterior,
    ca.sk_house_listing_anterior AS last_contract,
    ca.sk_contract_anterior AS sk_last_contract,
    ca.dt_ended_rental_confirmed,
    ca.dt_relisting,
    ca.dt_despublicado,
    rt.num_retenants,
    rt.num_retenants_12W,
    CASE
      WHEN disp.sk_user > 0
      AND ten.sk_user IS NOT NULL THEN 'Retenant'
      ELSE NULL
    END AS is_retenant,
    ca.early_demand_started,
    ca.is_repair_tenant_duty,
    ca.er2rl,
    ca.rent,
    CASE
      WHEN dhl.listing_category_start = 'Re-Listing'
      AND dhl.is_early_demand = true
      AND date(dc.ts_created) between date(dhl.ts_early_demand_started)
      AND date(ca.dt_termination) THEN 'Relisting ED (periodo)'
      WHEN dhl.listing_category_start = 'Re-Listing'
      AND dhl.is_early_demand = false THEN 'Re-Listing Comum'
      WHEN dhl.listing_category_start = 'First Listing' THEN dhl.listing_category_start
      ELSE 'Outros'
    END AS early_demand_contract,
    ca.early_demand_offer,
    ca.early_demand_vc,
    CASE
      WHEN dt.is_spoc_contract = TRUE THEN TRUE
      ELSE FALSE
    END AS spoc,
    ca.vc_occupied_property,
    to_char(date(o.ts_opt_out_flow), 'yyyy-mm-dd') AS early_demand_opt_out,
    dr.city_group,
    dr.city_name,CASE
      WHEN dr.city_group not in ('RMSP', 'Belo Horizonte', 'Porto Alegre')
      OR dr.city_group is NULL THEN 'Wave 1'
      WHEN (
        dr.city_group = 'RMSP'
        AND dr.city_name <> 'São Paulo'
      )
      OR dr.city_group = 'Belo Horizonte' THEN 'Wave 2'
      WHEN dr.city_name = 'São Paulo'
      OR dr.city_group = 'Porto Alegre' THEN 'Wave 3'
      ELSE 'Wave 1'
    END AS wave,CASE
      WHEN (
        dr.city_group not in ('RMSP', 'Belo Horizonte', 'Porto Alegre')
        OR dr.city_group is NULL
      )
      AND date(ca.ts_created) >= date('2024-06-24') THEN 'New model'
      WHEN (
        (
          dr.city_group = 'RMSP'
          AND dr.city_name <> 'São Paulo'
        )
        OR dr.city_group = 'Belo Horizonte'
      )
      AND date(ca.ts_created) >= date('2024-07-11') THEN 'New model'
      WHEN (
        dr.city_name = 'São Paulo'
        OR dr.city_group = 'Porto Alegre'
      )
      AND date(ca.ts_created) >= date('2024-07-18') THEN 'New model'
      ELSE 'Old model'
    END AS model
  from
    dw_customer_satisfaction.dim_nps_answer AS ans
  LEFT JOIN dw_customer_satisfaction.fact_nps_dispatches AS disp 
      ON ans.sk_nps_answer = disp.sk_nps_answer
  INNER JOIN dw_customer_satisfaction.dim_nps_campaign AS camp 
    ON disp.sk_nps_campaign = camp.sk_nps_campaign
  INNER JOIN dw_public.dim_date AS pub 
    ON disp.sk_answered_date = pub.sk_date
  LEFT JOIN dw_rent.dim_contract dc 
    ON dc.sk_contract = disp.sk_contract 
  LEFT JOIN dw_offboarding.fact_terminations AS dt
      ON dt.sk_contract = disp.sk_contract
  LEFT JOIN dw_public.fact_house_listings AS fhl 
    ON fhl.sk_contract = dc.sk_contract
  LEFT JOIN dw_public.dim_house_listing AS dhl 
    ON dhl.sk_house_listing = fhl.sk_house_listing
  Left join contrato_anterior ca 
    ON ca.sk_house_listing = dhl.sk_house_listing
  LEFT JOIN retenants rt 
    ON rt.sk_contract = ca.sk_contract_anterior
  LEFT JOIN tenant ten
    ON ten.sk_user = disp.sk_user
  LEFT JOIN opt_out o 
    ON o.id_contract = ca.sk_contract_anterior
  LEFT JOIN dw_public.dim_region dr 
    ON fhl.sk_region = dr.sk_region
  WHERE
    disp.sk_nps_answer > 0
    AND camp.metric_group in ('iqonboarding', 'pponboarding')
    AND camp.business_context = 'forRent'
    AND camp.purpose = 'main'
    AND COALESCE(dc.dt_start, dc.dt_entrance) >= date_add(MONTH, -17, '{load_start_date}')
    AND COALESCE(dc.dt_start, dc.dt_entrance) <= date_add(DAY, -1, '{load_start_date}')
    AND (
      ca.rk is NULL
      OR ca.rk = 1
    ) -- AND ca.sk_house_listing_anterior IS NOT NULL -- filtro para imóveis Re-rented
    AND DATE(ans.ts_answered) >= DATE('{load_start_date}')
),
status AS (
  SELECT
    DISTINCT fhls.*,
    ROW_NUMBER() OVER (
      PARTITION BY fhls.sk_house_listing / 1000
      ORDER BY
        fhls.ts_status_start desc
    ) AS rn
  FROM
    dw_offboarding.fact_house_listing_terminations tr
    right JOIN dw_rent.fact_house_listing_status fhls ON fhls.sk_house_listing / 1000 = tr.sk_house_listing / 1000
    AND sk_next_house_listing_publication_date >= 19000101 -- garantindo mínimo
    AND date(fhls.ts_status_start) >= DATE(
      CAST(
        sk_next_house_listing_publication_date AS STRING
      )
    )
  WHERE
    (
      fhls.ts_status_end IS NULL
      OR fhls.ts_status_start <> fhls.ts_status_end
    ) -- Retira casos de bug
    AND fhls.is_last_status_of_day = true
),
rent_2 AS (
  SELECT
    DISTINCT sk_contract,
    fhlt.sk_house_listing,
    erc.date AS erc_date,
    rl.date AS relisting_date,
    cs.date AS contract_signed_date,
    CASE
      WHEN st.status_history IN ('UNPUBLISHED', 'OPTED_OUT', 'SUSPENDED')
      AND status_change_reason NOT IN (
        'ContractDraft',
        'HouseReserved',
        'PaidGuarantee',
        'RENTED'
      )
      AND fhlt.sk_next_contract_signature_date = -1 THEN date(st.ts_status_start)
    END AS churn_date,
    CASE
      WHEN fhlt.sk_next_contract_signature_date != -1
      AND cs.date <= date_add(DAY, 28, erc.date) THEN true
      ELSE false
    END AS re_rental_4W,
    CASE
      WHEN st.status_history IN ('UNPUBLISHED', 'OPTED_OUT', 'SUSPENDED')
      AND status_change_reason NOT IN (
        'ContractDraft',
        'HouseReserved',
        'PaidGuarantee',
        'RENTED'
      )
      AND fhlt.sk_next_contract_signature_date = -1 THEN true
      WHEN fhlt.sk_next_house_listing_publication_date = -1 THEN true
      ELSE false
    END AS churn,
    CASE
      WHEN(
        st.status_history = 'SUSPENDED'
        AND st.status_change_reason = 'RENTED'
      )
      OR fhlt.sk_next_contract_signature_date != -1 THEN 'RENTED'
      ELSE st.status_history
    END AS status,
    CASE
      WHEN (
        st.status_history = 'SUSPENDED'
        AND st.status_change_reason = 'RENTED'
      )
      OR fhlt.sk_next_contract_signature_date != -1 THEN '-'
      WHEN status_change_reason IN (
        'ContractDraft',
        'HouseReserved',
        'PaidGuarantee'
      ) THEN 'Negociação avançada'
      ELSE st.status_change_reason
    END AS status_reason
  FROM
    dw_offboarding.fact_house_listing_terminations fhlt
    LEFT JOIN status st ON st.sk_house_listing = fhlt.sk_next_house_listing_consolidated
    AND DATE_ADD(DAY, -1, '{load_start_date}') >= st.ts_status_start
    AND DATE_ADD(DAY, -1, '{load_start_date}') <= COALESCE(st.ts_status_end, '{load_start_date}')
    AND rn = 1 -- alterar '{load_start_date}' dentro do 'DATE_ADD' para a data da resposta do NPS
    LEFT JOIN dw_public.dim_date erc ON erc.sk_date = fhlt.sk_ended_rental_confirmed_date -- ajuste para data do Ended Rental confirmed
    LEFT JOIN dw_public.dim_date rl ON rl.sk_date = fhlt.sk_next_house_listing_publication_date -- Ajuste para a data de relistagem
    LEFT JOIN dw_public.dim_date cs ON cs.sk_date = fhlt.sk_next_contract_signature_date -- Ajuste para a data do contrato assinado
    LEFT JOIN dw_offboarding.dim_termination dt using(sk_termination)
  WHERE
    erc.date >= DATE('2024-09-03')
    AND erc.date <= DATE('2024-12-03')
    AND dt.status != 'CANCELED'
),
joined AS (
  SELECT DISTINCT
    ntc.sk_nps_answer AS feedback_id,
    ntc.sk_user AS author_id,
    ntc.sk_contract,
    CONCAT(
      CAST(ntc.sk_contract AS STRING),
      '_',
      CASE
        WHEN ntc.customer_type = 'IQ' THEN 'tenant'
        ELSE 'landlord'
      END
    ) AS account_id,
    CASE
      WHEN ntc.customer_type = 'IQ' THEN 'tenant'
      ELSE 'landlord'
    END AS customer_type,
    ntc.score AS rating,
    ntc.score_category,
    date_format(
      ntc.data_resposta_nps, 'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''
    ) AS posted_at,
    CASE
      WHEN metric_group in ('iqonboarding', 'pponboarding') THEN 'onboarding'
      ELSE NULL
    END AS nps_campanha,
    CAST(
      CASE
        WHEN NULLIF(ntc.comment, '') is NULL THEN NULL
        WHEN ntc.score between 0
        AND 6 THEN CONCAT('Motivo da minha insatisfação: ', ntc.comment)
        WHEN ntc.score between 7
        AND 8 THEN CONCAT('Motivo da minha nota: ', ntc.comment)
        WHEN ntc.score between 9
        AND 10 THEN CONCAT('Motivo da minha satisfação: ', ntc.comment)
        ELSE ntc.comment
      END AS VARCHAR(1000000)
    ) AS text,
    CASE
      WHEN cast(irco.ts_inspected AS date) > c.dt_entrance THEN TRUE
      ELSE FALSE
    END flg_sla_onboarding,
    CASE
      WHEN c.flg_rerental_12w = 1 THEN TRUE
      ELSE FALSE
    END flg_rerental_12w_onboarding,
    CASE
      WHEN ntc.n_ticket_consumption_bills + ntc.n_ticket_moving > 0 THEN TRUE
      ELSE FALSE
    END flg_pos_contract_onboarding,
    CASE
      WHEN ntc.n_ticket_keys + n_ticket_keys_theme > 0 THEN TRUE
      ELSE FALSE
    END flg_key_onboarding,
    CASE
      WHEN ntc.n_ticket_payments_back + ntc.n_ticket_payments_front + ntc.n_ticket_payments_serfin + ntc.n_ticket_payments_theme > 0 THEN TRUE
      ELSE FALSE
    END flg_payment_onboarding,
    CASE
      WHEN ntc.n_ticket_contract_theme + ntc.n_ticket_closing + coalesce(cc.n_task_closed_manually, 0) > 0 THEN TRUE
      ELSE FALSE
    END flg_closing_onboarding,
   CASE
      WHEN ntc.n_ticket_repairs_back + ntc.n_ticket_repairs_front + ntc.n_ticket_repairs_theme > 0 THEN TRUE
      ELSE FALSE
    END flg_repair_onboarding,
    CASE
      WHEN (
        CASE
          WHEN ntc.customer_type = 'IQ' THEN CASE
            WHEN irco.n_lcomments > 15 THEN 1
            WHEN ntc.n_ticket_inspection_book > 0 THEN 1
            WHEN ntc.n_ticket_inspection_theme > 0 THEN 1
            WHEN cast(irco.ts_inspected AS date) > c.dt_entrance THEN 1
            ELSE 0
          END
          ELSE CASE
            WHEN n_lcomments > 15 THEN 1
            WHEN coalesce(ibcc.n_insp_cancelled, 0) > 0 THEN 1
            WHEN ntc.n_ticket_inspection_book > 0 THEN 1
            WHEN ntc.n_ticket_inspection_theme > 0 THEN 1
            WHEN cast(irco.ts_inspected AS date) > c.dt_entrance THEN 1
            ELSE 0
          END
        END
      ) > 0 THEN TRUE
      ELSE FALSE
    END AS flg_inspection_onboarding,
    CASE
      WHEN c.rent_value > 2500 THEN TRUE
      ELSE FALSE
    END flg_high_value_onboarding,
    CASE
      WHEN flg_ticket_all > 0 THEN TRUE
      ELSE FALSE
    END AS flg_ticket_all_onboarding,
    CASE
      WHEN c.house_contract_rank > 1
      OR c.flg_rerental_12w = 1 THEN TRUE
      ELSE FALSE
    END re_rental,
    city_group
  FROM
    nps_ticket_counts ntc
  LEFT JOIN closing_counts cc 
    ON ntc.sk_contract = cc.sk_contract
  LEFT JOIN contracts c 
    ON ntc.sk_contract = c.sk_contract
  LEFT JOIN inspection_booking_cancelled_counts ibcc 
    ON ntc.sk_contract = ibcc.sk_contract
  LEFT JOIN inspection_review_counts_ordered irco 
    ON ntc.sk_contract = irco.sk_contract
    AND irco.desc_rn = 1
  LEFT JOIN tb_reten ret 
    ON ntc.sk_nps_answer = ret.sk_nps_answer
  LEFT JOIN rent_2 ret2 
    ON ret.sk_last_contract = ret2.sk_contract
)

SELECT DISTINCT
  jd.*,
  CASE
    WHEN jd.customer_type = 'PP' THEN CASE
      WHEN flg_rerental_12W_Onboarding = TRUE THEN 'rerental'
      WHEN flg_inspection_Onboarding = TRUE THEN 'inspections'
      WHEN flg_repair_Onboarding = TRUE THEN 'repairs'
      WHEN flg_payment_Onboarding = TRUE THEN 'payments'
      WHEN flg_closing_Onboarding = TRUE THEN 'closing'
      When flg_ticket_all_onboarding = TRUE THEN 'Other Departments'
      ELSE 'seamless'
    END
    ELSE CASE
      WHEN flg_inspection_Onboarding = TRUE THEN 'inspections'
      WHEN flg_payment_Onboarding = TRUE THEN 'payments'
      WHEN flg_repair_Onboarding = TRUE THEN 'repairs'
      WHEN flg_key_Onboarding = TRUE THEN 'moving'
      WHEN flg_pos_contract_Onboarding = TRUE THEN 'moving'
      When flg_ticket_all_onboarding = TRUE THEN 'Other Departments'
      ELSE 'seamless'
    END
  END AS alavancas,
  CASE
    WHEN dt.is_spoc_contract = TRUE THEN 'SPOC'
    WHEN dt.is_spoc_control_group = TRUE THEN 'Grupo controle'
    ELSE NULL
  END AS spoc,
  year(posted_at) AS year,
  month(posted_at) AS month,
  day(posted_at) AS day,
  NOW() AS ts_load
FROM
  joined jd
LEFT JOIN dw_offboarding.fact_terminations AS dt
  ON dt.sk_contract = jd.sk_contract
