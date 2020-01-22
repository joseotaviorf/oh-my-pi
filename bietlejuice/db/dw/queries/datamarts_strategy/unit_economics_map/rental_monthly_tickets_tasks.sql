WITH
  onboarding AS ( -- Onboarding tasks
    SELECT
      sk_task,
      'pos' AS group_type,
      'onboarding' AS task_group,
      ts_action::date AS date_task_created,
      -1 as sk_lead,
      sk_house_listing,
      sk_contract,
      ROW_NUMBER() OVER (PARTITION BY sk_task ORDER BY sk_house_listing DESC, sk_contract DESC) AS index_task
    FROM crm.fact_onboarding_tenant_tasks
    WHERE action_type = 'CREATE'
  ),
  offboarding AS ( -- Offboarding tasks
    SELECT
      sk_task,
      'pos' AS group_type,
      'offboarding' AS task_group,
      ts_action::date AS date_task_created,
      -1 as sk_lead,
      sk_house_listing,
      sk_contract,
      ROW_NUMBER() OVER (PARTITION BY sk_task ORDER BY sk_house_listing DESC, sk_contract DESC) AS index_task
    FROM crm.fact_offboarding_tasks
    WHERE action_type = 'CREATE'
  ),
  payments AS ( -- Payments tasks
    SELECT
      sk_task,
      'pos' AS group_type,
      'payments' AS task_group,
      ts_action::date AS date_task_created,
      -1 as sk_lead,
      sk_house_listing,
      sk_contract,
      ROW_NUMBER() OVER (PARTITION BY sk_task ORDER BY sk_house_listing DESC, sk_contract DESC) AS index_task
    FROM crm.fact_payment_tasks
    WHERE action_type = 'CREATE'
  ),
  repairs AS ( -- Repairs tasks
    SELECT
      sk_task,
      'pos' AS group_type,
      'repairs' AS task_group,
      ts_action::date AS date_task_created,
      -1 as sk_lead,
      sk_house_listing,
      sk_contract,
      ROW_NUMBER() OVER (PARTITION BY sk_task ORDER BY sk_house_listing DESC, sk_contract DESC) AS index_task
    FROM crm.fact_repair_tasks
    WHERE action_type = 'CREATE'
  ),
  linhadireta AS ( -- Linha direta tasks
    SELECT
      sk_task,
      'pos' AS group_type,
      'linhadireta' AS task_group,
      ts_action::date AS date_task_created,
      -1 as sk_lead,
      sk_house_listing,
      sk_contract,
      ROW_NUMBER() OVER (PARTITION BY sk_task ORDER BY sk_house_listing DESC, sk_contract DESC) AS index_task
    FROM crm.fact_linhadireta_chat_tasks
    WHERE action_type = 'CREATE'
  ),
  manual AS ( -- Manual tasks
    SELECT
        fma.sk_task,
        'all' AS group_type,
        'manual' AS task_group,
        ts_action::date AS date_task_created,
        -1 as sk_lead,
        rf.sk_house_listing,
        fma.sk_contract,
      ROW_NUMBER() OVER (PARTITION BY sk_task ORDER BY rf.sk_house_listing DESC, fma.sk_contract DESC) AS index_task
    FROM crm.fact_ungrouped_manual_tasks fma
    LEFT JOIN (SELECT DISTINCT sk_house_listing, sk_contract FROM fact_listing_rent_flows) rf
      ON fma.sk_contract = rf.sk_contract AND rf.sk_contract > 0
    WHERE fma.action_type = 'CREATE'
  ),
  listing_tasks AS (  -- All tasks by listing
    SELECT * FROM onboarding WHERE index_task = 1
    UNION SELECT * FROM offboarding WHERE index_task = 1
    UNION SELECT * FROM payments WHERE index_task = 1
    UNION SELECT * FROM repairs WHERE index_task = 1
    UNION SELECT * FROM linhadireta WHERE index_task = 1
    UNION SELECT * FROM manual WHERE index_task = 1
  ),
  lead_listing AS ( -- Associating lead and listing
    SELECT
        hlf.sk_lead,
        dhl.sk_house_listing,
        hlf.sk_lead_date,
        hlf.sk_first_listing_date,
        hlf.sk_region,
        dr_listing.city_group,
        SUBSTRING(hlf.sk_house_listing,1,9) AS id_house,
        COALESCE(dr_listing.city_name,dr_lead.city_name) AS city_name
    FROM fact_house_listing_flows hlf
    LEFT JOIN dim_region dr_listing
      ON dr_listing.sk_region = hlf.sk_region
    LEFT JOIN dim_region dr_lead
      ON dr_lead.sk_region = hlf.sk_city
    LEFT JOIN dim_house_listing dhl
      ON SUBSTRING(hlf.sk_house_listing,1,9)= dhl.id_house
    ORDER BY sk_lead_date DESC
  ),
  listing_city AS ( -- Excluding null listings
    SELECT *
    FROM lead_listing
    WHERE sk_house_listing IS NOT NULL
  ),
  listing_tasks_city AS ( -- Association listing, task and city
    SELECT
      lit.*,
      lic.id_house,
      lic.city_name,
      lic.city_group
    FROM listing_tasks lit
    LEFT JOIN listing_city lic
      ON lit.sk_house_listing = lic.sk_house_listing
  ),
  all_tasks_city_unique AS ( -- Selection of last listing associated to task, since we know that there might be more than one listing linked to a task
    SELECT * FROM (
      SELECT *,
        ROW_NUMBER() OVER (PARTITION BY sk_task ORDER BY sk_house_listing DESC) AS index_tasks
      FROM listing_tasks_city
    )
    WHERE index_tasks = 1
        AND date_task_created >= '2019-07-01'
  ),
  tasks_monthly AS ( -- Aggregating tasks by month
    SELECT
      date_trunc('month', date_task_created) as month_task_created,
      sk_house_listing,
      city_group,
      task_group,
      COUNT (distinct sk_task) AS count_tasks
    FROM all_tasks_city_unique
    GROUP BY 1,2,3,4
    ORDER BY 1,2 DESC
  ),
  tickets AS ( -- Tickets by group
    SELECT
      dt.sk_ticket,
      dt.channel,
      date(dt.ts_created_local) AS date_ticket_created,
      ft.sk_house_listing,
      ft.sk_contract,
      CASE
        WHEN dt.group_name like '%[AGE]%' THEN 'Agents'
        WHEN dt.group_name like '%[B2B]%' THEN 'B2B'
        WHEN dt.group_name like '%[CE]%' THEN 'Crisis'
        WHEN dt.group_name like '%[CLO]%' THEN 'Closing'
        WHEN dt.group_name like '%[COL]%' THEN 'Collections'
        WHEN dt.group_name like '%[IS]%' THEN 'Inside Sales'
        WHEN dt.group_name like '%[LAB]%' THEN 'Labs'
        WHEN dt.group_name like '%[OFF]%' THEN 'Offboarding'
        WHEN dt.group_name like '%[ONB]%' THEN 'Onboarding'
        WHEN dt.group_name like '%[PAY]%' THEN 'Payments'
        WHEN dt.group_name like '%[PRO]%' THEN 'Offers'
        WHEN dt.group_name like '%[REP]%' THEN 'Repairs'
        WHEN dt.group_name like '%[SUP]%' THEN 'IndicaAí'
        WHEN dt.group_name like '%[VIS]%' THEN 'Visits'
        ELSE 'Other'
       END AS team,
    CASE
      WHEN team = 'Onboarding' THEN 'onboarding'
      WHEN team IN ('Payments','Repairs','Crisis') THEN 'ongoing'
      WHEN team = 'Offboarding' THEN 'offboarding'
      ELSE 'other'
      END AS team_group,
      dus.email AS email_client,
      substring(left(dus.email, charindex('@', dus.email) - 1),3) AS telefone_client
    FROM zendesk.dim_ticket dt
    JOIN zendesk.fact_tickets ft
      ON dt.sk_ticket = ft.sk_ticket
    JOIN zendesk.dim_zendesk_user dus
      ON dus.sk_zendesk_user = ft.sk_zendesk_submitter_user
    where ((dt.group_name like '%[POS]%') or (dt.group_name like '%[PÓS]%'))
    and (date(dt.ts_created_local) >= date('2019-07-01'))
  ),
  tickets_client AS ( -- Associating tickets to sk_user
    SELECT
        t.*,
      COALESCE (du_telefone.sk_user,du_email.sk_user,du_email_alt.sk_user,-1) AS sk_user_client
    FROM tickets t
    LEFT JOIN dim_user du_telefone -- aqui tem repetidos
      ON t.telefone_client = right(du_telefone.telefone_principal,11)
      AND t.channel = 'chat'
    LEFT JOIN dim_user du_email -- aqui tem repetidos
      ON t.email_client = du_email.email
    LEFT JOIN dim_user du_email_alt -- aqui tem repetidos
      ON t.email_client = du_email_alt.email_alternativo
    --where t.team_group = 'onboarding'
  ),
  contratopessoa AS ( --
      SELECT
          DISTINCT cp.usuario_id,
          replace(cp.email,' ','') AS email,
          replace(replace(replace(replace(replace(cp.telefone,'(',''),')',''),' ',''),'-',''),'+55','') AS telefone,
          replace(replace(replace(replace(replace(cp.telefonesecundario,'(',''),')',''),' ',''),'-',''),'+55','') AS telefone_secundario,
          cp.contrato_id,
          dc.ts_signature::date AS date_contract_signed
      FROM datalake_ebdb_raw_prod.contratopessoa cp
      JOIN dim_contract dc
          ON dc.sk_contract = cp.contrato_id
      WHERE (cp.email IS NOT NULL OR cp.telefone IS NOT NULL)
  ),
  tickets_contract AS (
      SELECT
          tc.*,
          CASE WHEN tc.sk_contract > 0 THEN tc.sk_contract
              WHEN tc.sk_contract = -1 THEN COALESCE(cp_telefone.contrato_id,cp_email.contrato_id,cp_telefone_secundario.contrato_id)
              ELSE -1
              END AS contract_id
      FROM tickets_client tc
      LEFT JOIN contratopessoa cp_email -- aqui gerou repetidos
          ON tc.email_client = cp_email.email
          AND tc.date_ticket_created >= cp_email.date_contract_signed
      LEFT JOIN contratopessoa cp_telefone
          ON tc.telefone_client = cp_telefone.telefone
          AND tc.date_ticket_created >= cp_telefone.date_contract_signed
      LEFT JOIN contratopessoa cp_telefone_secundario
          ON tc.telefone_client = cp_telefone_secundario.telefone_secundario
          AND tc.date_ticket_created >= cp_telefone_secundario.date_contract_signed
  ),
  listing_contract AS (
      SELECT
          DISTINCT rf.sk_contract,
          rf.sk_house_listing
      FROM fact_listing_rent_flows rf
      WHERE rf.sk_contract_signed_date > 0
  ),
  rent_flows AS (
      SELECT
          DISTINCT
          rf.sk_house_listing,
          dr.sk_region,
          dr.city_group
      FROM fact_listing_rent_flows rf
      LEFT JOIN dim_region dr
          ON rf.sk_region = dr.sk_region
  ),
  tickets_listing AS ( --
      SELECT
          tc.*,
          CASE WHEN tc.sk_house_listing > 0 THEN tc.sk_house_listing
              WHEN tc.sk_house_listing = -1 AND lc.sk_house_listing >0 THEN lc.sk_house_listing
              ELSE -1 END AS listing_id,
          ROW_NUMBER() OVER (PARTITION BY tc.sk_ticket ORDER BY listing_id DESC) AS index_ticket
      FROM tickets_contract tc
      LEFT JOIN listing_contract lc
          ON tc.contract_id = lc.sk_contract
  ),
  tickets_monthly AS ( -- Selection of last listing associated to ticket, since we know that there might be more than one listing linked to a ticket
      SELECT
          date_trunc('month', tl.date_ticket_created) as month_ticket_created,
        rf.sk_house_listing,
        tl.team_group,
        rf.city_group,
          count(distinct tl.sk_ticket) as tickets
      FROM tickets_listing tl
      LEFT JOIN rent_flows rf
          ON tl.listing_id = rf.sk_house_listing
      WHERE index_ticket = 1
      group by 1,2,3,4
  ) -- Sum of all tasks and tickets associated to a listing by month
  select
    coalesce(tim.sk_house_listing, tam.sk_house_listing) as sk_house_listing,
    coalesce(date(tim.month_ticket_created),date(tam.month_task_created)) as month,
    coalesce(tim.city_group, tam.city_group) as city_group,
    coalesce(tim.team_group, tam.task_group) as task_ticket_group,
    sum(coalesce(tim.tickets,0)) as tickets,
    sum(coalesce(tam.count_tasks,0)) as tasks,
    sum(coalesce(tim.tickets,0)) + sum(coalesce(tam.count_tasks,0)) as total_tickets_tasks
  from tickets_monthly tim
  full outer join tasks_monthly tam
    on tim.month_ticket_created = tam.month_task_created
       and tim.sk_house_listing = tam.sk_house_listing
       and tim.city_group = tam.city_group
       and tim.team_group = tam.task_group
-- costs for onboarding, ongoing and offboarding tickets and tasks available only from July 2019 on
  where coalesce(date(tim.month_ticket_created),date(tam.month_task_created)) >= '2019-07-01'
  group by 1,2,3,4;