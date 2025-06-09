WITH base_nps as (
  select
    ans.sk_nps_answer,
    disp.sk_user,
    camp.customer_type,
    disp.score,
    score_category,
    ans.comment,
    ans.ts_answered as data_resposta_nps,
    camp.metric_group,
    rank() over (PARTITION BY disp.sk_user ORDER BY ans.ts_answered) rank_nps
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
  WHERE
    disp.sk_nps_answer > 0
    and camp.metric_group in ('currentpo')
    and camp.business_context = 'forRent'
    and year >= 2024
),
ultimo_nps as (
  select
    data_resposta_nps,
    sk_nps_answer,
    sk_user,
    score,
    score_category,
    comment,
    max(rank_nps) last_rank
  from
    base_nps nps
  group by
    1,
    2,
    3,
    4,
    5,
    6,
    rank_nps
  having
    rank_nps = max(rank_nps)
  order by
    1
),
tkt as (
  select
    tkt.sk_user,
    tkt.sk_ticket,
    tkt.ts_sla_started,
    tkt.ts_closed,
    dd.team,
    tkt.front_or_back,
    tkt.channel,
    RANK() OVER (PARTITION BY nps.sk_nps_answer ORDER BY tkt.ts_closed DESC) last_ticket
  from
    dw_customer_support.fact_tickets tkt
      left join dw_customer_support.dim_department dd
        on dd.sk_department = tkt.sk_main_department
      left join dw_customer_support.dim_taxonomy dt
        on dt.sk_taxonomy = tkt.sk_taxonomy
      left join ultimo_nps as nps
        on tkt.sk_user = nps.sk_user
  where
    tkt.sk_user > 0
    and tkt.ts_sla_started between
      (date(data_resposta_nps) - interval '90' day)
    and
      (data_resposta_nps)
),
base_detractor as (
  select
    tkt.sk_user,
    count(distinct sk_ticket) total_tickets_l90d
  from
    tkt
  group by
    1
),
cluster_pp AS (
  SELECT
    id_owner,
    dt_owner_category,
    cluster_pp_multi,
    regexp_replace(cluster_pp_multi, ' \(.+\)', '') AS cluster_clean,
    ROW_NUMBER() OVER (PARTITION BY id_owner ORDER BY dt_owner_category DESC, id_owner DESC) AS rn
  FROM
    datalake_pro_owners.daily_owner_category doc
),
cluster_pp_2 as (
  SELECT DISTINCT
    dhh.id_owner,
    du.nome,
    du.email,
    du.telefone_principal AS telefone,
    CASE
      WHEN
        dhh.id_owner IN (2982090, 4133107, 7418653, 6446899, 10880132, 10178048, 10954737, 184489)
      THEN
        'Short Stay'
      WHEN
        dhh.id_owner IN (
          4166683,
          9005414,
          213199,
          1895145,
          9468263,
          416663,
          7109194,
          75535,
          1673646,
          145322,
          495270,
          3930579,
          70225,
          10302982,
          9836052
        )
      THEN
        'Corporate'
      WHEN
        dhh.id_owner NOT IN (
          2982090, 4133107, 7418653, 6446899, 10880132, 10178048, 10954737, 184489
        )
        AND dhh.id_owner NOT IN (
          4166683,
          9005414,
          213199,
          1895145,
          9468263,
          416663,
          7109194,
          75535,
          1673646,
          145322,
          495270,
          3930579,
          70225,
          10302982,
          9836052
        )
      THEN
        cp.cluster_clean
    END AS type_pp,
    DATE_FORMAT(DATE(upo.ts_created), '%Y-%m-%d') AS date_tag,
    dhh.id_account_manager,
    CASE
      WHEN dhh.id_account_manager = 4334394 THEN 'ariana.bueno'
      WHEN dhh.id_account_manager = 9187650 THEN 'isabel.medeiros'
      WHEN dhh.id_account_manager = 9084858 THEN 'julia.soltanovitch'
      WHEN dhh.id_account_manager = 4158243 THEN 'aline.salatini'
      WHEN dhh.id_account_manager = 1476578 THEN 'bianca.andrade'
      WHEN dhh.id_account_manager = 4626432 THEN 'itamar.amorim'
      WHEN dhh.id_account_manager = 3398932 THEN 'chaynara.nascimento'
      WHEN dhh.id_account_manager = 2672392 THEN 'barbara.avelino'
      WHEN dhh.id_account_manager = 4854943 THEN 'jonathan.fernandes'
      WHEN dhh.id_account_manager = 4317246 THEN 'larisse.bento'
      WHEN dhh.id_account_manager = 4776072 THEN 'maiza.martins'
      WHEN dhh.id_account_manager = 4776361 THEN 'manoela.susi'
      WHEN dhh.id_account_manager = 4858270 THEN 'mariane.prestes'
      WHEN dhh.id_account_manager = 4355360 THEN 'pedro.mendes'
      WHEN dhh.id_account_manager = 4439062 THEN 'rachell.bigi'
      WHEN dhh.id_account_manager = 4765009 THEN 'samia.ferradas'
      WHEN dhh.id_account_manager = 3395209 THEN 'thiago.brandao'
      WHEN dhh.id_account_manager = 4776242 THEN 'victor.andrade'
      WHEN dhh.id_account_manager = 3222869 THEN 'taili.martinez'
      WHEN dhh.id_account_manager = 4021496 THEN 'evellyn.silva'
      WHEN dhh.id_account_manager = 1128084 THEN 'gabriel.zucchini'
      WHEN dhh.id_account_manager = 3256657 THEN 'fabiane.januario'
      WHEN dhh.id_account_manager = 246550 THEN 'stephanie.pfutzenreiter'
      WHEN dhh.id_account_manager = 5001977 THEN 'henrique.leite'
      WHEN dhh.id_account_manager = 2901648 THEN 'ygor.cigoli'
      WHEN dhh.id_account_manager = 4376039 THEN 'adriana.santiago'
      WHEN dhh.id_account_manager = 3396776 THEN 'ranielly.fonseca'
      WHEN dhh.id_account_manager = 3678107 THEN 'suelen.moreira'
      WHEN dhh.id_account_manager = 3396811 THEN 'sula.carreiro'
      WHEN dhh.id_account_manager = 3396762 THEN 'pamela.barbosa'
      WHEN dhh.id_account_manager = 4499936 THEN 'davi.prado'
      WHEN dhh.id_account_manager = 4098654 THEN 'igor.fornagieri'
      ELSE 'Check'
    END AS account_manager,
    dhh.total_houses,
    dhh.ongoing_houses,
    dhh.houses_published,
    dhh.houses_rented,
    dhh.houses_unpublished
  FROM
    datalake_pro_owners.daily_owner_houses_quantity_history dhh
      LEFT JOIN dw_public.dim_user du
        ON dhh.id_owner = du.sk_user
      LEFT JOIN datalake_ebdb_clean.user_pro_owner upo
        ON upo.id_user = dhh.id_owner
        AND upo.is_active = true
      LEFT JOIN (
        SELECT
          *
        FROM
          cluster_pp
        WHERE
          rn = 1
      ) cp
        ON cp.id_owner = du.sk_user
  WHERE
    dhh.is_pp_multi_active = true
    AND dhh.dt_houses_owned >= DATE_ADD(DAY, -1, DATE('{load_start_date}'))
    AND dhh.country_code = 'BR'
  GROUP BY
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    9,
    10,
    11,
    12,
    13
),
cluster_aux as (
  SELECT
    doq.id_owner,
    CASE
      WHEN doq.id_owner in (2982090, 4133107, 7418653) THEN 'Short Stay'
      WHEN
        doq.id_owner in (
          4166683,
          9005414,
          213199,
          6446899,
          1895145,
          9468263,
          7418653,
          4133107,
          416663,
          7109194,
          75535,
          1673646,
          2982090,
          145322,
          495270,
          3930579,
          70225
        )
      THEN
        'Corporate'
      WHEN doq.ongoing_houses > 15 THEN 'Investors (15+)'
      WHEN doq.ongoing_houses > 10 THEN 'Investors (10-15)'
      WHEN doq.ongoing_houses >= 5 THEN 'Long-tail (5-10)'
      WHEN doq.ongoing_houses > 0 THEN 'Amadores'
    END AS type_pp,
    doq.ongoing_houses,
    doq.is_pp_multi_active,
    doq.dt_houses_owned,
    DATE_TRUNC('MONTH', doq.dt_houses_owned) as month,
    ROW_NUMBER() OVER (
        PARTITION BY doq.id_owner, DATE_TRUNC('MONTH', doq.dt_houses_owned)
        ORDER BY doq.dt_houses_owned DESC
      ) AS rk
  FROM
    datalake_pro_owners.daily_owner_houses_quantity_history doq
  WHERE
    doq.dt_houses_owned >= DATE('{load_start_date}') - INTERVAL '6' month
    AND (
      doq.ongoing_houses >= 5
      OR doq.is_pp_multi_active
    )
),
previous_date as (
  SELECT
    doq.id_owner,
    doq.ongoing_houses,
    doq.dt_houses_owned,
    ROW_NUMBER() OVER (PARTITION BY doq.id_owner ORDER BY doq.dt_houses_owned ASC) AS rk
  FROM
    datalake_pro_owners.daily_owner_houses_quantity_history doq
  WHERE
    doq.ongoing_houses >= 5
    AND doq.is_pp_multi_active = FALSE
),
aux_1 as (
  SELECT
    ca.id_owner,
    ca.type_pp,
    ca.ongoing_houses,
    ca.is_pp_multi_active,
    ca.month,
    ca.dt_houses_owned,
    CASE
      WHEN is_pp_multi_active = false THEN pd.dt_houses_owned
      ELSE NULL
    END as pp_mult_since
  FROM
    cluster_aux ca
      LEFT JOIN previous_date pd
        ON pd.id_owner = ca.id_owner
        AND pd.rk = 1
  WHERE
    ca.rk = 1
    AND ca.dt_houses_owned = DATE('{load_start_date}') - INTERVAL '1' day
),
aux_2 as (
  SELECT
    id_owner,
    type_pp,
    ongoing_houses,
    is_pp_multi_active
  FROM
    aux_1
  WHERE
    is_pp_multi_active = TRUE
    AND ongoing_houses > 4
),
base_contratos as (
  select
    i.id_owner,
    dc.sk_contract,
    max(dc.sk_contract) as last_contract,
    count(distinct dc.sk_contract) total_contratos_historico,
    count(distinct
      case
        when dc.status = 'Ativo' then dc.sk_contract
      end
    ) contratos_ativos,
    count(distinct
      case
        when
          dc.dt_start between (date(data_resposta_nps) - interval '90' day) and (data_resposta_nps)
        then
          dc.sk_contract
      end
    ) contratos_iniciados_l90d,
    count(distinct
      case
        when dc.status = 'Finalizado' then dc.sk_contract
      end
    ) contratos_finalizados,
    count(distinct
      case
        when
          dc.dt_annulment between
            (date(data_resposta_nps) - interval '90' day)
          and
            (data_resposta_nps)
        then
          dc.sk_contract
      end
    ) contratos_finalizados_l90d,
    count(distinct
      case
        when
          dc.dt_annulment between
            (date(data_resposta_nps) - interval '90' day)
          and
            (data_resposta_nps)
          and is_repair_tenant_duty = true
        then
          dc.sk_contract
      end
    ) contratos_finalizados_reparos_l90d
  from
    aux_2 i
      left join ultimo_nps un
        on un.sk_user = i.id_owner
      left join dw_rent.fact_contract_people fcp
        on fcp.sk_user = i.id_owner
      left join dw_rent.dim_contract dc
        on dc.sk_contract = fcp.sk_contract
  where
    dc.status <> 'cancelado'
  group by
    1,
    2
  order by
    1 desc
),
jd as (
  select DISTINCT
    un.sk_nps_answer as feedback_id,
    un.sk_user as author_id,
    max(bc.sk_contract) as sk_contract,
    case
      when bn.customer_type = 'PP' then 'landlord'
      else 'landlord'
    end as customer_type,
    un.score as rating,
    un.score_category,
    date_format(un.data_resposta_nps, 'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'') AS posted_at,
    'currentpo' as nps_campanha,
    a.cluster_pp_multi as type_pp,
    a.rn,
    CAST(
      case
        when NULLIF(un.comment, '') is null then null
        when un.score between 0 and 6 then CONCAT('Motivo da minha insatisfação: ', un.comment)
        when un.score between 7 and 8 then CONCAT('Motivo da minha nota: ', un.comment)
        when un.score between 9 and 10 then CONCAT('Motivo da minha satisfação: ', un.comment)
        else un.comment
      end AS VARCHAR(1000000)
    ) AS text
  from
    ultimo_nps un
      left join base_nps bn
        on bn.sk_user = un.sk_user
        and bn.rank_nps = (un.last_rank - 1)
      left join aux_2 i
        on i.id_owner = un.sk_user
      left join base_detractor bd
        on bd.sk_user = un.sk_user
      left join base_contratos bc
        on bc.id_owner = un.sk_user
      left join cluster_pp a
        on a.id_owner = un.sk_user
  group by
    1,
    2,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11
)
SELECT
  feedback_id,
  author_id,
  type_pp,
  CONCAT(CAST(sk_contract AS VARCHAR(10)), '_', customer_type) AS account_id,
  customer_type,
  rating,
  score_category,
  posted_at,
  nps_campanha,
  text,
  year(posted_at) AS year,
  month(posted_at) AS month,
  day(posted_at) AS day,
  NOW() AS ts_load
FROM
  jd
WHERE
  (
    rn = 1
    OR rn IS NULL
  )
  AND author_id IS NOT NULL
  AND author_id <> -1
  AND posted_at >= DATE('{load_start_date}')