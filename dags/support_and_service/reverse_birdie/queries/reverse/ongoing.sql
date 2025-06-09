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
  FROM
    datalake_pro_owners.daily_owner_houses_quantity_history dohq
      LEFT JOIN datalake_pro_owners.daily_owner_category doc
        ON dohq.id_owner = doc.id_owner
        AND dohq.dt_houses_owned = doc.dt_owner_category
      LEFT JOIN dw_public.dim_user dup
        ON dup.sk_user = dohq.id_owner
  WHERE
    dohq.is_pp_multi_active
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
  FROM
    dw_rent.dim_contract dc
      JOIN dw_public.dim_date dd
        ON dd.date BETWEEN
          COALESCE(dc.dt_start, dc.dt_entrance)
        AND
          COALESCE(dc.dt_annulment, CURRENT_DATE - INTERVAL '1' DAY)
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
    AND COALESCE(dc.dt_start, dc.dt_entrance) < CURRENT_DATE
    AND dd.date < CURRENT_DATE
    AND dc.type <> 'DealOnly'
    AND EXTRACT(YEAR FROM dd.date) >= 2024
), 
base_nps AS (
  SELECT
    ans.sk_nps_answer,
    disp.sk_user,
    disp.sk_contract,
    camp.customer_type,
    CASE
      WHEN camp.metric_group LIKE '%onboarding%' THEN 'onboarding'
      WHEN camp.metric_group LIKE '%ongoing%'   THEN 'ongoing'
      WHEN camp.metric_group LIKE '%offboarding%' THEN 'offboarding'
      ELSE NULL
    END AS campanha_nps,
    disp.score,
    ans.score_category,
    ans.comment,
    ans.ts_answered,
    DATE_FORMAT(ans.ts_answered, 'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'') AS data_resposta_nps,
    ans.ts_answered AS data_resposta,
    DATE(dc.ts_signature) AS contract_signed,
    DATE(COALESCE(dc.dt_start, dc.dt_entrance)) AS entrance_date,
    case when multi.sk_contract is not null then TRUE else FALSE end as pro_owner_property,
    pub.day,
    pub.month,
    pub.year,
    c.dt_start AS data_inicio_contrato,
    c.dt_annulment AS data_fim_contrato,
    CONCAT(
      CAST(disp.sk_user AS STRING),
      CAST(disp.sk_contract AS STRING)
    ) AS user_contrato,
    dr.city_group,
    dr.city_name
  FROM dw_customer_satisfaction.dim_nps_answer AS ans
  LEFT JOIN dw_customer_satisfaction.fact_nps_dispatches AS disp
    ON ans.sk_nps_answer = disp.sk_nps_answer
  INNER JOIN dw_customer_satisfaction.dim_nps_campaign AS camp
    ON disp.sk_nps_campaign = camp.sk_nps_campaign
  INNER JOIN dw_public.dim_date AS pub
    ON disp.sk_answered_date = pub.sk_date
  LEFT JOIN dw_rent.dim_contract AS c
    ON c.sk_contract = disp.sk_contract
  LEFT JOIN dw_rent.fact_house_listings AS fhl
    ON fhl.sk_contract = c.sk_contract
  LEFT JOIN dw_public.dim_region AS dr
    ON fhl.sk_region = dr.sk_region
  LEFT JOIN ppm_ongoing_rentals multi 
    ON multi.sk_contract = c.sk_contract
  LEFT JOIN dw_rent.dim_contract dc 
  ON dc.sk_contract = disp.sk_contract
  WHERE
    disp.sk_nps_answer > 0
    AND camp.metric_group IN ('iqongoing','ppongoing')
    AND camp.business_context = 'forRent'
    AND pub.year >= 2024
),

tickets AS (
  SELECT
    tkt.sk_user,
    nps.user_contrato,
    COUNT(DISTINCT tkt.sk_ticket) AS vol_ticket,
    COUNT(DISTINCT CASE
      WHEN tkt.ts_sla_started >= DATE(nps.ts_answered - INTERVAL '90' DAY)
      THEN tkt.sk_ticket
    END) AS vol_ticket_L3M,
    COUNT(DISTINCT CASE
      WHEN tkt.ts_sla_started
           BETWEEN DATE(nps.ts_answered - INTERVAL '180' DAY)
               AND DATE(nps.ts_answered - INTERVAL '90' DAY)
      THEN tkt.sk_ticket
    END) AS vol_ticket_L6M,
    COUNT(DISTINCT CASE
      WHEN tkt.ts_sla_started
           BETWEEN DATE(nps.ts_answered - INTERVAL '365' DAY)
               AND DATE(nps.ts_answered - INTERVAL '180' DAY)
      THEN tkt.sk_ticket
    END) AS vol_ticket_L12M,
    /* Recorrente */
    COUNT(DISTINCT CASE
      WHEN tkt.ts_sla_started
           BETWEEN DATE(nps.ts_answered - INTERVAL '90' DAY)
               AND DATE(nps.ts_answered - INTERVAL '60' DAY)
      THEN tkt.sk_ticket
    END) AS vol_ticket_L3M_recorrente,
    COUNT(DISTINCT CASE
      WHEN tkt.ts_sla_started
           BETWEEN DATE(nps.ts_answered - INTERVAL '60' DAY)
               AND DATE(nps.ts_answered - INTERVAL '30' DAY)
      THEN tkt.sk_ticket
    END) AS vol_ticket_L2M_recorrente,
    COUNT(DISTINCT CASE
      WHEN tkt.ts_sla_started
           BETWEEN DATE(nps.ts_answered - INTERVAL '30' DAY)
               AND DATE(nps.ts_answered - INTERVAL '1' DAY)
      THEN tkt.sk_ticket
    END) AS vol_ticket_L1M_recorrente,
    /* Payments Back */
    COUNT(DISTINCT CASE
      WHEN dd.area = 'CX'
       AND tkt.front_or_back = 'back'
       AND dd.team = 'Payments Ativo Back'
      THEN tkt.sk_ticket
    END) AS vol_ticket_time_payments_back,
    COUNT(DISTINCT CASE
      WHEN tkt.ts_sla_started BETWEEN DATE(nps.ts_answered - INTERVAL '90' DAY)
       AND DATE('{load_start_date}')
       AND dd.area = 'CX'
       AND dd.team = 'Payments Ativo Back'
       AND tkt.front_or_back = 'back'
      THEN tkt.sk_ticket
    END) AS vol_ticket_time_payments_back_Last_3_Month,
    /* Repairs Back */
    COUNT(DISTINCT CASE
      WHEN dd.area = 'CX'
       AND tkt.front_or_back = 'back'
       AND dd.team = 'Repairs/Ongoing Back'
      THEN tkt.sk_ticket
    END) AS vol_ticket_time_reparos_back,
    COUNT(DISTINCT CASE
      WHEN tkt.ts_sla_started BETWEEN DATE(nps.ts_answered - INTERVAL '90' DAY)
       AND DATE('{load_start_date}')
       AND dd.area = 'CX'
       AND dd.team = 'Repairs/Ongoing Back'
       AND tkt.front_or_back = 'back'
      THEN tkt.sk_ticket
    END) AS vol_ticket_time_reparos_back_Last_3_Month,
    /* Ongoing Back */
    COUNT(DISTINCT CASE
      WHEN dd.area = 'CX'
       AND tkt.front_or_back = 'back'
       AND dd.team = 'Ongoing Back'
      THEN tkt.sk_ticket
    END) AS vol_ticket_time_ongoing_back,
    COUNT(DISTINCT CASE
      WHEN tkt.ts_sla_started BETWEEN DATE(nps.ts_answered - INTERVAL '90' DAY)
       AND DATE('{load_start_date}')
       AND dd.area = 'CX'
       AND dd.team = 'Ongoing Back'
       AND tkt.front_or_back = 'back'
      THEN tkt.sk_ticket
    END) AS vol_ticket_time_ongoing_back_Last_3_Month,
    /* Front */
    COUNT(DISTINCT CASE
      WHEN dd.area = 'CX'
       AND tkt.front_or_back = 'front'
      THEN tkt.sk_ticket
    END) AS vol_ticket_front,
    COUNT(DISTINCT CASE
      WHEN tkt.ts_sla_started BETWEEN DATE(nps.ts_answered - INTERVAL '90' DAY)
       AND DATE('{load_start_date}')
       AND dd.area = 'CX'
       AND tkt.front_or_back = 'front'
      THEN tkt.sk_ticket
    END) AS vol_ticket_front_Last_3_Month,
    /* Serfin */
    COUNT(DISTINCT CASE
      WHEN tkt.sk_main_department IN (
        'Serv. Financeiros - IQ Paga/Captura de boletos [SO]',
        'Serv. Financeiros - Faturas [SO]',
        'Serv. Financeiros - Tarefas Invisíveis Correções [SO]',
        'Serv. Financeiros - Condomínio V0V8 [SO]',
        'Serv. Financeiros - Correções [SO]',
        'Serv. Financeiros - Reembolsos [SO]'
      ) THEN tkt.sk_ticket
    END) AS vol_ticket_time_Serfin,
    COUNT(DISTINCT CASE
      WHEN tkt.ts_sla_started BETWEEN DATE(nps.ts_answered - INTERVAL '90' DAY)
        AND DATE('{load_start_date}')
       AND tkt.sk_main_department IN (
        'Serv. Financeiros - IQ Paga/Captura de boletos [SO]',
        'Serv. Financeiros - Faturas [SO]',
        'Serv. Financeiros - Tarefas Invisíveis Correções [SO]',
        'Serv. Financeiros - Condomínio V0V8 [SO]',
        'Serv. Financeiros - Correções [SO]',
        'Serv. Financeiros - Reembolsos [SO]'
       )
      THEN tkt.sk_ticket
    END) AS vol_ticket_time_Serfin_Last_3_Month,
    /* Collections */
    COUNT(DISTINCT CASE
      WHEN tkt.sk_main_department IN (
        'Cobrança 0-30d [COL] [POS] [BACK]',
        'Ops Cobrança [BACK] [POS]',
        'Cobrança Acordos [COL] [POS] [BACK]',
        'Cobrança 31-60d [COL] [POS] [BACK]',
        'Cobrança Proprietários [COL] [POS] [BACK]'
      ) THEN tkt.sk_ticket
    END) AS vol_ticket_time_Collections,
    COUNT(DISTINCT CASE
      WHEN tkt.ts_sla_started BETWEEN DATE(nps.ts_answered - INTERVAL '90' DAY)
       AND DATE('{load_start_date}')
       AND tkt.sk_main_department IN (
         'Cobrança 0-30d [COL] [POS] [BACK]',
         'Ops Cobrança [BACK] [POS]',
         'Cobrança Acordos [COL] [POS] [BACK]',
         'Cobrança 31-60d [COL] [POS] [BACK]',
         'Cobrança Proprietários [COL] [POS] [BACK]'
       )
      THEN tkt.sk_ticket
    END) AS vol_ticket_time_Collections_Last_3_Month,
    /* Offboarding */
    COUNT(DISTINCT CASE
      WHEN dd.team IN ('Offboarding Back','Offboarding Front')
      THEN tkt.sk_ticket
    END) AS vol_ticket_time_Off,
    COUNT(DISTINCT CASE
      WHEN tkt.ts_sla_started BETWEEN DATE(nps.ts_answered - INTERVAL '90' DAY)
       AND DATE('{load_start_date}')
       AND dd.team IN ('Offboarding Back','Offboarding Front')
      THEN tkt.sk_ticket
    END) AS vol_ticket_time_Off_Last_3_Month,
    /* Payments Front */
    COUNT(DISTINCT CASE
      WHEN dd.area = 'CX'
       AND tkt.front_or_back = 'front'
       AND dd.team = 'Payments'
      THEN tkt.sk_ticket
    END) AS vol_ticket_time_payments_front,
    COUNT(DISTINCT CASE
      WHEN tkt.ts_sla_started BETWEEN DATE(nps.ts_answered - INTERVAL '90' DAY)
       AND DATE('{load_start_date}')
       AND dd.area = 'CX'
       AND tkt.front_or_back = 'front'
       AND dd.team = 'Payments'
      THEN tkt.sk_ticket
    END) AS vol_ticket_time_payments_front_Last_3_Month,
    /* Repairs Front */
    COUNT(DISTINCT CASE
      WHEN dd.area = 'CX'
       AND tkt.front_or_back = 'front'
       AND dd.team = 'Repairs/Ongoing Front'
      THEN tkt.sk_ticket
    END) AS vol_ticket_time_reparos_front,
    COUNT(DISTINCT CASE
      WHEN tkt.ts_sla_started BETWEEN DATE(nps.ts_answered - INTERVAL '90' DAY)
       AND DATE('{load_start_date}')
       AND dd.area = 'CX'
       AND tkt.front_or_back = 'front'
       AND dd.team = 'Repairs/Ongoing Front'
      THEN tkt.sk_ticket
    END) AS vol_ticket_time_reparos_front_Last_3_Month,
    /* Outros times CX vs fora CX */
    COUNT(DISTINCT CASE
      WHEN tkt.ts_sla_started BETWEEN DATE(nps.ts_answered - INTERVAL '90' DAY)
       AND DATE('{load_start_date}')
       AND dd.area = 'CX'
      THEN tkt.sk_ticket
    END) AS outros_times_cx_last_3months,
    COUNT(DISTINCT CASE
      WHEN tkt.ts_sla_started BETWEEN DATE(nps.ts_answered - INTERVAL '90' DAY)
       AND DATE('{load_start_date}')
       AND dd.area <> 'CX'
      THEN tkt.sk_ticket
    END) AS outros_times_fora_cx_last_3months,
    /* Por tema (CX front) */
    COUNT(DISTINCT CASE
      WHEN tkt.ts_sla_started BETWEEN DATE(nps.ts_answered - INTERVAL '90' DAY)
       AND DATE('{load_start_date}')
       AND dd.area = 'CX'
       AND dt.theme IN (
         'rental_ongoing_condo',
         'pay__condomínio_pendente__selfcondo',
         'rental_house_info_and_condo_rules'
       )
       AND tkt.front_or_back = 'front'
      THEN tkt.sk_ticket
    END) AS condominio,
    COUNT(DISTINCT CASE
      WHEN tkt.ts_sla_started BETWEEN DATE(nps.ts_answered - INTERVAL '90' DAY)
       AND DATE('{load_start_date}')
       AND dd.area = 'CX'
       AND dt.theme IN ('rent_billet_detailing','rental_value_transfer')
       AND tkt.front_or_back = 'front'
      THEN tkt.sk_ticket
    END) AS boleto_demonstrativo,
    COUNT(DISTINCT CASE
      WHEN tkt.ts_sla_started BETWEEN DATE(nps.ts_answered - INTERVAL '90' DAY)
       AND DATE('{load_start_date}')
       AND dd.area = 'CX'
       AND dt.theme = 'iptu_rent_property_tax'
       AND tkt.front_or_back = 'front'
      THEN tkt.sk_ticket
    END) AS iptu,
    COUNT(DISTINCT CASE
      WHEN tkt.ts_sla_started BETWEEN DATE(nps.ts_answered - INTERVAL '90' DAY)
       AND DATE('{load_start_date}')
       AND dd.area = 'CX'
       AND dt.theme IN ('rental_customer_income_tax','rental_customer_tax_receipt')
       AND tkt.front_or_back = 'front'
      THEN tkt.sk_ticket
    END) AS ir,
    COUNT(DISTINCT CASE
      WHEN tkt.ts_sla_started BETWEEN DATE(nps.ts_answered - INTERVAL '90' DAY)
       AND DATE('{load_start_date}')
       AND dd.area = 'CX'
       AND dt.theme = 'rent_negotiation'
       AND tkt.front_or_back = 'front'
      THEN tkt.sk_ticket
    END) AS negociacao,
    COUNT(DISTINCT CASE
      WHEN tkt.ts_sla_started BETWEEN DATE(nps.ts_answered - INTERVAL '90' DAY)
       AND DATE('{load_start_date}')
       AND dd.area = 'CX'
       AND dt.theme = 'rent_utility_bills'
       AND tkt.front_or_back = 'front'
      THEN tkt.sk_ticket
    END) AS contas_consumo,
    COUNT(DISTINCT CASE
      WHEN tkt.ts_sla_started BETWEEN DATE(nps.ts_answered - INTERVAL '90' DAY)
       AND DATE('{load_start_date}')
       AND dd.area = 'CX'
       AND dt.theme IN (
         'rental_ongoing_contract_demands',
         'ongoing_customer_records_management'
       )
       AND tkt.front_or_back = 'front'
      THEN tkt.sk_ticket
    END) AS atualizacao_cadastro,
    /* Repasse */
    COUNT(DISTINCT CASE
      WHEN tkt.ts_sla_started BETWEEN DATE(nps.ts_answered - INTERVAL '90' DAY)
       AND DATE('{load_start_date}')
       AND dd.area = 'CX'
       AND dt.theme IN (
         'rental_value_transfer_missing',
         'ongoing_customer_records_edit_bank_details',
         'ongoing_customer_records_management'
       )
      THEN tkt.sk_ticket
    END) AS repasse
  FROM dw_customer_support.fact_tickets AS tkt
  LEFT JOIN dw_customer_support.dim_department AS dd
    ON tkt.sk_main_department = dd.sk_department
  LEFT JOIN dw_customer_support.dim_taxonomy AS dt
    ON tkt.sk_taxonomy = dt.sk_taxonomy
  LEFT JOIN base_nps AS nps
    ON tkt.sk_user = nps.sk_user
  WHERE
    tkt.sk_user > 0
    AND tkt.ts_sla_started BETWEEN DATE(nps.data_inicio_contrato - INTERVAL '30' DAY) AND nps.ts_answered
  GROUP BY 1,2
),

lrf AS (
  SELECT DISTINCT
    sk_house_listing/1000 AS id_house,
    sk_owner
  FROM dw_public.fact_house_listings
  WHERE sk_owner > 0
  UNION
  SELECT DISTINCT
    sk_house_listing/1000 AS id_house,
    sk_owner
  FROM dw_rent.fact_listing_rent_flows
  WHERE sk_owner > 0
),

num_houses AS (
  SELECT
    sk_owner,
    COUNT(DISTINCT id_house) AS num_houses,
    COUNT(DISTINCT CASE WHEN status = 'Ativo' THEN id_house END) AS num_houses_rented,
    COUNT(DISTINCT CASE WHEN status = 'Finalizado' THEN id_house END) AS num_houses_finalizado
  FROM (
    SELECT
      lrf.sk_owner,
      lrf.id_house,
      tmp.sk_contract,
      tmp.status
    FROM lrf
    LEFT JOIN (
      SELECT DISTINCT
        sk_house_listing/1000 AS id_house,
        fhl.sk_contract,
        c.status
      FROM dw_public.fact_house_listings AS fhl
      LEFT JOIN (
        SELECT DISTINCT sk_contract, status
        FROM dw_rent.dim_contract
        WHERE status <> 'Cancelado'
      ) AS c
        ON c.sk_contract = fhl.sk_contract
    ) tmp
      ON tmp.id_house = lrf.id_house
  ) t
  GROUP BY sk_owner
),
col_tab AS (
  SELECT
    nps.sk_nps_answer,
    nps.sk_contract,
    nps.customer_type,
    nps.campanha_nps,
    nps.score_category,
    nps.data_resposta_nps,
    COUNT(DISTINCT 
          CASE WHEN t.dt_reference <= DATE(nps.ts_answered) 
          THEN t.id_contract END) AS Coll,
    COUNT(DISTINCT 
          CASE WHEN t.debtor_type = 'Stock' 
          AND t.dt_reference <= DATE(nps.ts_answered) 
          THEN t.id_contract END) AS Coll_Stock,
    COUNT(DISTINCT 
          CASE WHEN t.debtor_type = 'Flow' 
          AND t.dt_reference <= DATE(nps.ts_answered) 
          THEN t.id_contract END)AS Coll_Flow,
    COUNT(DISTINCT 
          CASE WHEN t.dt_reference BETWEEN DATE(nps.ts_answered - INTERVAL '30' DAY) 
          AND DATE(nps.ts_answered) 
          THEN t.id_contract END) AS Coll_1_mes,
    COUNT(DISTINCT 
          CASE WHEN t.debtor_type = 'Stock' 
          AND t.dt_reference BETWEEN DATE(nps.ts_answered - INTERVAL '30' DAY) 
          AND DATE(nps.ts_answered) THEN t.id_contract END) AS Coll_Stock_1_mes,
    COUNT(DISTINCT 
          CASE WHEN t.debtor_type = 'Flow' 
          AND t.dt_reference BETWEEN DATE(nps.ts_answered - INTERVAL '30' DAY) 
          AND DATE(nps.ts_answered) THEN t.id_contract END) AS Coll_Flow_1_mes,
    COUNT(DISTINCT 
          CASE WHEN t.dt_reference BETWEEN DATE(nps.ts_answered - INTERVAL '90' DAY) 
          AND DATE(nps.ts_answered) THEN t.id_contract END) AS Coll_3_mes,
    COUNT(DISTINCT 
          CASE WHEN t.debtor_type = 'Stock' 
          AND t.dt_reference BETWEEN DATE(nps.ts_answered - INTERVAL '90' DAY) 
          AND DATE(nps.ts_answered) THEN t.id_contract END) AS Coll_Stock_3_mes,
    COUNT(DISTINCT 
          CASE WHEN t.debtor_type = 'Flow' 
          AND t.dt_reference BETWEEN DATE(nps.ts_answered - INTERVAL '90' DAY) 
          AND DATE(nps.ts_answered) THEN t.id_contract END) AS Coll_Flow_3_mes,
    COUNT(DISTINCT 
          CASE WHEN t.dt_reference BETWEEN DATE(nps.ts_answered - INTERVAL '180' DAY) 
          AND DATE(nps.ts_answered) THEN t.id_contract END) AS Coll_6_mes,
    COUNT(DISTINCT 
          CASE WHEN t.debtor_type = 'Stock' 
          AND t.dt_reference BETWEEN DATE(nps.ts_answered - INTERVAL '180' DAY) 
          AND DATE(nps.ts_answered) THEN t.id_contract END) AS Coll_Stock_6_mes
  FROM base_nps AS nps
  LEFT JOIN datalake_invoice.overdue_portfolio_timeline AS t
    ON nps.sk_contract = t.id_contract
  GROUP BY
    nps.sk_nps_answer,
    nps.sk_contract,
    nps.customer_type,
    nps.campanha_nps,
    nps.score_category,
    nps.data_resposta_nps
),

listings AS (
  SELECT
    hl.id_house,
    hl.sk_house_listing,
    dc.sk_contract,
    TO_CHAR(DATE(dc.ts_signature),'yyyy-mm-dd')                           AS ts_signature,
    TO_CHAR(DATE(COALESCE(dc.dt_start, dc.dt_entrance)),'yyyy-mm-dd')     AS inicio_contrato,
    TO_CHAR(DATE(dc.dt_annulment),'yyyy-mm-dd')                           AS dt_annulment,
    TO_CHAR(DATE(hl.ts_early_demand_started),'yyyy-mm-dd')                AS early_demand_started,
    rl.sk_house_listing                                                  AS sk_relisting,
    TO_CHAR(DATE(rl.ts_listing_version_start),'yyyy-mm-dd')               AS dt_relisting
  FROM dw_rent.dim_contract AS dc
  LEFT JOIN dw_rent.fact_listing_rent_flows AS fhl
    ON fhl.sk_contract = dc.sk_contract
  LEFT JOIN dw_public.dim_house_listing AS hl
    ON hl.sk_house_listing = fhl.sk_house_listing
  LEFT JOIN dw_public.dim_house_listing AS rl
    ON rl.sk_house_listing = hl.sk_house_listing + 1
  WHERE
    dc.status = 'Finalizado'
    AND TO_CHAR(DATE(dc.dt_annulment),'yyyy-mm-dd') >= '2022-01-01'
),

base_rescisoes AS (
  SELECT
    ct.id_house,
    ct.id_contract,
    CAST(ct.ts_created AS DATE) AS dt_rescission_created,
    ct.dt_termination,
    CAST(ct.ts_canceled AS DATE) AS dt_rescission_canceled,
    ct.status               AS status_rescission,
    ct.is_before_contract_start,
    ct.requested_by,
    ct.id_region
  FROM datalake_offboarding.contract_termination AS ct
  WHERE
    ct.ts_created >= CAST('2021-01-01' AS DATE)
    AND ct.dt_termination <= DATE('{load_start_date}')
    AND ct.status <> 'CANCELED'
),

bd_relisting AS (
  SELECT
    l.sk_relisting,
    l.dt_relisting,
    dc.sk_contract AS contrato_relisting,
    dc.ts_signature,
    CASE
      WHEN br.id_house IS NOT NULL  THEN 'Early-Listing'
      WHEN br2.id_house IS NOT NULL THEN 'Re-Listing'
      ELSE NULL
    END AS early_listing,
    COUNT(l.sk_relisting) AS indicador_relisting
  FROM listings AS l
  LEFT JOIN (
    SELECT DISTINCT
      fhl.sk_house_listing,
      hl.id_house,
      fhl.sk_contract,
      fhl.sk_offer_approved_date,
      fhl.sk_offer_submitted_date
    FROM dw_rent.fact_listing_rent_flows AS fhl
    LEFT JOIN dw_public.dim_house_listing AS hl
      ON hl.sk_house_listing = fhl.sk_house_listing
  ) AS fhl
    ON fhl.sk_house_listing = l.sk_relisting
  LEFT JOIN dw_rent.dim_contract AS dc
    ON dc.sk_contract = fhl.sk_contract
  INNER JOIN dw_public.dim_date dd
    ON dd.sk_date = fhl.sk_offer_approved_date
  INNER JOIN dw_public.dim_date dd2
    ON dd2.sk_date = fhl.sk_offer_submitted_date
  LEFT JOIN base_rescisoes AS br
    ON br.id_house = fhl.id_house
   AND dd2.date >= br.dt_rescission_created
   AND dd2.date <  br.dt_termination
  LEFT JOIN base_rescisoes AS br2
    ON br2.id_house = fhl.id_house
   AND dd2.date >= br2.dt_termination
  WHERE
    dc.sk_contract > 0
    AND dc.status <> 'Cancelado'
  GROUP BY
    1,2,3,4,5
),

tabela_final AS (
  SELECT
    nps.sk_nps_answer,
    nps.sk_user,
    nps.sk_contract,
    nps.customer_type,
    nps.campanha_nps,
    nps.score_category,
    nps.score,
    nps.comment,
    nps.data_resposta_nps,
    nps.ts_answered,
    nps.city_group,
    nps.city_name,
    DATE(nps.data_inicio_contrato) AS data_inicio_contrato,
    DATE(nps.data_fim_contrato)    AS data_fim_contrato,
    nps.contract_signed,
    nps.entrance_date,
    nps.pro_owner_property,
    /* Touchpoint L3M */
    CASE
      WHEN COALESCE(tkt.vol_ticket_L3M,0) +
           COALESCE(col.Coll_Flow_3_mes,0) > 0
      THEN 1 ELSE 0
    END AS touchpoint_L3M,
    /* Alavancas */
    COALESCE(tkt.vol_ticket_time_payments_back_Last_3_Month,0)       AS pay_back_L3M,
    COALESCE(tkt.vol_ticket_time_Serfin_Last_3_Month,0)               AS serfin_L3M,
    COALESCE(tkt.vol_ticket_time_payments_front_Last_3_Month,0)      AS pay_front_L3M,
    CASE
      WHEN (COALESCE(col.Coll_Flow_3_mes,0) +
            COALESCE(tkt.vol_ticket_time_Collections,0)) > 0
      THEN 1 ELSE 0
    END AS collections,
    COALESCE(tkt.vol_ticket_time_reparos_back_Last_3_Month,0)        AS reparos_back_L3M,
    COALESCE(tkt.vol_ticket_time_reparos_front_Last_3_Month,0)       AS reparos_front_L3M,
    COALESCE(tkt.vol_ticket_time_ongoing_back_Last_3_Month,0)        AS ongoing_back_L3M,
    COALESCE(tkt.vol_ticket_time_Off_Last_3_Month,0)                 AS offboarding_L3M,
    /* Outros usos */
    COALESCE(tkt.outros_times_cx_last_3months,0)                     AS outros_cx_L3M,
    COALESCE(tkt.outros_times_fora_cx_last_3months,0)               AS outros_fora_cx_L3M,
    /* Por assunto */
    COALESCE(tkt.condominio,0)         AS condominio,
    COALESCE(tkt.boleto_demonstrativo,0) AS boleto_demonstrativo,
    COALESCE(tkt.iptu,0)               AS iptu,
    COALESCE(tkt.ir,0)                 AS ir,
    COALESCE(tkt.negociacao,0)         AS negociacao,
    COALESCE(tkt.contas_consumo,0)     AS contas_consumo,
    COALESCE(tkt.atualizacao_cadastro,0) AS atualizacao_cadastro,
    COALESCE(tkt.repasse,0)            AS repasse,
    /*Cliente */
    nh.num_houses,
    nh.num_houses_rented,
    nh.num_houses_finalizado,
    /* Relisting */
    CASE WHEN br.indicador_relisting > 0 THEN 1 ELSE 0 END AS relisting
  FROM base_nps AS nps
  LEFT JOIN tickets AS tkt 
    ON nps.user_contrato = tkt.user_contrato
  LEFT JOIN col_tab    AS col 
    ON col.sk_nps_answer = nps.sk_nps_answer
  LEFT JOIN num_houses AS nh  
    ON nps.sk_user = nh.sk_owner 
    AND nps.customer_type = 'PP'
  LEFT JOIN bd_relisting AS br
    ON br.contrato_relisting = nps.sk_contract
),

joined AS (
  SELECT
    tf.ts_answered,
    tf.sk_nps_answer,
    tf.sk_user,
    tf.sk_contract,
    tf.customer_type,
    tf.campanha_nps,
    tf.score,
    tf.score_category,
    tf.data_resposta_nps,
    tf.comment            AS comment_Ongoing,
    tf.city_group,
    tf.pro_owner_property,
    tf.contract_signed,
    tf.entrance_date,
    /* Alavanca principal */
    CASE
      WHEN tf.touchpoint_L3M = 0 THEN 'touchless'
      WHEN tf.pay_back_L3M + tf.serfin_L3M > 0 THEN 'pagamentos'
      WHEN tf.reparos_back_L3M + tf.reparos_front_L3M > 0 THEN 'reparos'
      ELSE 'outros'
    END AS alavanca,
    tf.touchpoint_L3M > 0                              AS flg_touchpoint_L3M,
    tf.pay_back_L3M + tf.serfin_L3M > 0                 AS flg_payments,
    tf.reparos_back_L3M + tf.reparos_front_L3M > 0      AS flg_repairs,
    tf.collections = 1                                  AS flg_collections,
    tf.relisting = 1                                    AS flg_relisting,
    CASE
      WHEN alavanca = 'touchless' THEN 'touchless'
      WHEN alavanca = 'pagamentos' THEN 'pagamentos'
      WHEN alavanca = 'reparos'    THEN 'reparos'
      WHEN alavanca = 'outros' AND flg_collections THEN 'collections'
      WHEN alavanca = 'outros' AND NOT flg_collections THEN 'outros'
    END                                                  AS alavancas_ongoing
  FROM tabela_final AS tf
  WHERE DATE(tf.data_resposta_nps) >= DATE('2024-01-01')
  ORDER BY tf.data_resposta_nps ASC
)

SELECT
  jd.sk_nps_answer  AS feedback_id,
  jd.sk_user  AS author_id,
  CONCAT(
    CAST(jd.sk_contract AS STRING), '_',
    CASE 
      WHEN jd.customer_type = 'IQ' 
      THEN 'tenant'
      ELSE 'landlord' END
  ) AS account_id,
  CASE 
    WHEN jd.customer_type = 'IQ' 
    THEN 'tenant' 
    ELSE 'landlord' 
  END AS customer_type,
  jd.score AS rating,
  jd.score_category,
  date_format(jd.data_resposta_nps, 'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'') AS posted_at,
  jd.campanha_nps AS nps_campanha,
  CAST(
    CASE
      WHEN NULLIF(jd.comment_Ongoing,'') IS NULL THEN NULL
      WHEN jd.score BETWEEN 0 AND 6  THEN CONCAT('Motivo da minha insatisfação: ', jd.comment_Ongoing)
      WHEN jd.score BETWEEN 7 AND 8  THEN CONCAT('Motivo da minha nota: ', jd.comment_Ongoing)
      WHEN jd.score BETWEEN 9 AND 10 THEN CONCAT('Motivo da minha satisfação: ', jd.comment_Ongoing)
      ELSE jd.comment_Ongoing
    END
  AS VARCHAR(1000000)) AS text,
  jd.city_group,
  jd.flg_touchpoint_L3M AS flg_touchpoint_l3m_ongoing,
  jd.flg_payments AS flg_payments_ongoing,
  jd.flg_repairs AS flg_repairs_ongoing,
  jd.flg_collections AS flg_collections_ongoing,
  jd.flg_relisting AS flg_relisting_ongoing,
  jd.pro_owner_property,
  jd.contract_signed,
  jd.entrance_date,
  jd.alavancas_ongoing,
  year(jd.data_resposta_nps) AS year,
  month(jd.data_resposta_nps) AS month,
  day(jd.data_resposta_nps) AS day,
  NOW() AS ts_load
FROM joined jd
WHERE 
  DATE(jd.data_resposta_nps) >= DATE('{load_start_date}')
QUALIFY ROW_NUMBER() OVER(PARTITION BY jd.sk_contract, jd.customer_type ORDER BY jd.data_resposta_nps ASC) = 1