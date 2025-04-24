WITH post_visit_review AS (
  with template_feature_prep as (
  select
    template_feature.id_feature,
    coalesce(template_feature_parent.id_template, template_feature.id_template) as id_template,
    template_feature.visible_options
  from
    datalake_insider_clean.template_feature as template_feature
      left join
        datalake_insider_clean.template_feature as template_feature_parent
        on template_feature_parent.id = template_feature.id_parent
),
rating as (
  select
    left(review.id_reviewed, 8) as visit_code,
    date_format(review.dt_creation, 'yyyy-MM-dd HH:mm:ss') as review_date,
    feature.name as journey_step,
    cast(review_feature.rating_selected as string) as rating_selected,
    review_feature.comment,
    review.status,
    review.id as review_id
  from
    datalake_insider_clean.template as template
      left join
        template_feature_prep as template_feature
        on template.id = template_feature.id_template
      left join
        datalake_insider_clean.feature as feature
        on template_feature.id_feature = feature.id
      left join
        datalake_insider_clean.review_feature as review_feature
        on feature.id = review_feature.id_feature
      left join datalake_insider_clean.review as review on review_feature.id_review = review.id
  where
    template.type in ('post_visit_agent_rating', 'post_visit_house_rating')
    and template.is_active = true
  order by
    1,
    4
),
schedules as (
  SELECT
    schedules.sk_schedule,
    schedules.sk_visit,
    schedules.sk_region,
    schedules.sk_visitor,
    schedules.sk_owner,
    schedules.sk_house,
    bc.business_context,
    behavior.behavior_type,
    bm.business_model,
    schedules.sk_agent,
    schedules.sk_user_agent,
    schedules.sk_fixed_agent,
    schedules.sk_author_creator,
    schedules.visit_code,
    et.entrance_type,
    schedules.sk_succeed_schedule,
    schedules.has_tenant_living,
    schedules.is_reschedule,
    schedules.is_confirmed,
    schedules.is_completed,
    schedules.is_canceled,
    schedules.is_unsuccessful
  FROM
    dw_visit.fact_visit_schedules AS schedules
      left join
        dw_visit.dim_business_context as bc
        on bc.sk_business_context = schedules.sk_business_context
      left join
        dw_visit.dim_behavior as behavior
        on schedules.sk_behavior_type = behavior.sk_behavior_type
      left join
        dw_visit.dim_business_model as bm
        on schedules.sk_business_model = bm.sk_business_model
      left join dw_visit.dim_entrance_type as et on schedules.sk_entrance_type = et.sk_entrance_type
  where
    schedules.sk_succeed_schedule is null
)
select
  schedules.visit_code,
  schedules.sk_schedule as id_booking,
  schedules.is_reschedule,
  schedules.is_completed,
  schedules.is_canceled,
  schedules.is_unsuccessful,
  visits.is_registered,
  cancelation_details.channel as cancelation_channel,
  cancelation_details.reason as cancelation_reason,
  cancelation_details.on_behalf_of as cancelation_on_behalf_of,
  schedules.has_tenant_living,
  schedules.entrance_type,
  schedules.sk_author_creator,
  schedules.behavior_type,
  schedules.business_model,
  if(
    schedules.sk_author_creator = schedules.sk_visitor,
    'Demand',
    if(schedules.sk_author_creator = schedules.sk_user_agent, 'Agent', 'OPS')
  ) as author_user_role,
  date_format.date as visit_date,
  visits.ts_visit_local_tz as ts_visit_date,
  rating_agent.status as review_status,
  cast(coalesce(rating_agent.review_date, rating_house.review_date) as timestamp) as ts_review_date,
  if(
    (rating_agent.review_date is null and rating_house.review_date is null), false, true
  ) as has_visit_review,
  schedules.sk_house AS house_id,
  schedules.sk_visitor AS user_id,
  schedules.sk_agent AS agent_id,
  date(dim_agent.ts_created) AS ts_5a_agent_created,
  date_diff(YEAR, dim_agent.ts_created, now()) as years_as_5a_agent,
  date_diff(MONTH, dim_agent.ts_created, now()) as months_as_5a_agent,
  dim_region.city_group AS city_group,
  dim_region.city_name AS city_name,
  dim_region.region_code AS region_code,
  schedules.business_context,
  if(
    rating_agent.journey_step = 'visit_done_agent_rating'
    or rating_house.journey_step = 'house_rating',
    'Visit Completed',
    if(rating_agent.journey_step = 'visit_incomplete_agent_rating', 'Visit Incomplete', NULL)
  ) as review_chosen_type,
  if(rating_agent.review_date is null and rating_house.review_date is null,null,
  if(
      schedules.is_completed = 1,
      'Visit Completed',
      if(
        schedules.is_unsuccessful = 1,
        'Visit Incomplete',
        if(
          schedules.is_canceled = 1
          AND cancelation_details.on_behalf_of = 'DEMAND'
          AND cancelation_details.channel <> 'TENANT_PWA'
          AND cancelation_details.channel <> 'TENANT_NATIVE',
          'Visit Incomplete',
            if(
              schedules.is_completed = 0
              and schedules.is_unsuccessful = 0
              and schedules.is_canceled = 0,
              'Stalled',
              'Error'
            )
          )
        )
      )
      )
     as review_original_type,
  
    if(
      schedules.is_completed = 1,
      'Visit Completed',
      if(
        schedules.is_unsuccessful = 1,
        'Visit Unsuccessful',
        if(
          schedules.is_canceled = 1
          AND cancelation_details.on_behalf_of = 'DEMAND'
          AND cancelation_details.channel <> 'TENANT_PWA'
          AND cancelation_details.channel <> 'TENANT_NATIVE',
          'Visit Canceled on Behalf of Demand',
          if(
            schedules.is_canceled = 1,
            'Visit Canceled Not on Behalf of Demand',
            if(
              schedules.is_completed = 0
              and schedules.is_unsuccessful = 0
              and schedules.is_canceled = 0,
              'Stalled',
              'Error'
            )
          )
        )
      )
    ) as visit_status,
  if(
    rating_agent.rating_selected is null,
    null,
    if(substring(rating_agent.rating_selected, 2, 1) = '5', '5 stars', 'Not 5 stars')
  ) AS agent_rating_type,
  cast(substring(rating_agent.rating_selected, 2, 1) as integer) AS agent_rating,
  if(
    rating_agent_selection.rating_selected is null,
    null,
    if(
      rating_agent_selection.rating_selected
      = '[Pontualidade, Gentileza, respeito e atenção, Conhecimento sobre o imóvel, condomínio e/ou região, Conhecimento sobre o processo de aluguel e venda]'
      or rating_agent_selection.rating_selected
      = '[Ser mais pontual, Evitar a sugestão de negociar fora do QuintoAndar, Ser mais gentil e/ou atencioso, Ter mais conhecimento sobre o imóvel, condomínio e/ou região, Ter mais conhecimento sobre o processo de aluguel ou venda]'
      or rating_agent_selection.rating_selected
      = '[Outro, Ser mais pontual, Entrar em contato comigo, Evitar a sugestão de negociar fora do QuintoAndar, Ser mais gentil e/ou atencioso]'
      or rating_agent_selection.rating_selected
      = '[Outro, Pontualidade, Gentileza, respeito e atenção]',
      false,
      true
    )
  ) as fixed_agent_rating_selected,
  if(
    rating_agent_selection.rating_selected is null,
    null,
    if(
      rating_agent_selection.rating_selected not like '%punctuality%',
      null,
      if(substring(rating_agent.rating_selected, 2, 1) = '5', 'Good', 'Needs Improvement')
    )
  ) as agent_punctuality,
  if(
    rating_agent_selection.rating_selected is null,
    null,
    if(
      rating_agent_selection.rating_selected not like '%thoughtfulness%',
      null,
      if(substring(rating_agent.rating_selected, 2, 1) = '5', 'Good', 'Needs Improvement')
    )
  ) as agent_thoughtfulness,
  if(
    rating_agent_selection.rating_selected is null,
    null,
    if(
      rating_agent_selection.rating_selected not like '%house_features_knowledge%',
      null,
      if(substring(rating_agent.rating_selected, 2, 1) = '5', 'Good', 'Needs Improvement')
    )
  ) as agent_house_features_knowledge,
  if(
    rating_agent_selection.rating_selected is null,
    null,
    if(
      rating_agent_selection.rating_selected not like '%rent_sale_process_knowledge%',
      null,
      if(substring(rating_agent.rating_selected, 2, 1) = '5', 'Good', 'Needs Improvement')
    )
  ) as agent_rent_sale_process_knowledge,
  if(
    rating_agent_selection.rating_selected is null,
    null,
    if(
      rating_agent_selection.rating_selected not like '%get_in_touch%',
      null,
      if(substring(rating_agent.rating_selected, 2, 1) = '5', 'Good', 'Needs Improvement')
    )
  ) as agent_get_in_touch,
  if(
    rating_agent_selection.rating_selected is null,
    null,
    if(
      rating_agent_selection.rating_selected not like '%bypass_attempt%',
      null,
      if(substring(rating_agent.rating_selected, 2, 1) = '5', 'Good', 'Needs Improvement')
    )
  ) as agent_bypass_attempt,
  if(
    rating_agent_selection.rating_selected is null,
    null,
    if(
      rating_agent_selection.rating_selected not like '%other%',
      null,
      if(substring(rating_agent.rating_selected, 2, 1) = '5', 'Good', 'Needs Improvement')
    )
  ) as agent_other,
  rating_agent_comment.comment AS agent_rating_comment,
  if(
    rating_house.rating_selected is null,
    null,
    if(
      rating_house.rating_selected is null,
      null,
      if(substring(rating_house.rating_selected, 2, 3) = 'yes', 'Liked', 'Partially Liked or No')
    )
  ) AS house_rating_type,
  substring(
    rating_house.rating_selected, 2, length(rating_house.rating_selected) - 2
  ) AS house_rating,
  if(
    rating_house_selection.rating_selected is null,
    null,
    if(
      rating_house_selection.rating_selected is null
      or rating_house_selection.rating_selected not like '%location%',
      null,
      if(substring(rating_house.rating_selected, 2, 3) = 'yes', 'Good', 'Needs Improvement')
    )
  ) as house_location,
  if(
    rating_house_selection.rating_selected is null,
    null,
    if(
      rating_house_selection.rating_selected is null
      or rating_house_selection.rating_selected not like '%house_conservation%',
      null,
      if(substring(rating_house.rating_selected, 2, 3) = 'yes', 'Good', 'Needs Improvement')
    )
  ) as house_conservation,
  if(
    rating_house_selection.rating_selected is null,
    null,
    if(
      rating_house_selection.rating_selected is null
      or rating_house_selection.rating_selected not like '%neighborhood%',
      null,
      if(substring(rating_house.rating_selected, 2, 3) = 'yes', 'Good', 'Needs Improvement')
    )
  ) as house_neighborhood,
  if(
    rating_house_selection.rating_selected is null,
    null,
    if(
      rating_house_selection.rating_selected is null
      or rating_house_selection.rating_selected not like '%cost_benefit%',
      null,
      if(substring(rating_house.rating_selected, 2, 3) = 'yes', 'Good', 'Needs Improvement')
    )
  ) as house_cost_benefit,
  if(
    rating_house_selection.rating_selected is null,
    null,
    if(
      rating_house_selection.rating_selected is null
      or rating_house_selection.rating_selected not like '%condominium_features%',
      null,
      if(substring(rating_house.rating_selected, 2, 3) = 'yes', 'Good', 'Needs Improvement')
    )
  ) as house_condominium_features,
  if(
    rating_house_selection.rating_selected is null,
    null,
    if(
      rating_house_selection.rating_selected is null
      or rating_house_selection.rating_selected not like '%add_discrepancies%',
      null,
      if(substring(rating_house.rating_selected, 2, 3) = 'yes', 'Good', 'Needs Improvement')
    )
  ) as house_ad_discrepancies,
  rating_house_comment.comment AS house_rating_comment
FROM
  schedules as schedules
    LEFT JOIN dw_visit.fact_visits as visits on schedules.sk_visit = visits.sk_visit
    LEFT JOIN
      datalake_ebdb_clean.visit_cancellation_details AS cancelation_details
      on cancelation_details.id = visits.sk_cancellation_detail
    LEFT JOIN
      dw_public.dim_date as date_format
      on visits.sk_visit_date_local_tz = date_format.sk_date
    LEFT JOIN dw_public.dim_region AS dim_region ON schedules.sk_region = dim_region.sk_region
    LEFT JOIN dw_public.dim_agent AS dim_agent ON dim_agent.sk_agent = schedules.sk_agent
    LEFT JOIN
      rating as rating_agent
      on
        rating_agent.visit_code = schedules.visit_code
        and rating_agent.journey_step in (
          'visit_done_agent_rating', 'visit_incomplete_agent_rating'
        )
    LEFT JOIN
      rating as rating_agent_selection
      on
        rating_agent_selection.visit_code = schedules.visit_code
        and rating_agent_selection.journey_step in (
          'visit_done_agent_rating_unsatisfied',
          'visit_done_agent_rating_unsatisfied_v2',
          'visit_done_agent_rating_satisfied',
          'visit_incomplete_agent_rating_unsatisfied',
          'visit_incomplete_agent_rating_unsatisfied_v2',
          'visit_incomplete_agent_rating_satisfied'
        )
    LEFT JOIN
      rating as rating_agent_comment
      on
        rating_agent_comment.visit_code = schedules.visit_code
        and rating_agent_comment.journey_step in (
          'visit_done_agent_rating_unsatisfied',
          'visit_done_agent_rating_unsatisfied_v2',
          'visit_done_agent_rating_satisfied',
          'visit_incomplete_agent_rating_unsatisfied',
          'visit_incomplete_agent_rating_unsatisfied_v2',
          'visit_incomplete_agent_rating_satisfied'
        )
    LEFT JOIN
      rating as rating_house
      on
        rating_house.visit_code = schedules.visit_code
        and rating_house.journey_step in ('house_rating')
    LEFT JOIN
      rating as rating_house_selection
      on
        rating_house_selection.visit_code = schedules.visit_code
        and rating_house_selection.journey_step in (
          'house_rating_visitor_not_interested', 'house_rating_visitor_interested'
        )
    LEFT JOIN
      rating as rating_house_comment
      on
        rating_house_comment.visit_code = schedules.visit_code
        and rating_house_comment.journey_step in (
          'house_rating_visitor_not_interested', 'house_rating_visitor_interested'
        )
where
  (
    rating_agent.review_date is null
    or date(rating_agent.review_date) < date(now())
  )
  and date(date_format.date) < date(now())
  and dim_region.country_name = 'Brazil'
 ),
  contract_count AS (
  SELECT  
    id_user, 
    COUNT(DISTINCT case when contract_role = 'tenant' then contract_role else contract_role end)  
  FROM datalake_ebdb_contract.contract_person
  GROUP BY 
        1
  HAVING COUNT(DISTINCT case when contract_role = 'tenant' then contract_role else contract_role end)   = 1
), final as (
  SELECT
    DATE(ts_review_date) AS posted_at,
    id_booking as feedback_id,
    user_id as author_id,
    city_group,
    agent_rating AS rating,
    CASE WHEN agent_rating = 5 or agent_rating = 4 THEN 'promoter'
        WHEN agent_rating = 3 THEN 'passive'
        WHEN agent_rating = 2 or agent_rating = 1 THEN 'detractor' 
        ELSE  '' END AS csat_score_category,
        TRIM(
              CONCAT_WS(' ', 
                  CASE 
                      WHEN agent_rating_comment IS NOT NULL AND agent_rating_comment <> '' THEN
                          CASE 
                              WHEN agent_rating IN (2, 1) THEN 'Motivo da minha insatisfação:'
                              WHEN agent_rating IN (3) THEN 'Motivo da minha nota:'
                              WHEN agent_rating IN (5, 4) THEN 'Motivo da minha satisfação:'
                              ELSE '' 
                          END
                      ELSE ''
                  END,
                  CASE WHEN agent_rating_comment IS NOT NULL AND agent_rating_comment <> '' THEN agent_rating_comment ELSE NULL END
              )
          ) AS text,
    --business_context,
    --review_status,
    CASE WHEN review_chosen_type = 'Visit Incomplete' AND business_context = 'RENT' THEN 'DSAT Visitas Incompletas - FR'
        WHEN review_chosen_type = 'Visit Incomplete' AND business_context = 'SALE' THEN 'DSAT Visitas Incompletas - FS'
        WHEN review_chosen_type = 'Visit Completed' AND business_context = 'RENT' THEN 'DSAT Visitas Completas - FR'
        WHEN review_chosen_type = 'Visit Completed' AND business_context = 'SALE' THEN 'DSAT Visitas Completas - FS'
        ELSE '' END AS nome_campanha,
    MAX(case when contract_count.id_user is null then null
        when contract_role = 'tenant' then contract_role 
        else contract_role end) AS customer_type,
    CONCAT(cast(id_booking as string), '_', cast(user_id as string)) AS account_id
    from post_visit_review pv
    LEFT JOIN datalake_ebdb_contract.contract_person contract
      ON contract.id_user = pv.user_id
    LEFT JOIN contract_count
      ON contract_count.id_user = contract.id_user
    WHERE review_status = 'DONE'
    and DATE(ts_review_date) >= DATE('2025-03-10')
    GROUP BY 1,2,3,4,5,6,7,8,10
),
final_2 AS (
  select 
    posted_at,
    feedback_id,
    author_id,
    city_group,
    rating,
    csat_score_category,
    text,
    nome_campanha,
    COALESCE(final.customer_type, CASE WHEN tem_imovel = '1' THEN 'landlord' WHEN tem_imovel = '0' THEN 'tenant' ELSE NULL END) AS customer_type,
    account_id
  from 
    final
  left join dw_public.dim_user d
    on final.author_id = d.sk_user
),
final_3 AS (
  SELECT
    DATE(posted_at) AS posted_at,
    feedback_id,
    author_id,
    city_group,
    rating,
    csat_score_category,
    text,
    nome_campanha,
    CASE WHEN nome_campanha LIKE '%FS' AND customer_type = 'Inquilino' THEN 'buyer'
        WHEN nome_campanha LIKE '%FS' AND customer_type = 'Proprietario' THEN 'seller' ELSE customer_type END AS customer_type,
    account_id
  FROM 
    final_2
)
SELECT
  date_format(posted_at, 'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'') AS posted_at,
  feedback_id,
  author_id,
  city_group,
  rating,
  csat_score_category,
  text,
  nome_campanha AS csat_campanha,
  customer_type,
  account_id || 
    CASE 
        WHEN customer_type IS NOT NULL AND customer_type <> '' THEN '_' || 
            CASE 
                WHEN customer_type = 'Inquilino' THEN 'tenant'
                WHEN customer_type = 'Proprietario' THEN 'landlord'
                ELSE customer_type
            END
        ELSE ''
    END AS account_id
FROM 
  final_3