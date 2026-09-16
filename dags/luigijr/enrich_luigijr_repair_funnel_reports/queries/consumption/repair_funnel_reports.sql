with df_repairs AS (

with contestation_iq as
(
    select
        a.id_repair_request,
        a.ts_created,
        a.reason,
        a.comment
    from datalake_inspection_services_clean.contestation a

    inner join  (
    select
    id_repair_request,
    max(ts_created) as ts_created

    from  datalake_inspection_services_clean.contestation

    group by 1
            ) b
    on a. ts_created = b.ts_created and a.id_repair_request = b.id_repair_request
)

,inspection as
    (
        select
            fi.sk_contract,
            fi.sk_assessment,
            fi.sk_inspection,
            fi.sk_main_inspection,
            fi.sk_inspector,
            fi.ts_synced,
            fi.sk_client_side,
            concat('https://crm-pwa-imoveis.quintoandar.com.br/imoveis/',
    cast(fi.sk_house as STRING),
    '/vistorias/',
    cast(fi.sk_client_side as STRING), -- Specify the data type here
    '/revisar') as link_vistoria,
            CASE WHEN dc.rent >= 2500 THEN 'high_value' ELSE 'low_value' END as high_value_tag,
            dhl.house_total_area,
            dc.rent,
            cca.risk_category_canon


        from dw_inspections.fact_inspection fi
        left join dw_inspections.dim_inspection di
        	on fi.sk_inspection = di.sk_inspection
        left join dw_rent.dim_contract dc
            on dc.sk_contract = fi.sk_contract
        left join dw_rent.dim_house_listing dhl
            on dhl.id_house = fi.sk_house and dhl.is_last_version = True
        left join ( select pcf.sk_contract,
                    dca.risk_category_canon

                    from dw_credit.fact_proposal_credit_flows pcf
                    left join dw_credit.dim_credit_analysis dca
                        on pcf.sk_credit_analysis = dca.id_credit_analysis ) as cca
                    on cca.sk_contract = fi.sk_contract


        where fi.ts_synced is not null
            and di.status NOT IN ('cancelled', 'scheduled')
            and di.inspection_type in ('offboarding','verification')
            and fi.ts_synced >= date_add(current_date(), -120)


    )

 , base as
(
    select DISTINCT
            i.sk_inspection,
            i.sk_inspector,
            i.sk_contract,
            rr.id_repair_request,
            is_exempted,
            createdBy.reviewer_type as createdBy,
            rr.type,
            ig.name,
            room_name,
            rr.comment,
            grantedBy.reviewer_type as grantedBy,
            rr.ts_granted  as dt_granted_by,
            rr.responsibility,
            rr.cost,
            rr.ts_created as dt_created,
            grantedBy.approval_type,
            createdBy.approval_type as created_type,
            duc.email as email_created,
            dug.email as email_granted,
            i.link_vistoria,
            i.sk_client_side,
            rr.id_item_group,
            high_value_tag,
            house_total_area,
            rr.repair_service,
            rent,
            risk_category_canon as risk_category



    from datalake_inspection_services_clean.repair_request rr
    left join datalake_inspection_services_clean.reviewer createdBy
        on createdBy.id_reviewer = rr.id_reviewer
    inner join datalake_inspection_services_clean.item_group ig
        on rr.id_item_group = ig.id_item_group
    inner join datalake_inspection_services_clean.room r
        on ig.id_room = r.id_room
    inner join inspection i
        on i.sk_assessment = r.id_assessment
    left join datalake_inspection_services_clean.reviewer grantedBy
        on grantedBy.id_reviewer = rr.id_granted_by
    left join dw_public.dim_user duc
        on duc.sk_user = createdBy.id_user
    left join dw_public.dim_user dug
        on dug.sk_user = grantedBy.id_user


    where
        NOT(createdBy.reviewer_type = 'INSPECTIONS_SERVICE' AND (has_automatic_identification_accepted = False OR has_automatic_identification_accepted is null) )

)

,all as (

        select DISTINCT

        id_repair_request,
        createdBy,
        name,
        room_name,
        dt_created,
        id_item_group,
        sk_inspection,
        sk_inspector,
        sk_contract,
        link_vistoria,
        sk_client_side,
        high_value_tag,
        house_total_area,
        rent,
        risk_category


        from base

)
, automatic_repairs as
(
    select DISTINCT

            b.id_repair_request,
            is_exempted,
            createdBy,
            type,
            comment,
            responsibility,
            email_granted


    from base b


    where createdBy = 'INSPECTIONS_SERVICE' AND (approval_type is null or approval_type = 'REPAIR_ANALYSIS' )

)

 ,repair_analysis as
(

    select DISTINCT

            b.id_repair_request,
            is_exempted,
            createdBy,
            type,
            comment,
            responsibility,
            email_created


    from base b


    where  createdBy = 'ADMIN' AND (approval_type is null OR approval_type = 'REPAIR_ANALYSIS')

)
, review_comment as

(
     select DISTINCT

            b.id_repair_request,
            is_exempted,
            createdBy,
            type,
            comment,
            responsibility


    from base b
        where  createdBy = 'OWNER' AND (approval_type is null OR approval_type = 'REVIEW')

)

, review as
(

select DISTINCT
    b.id_repair_request,
    is_exempted,
    grantedBy,
    b.dt_granted_by,
    responsibility,
    b.comment,
    b.type

from base b
inner join
        (
            select id_repair_request,
            max(dt_granted_by) as dt_granted_by

            from base

            where approval_type = 'REVIEW' and (createdBy = 'ADMIN' OR createdBy= 'INSPECTIONS_SERVICE')

            group by 1


        ) max_review
    on b.id_repair_request = max_review.id_repair_request and b.dt_granted_by = max_review.dt_granted_by


)

, contestation as (

    select
        b.id_repair_request,
        is_exempted as is_exempted_AC,
        type as reason_AC,
        comment as comment_AC,
        b.grantedBy as grantedBy_AC,
        b.dt_granted_by  as dt_granted_by_AC,
        responsibility as responsibility_AC,
        b.cost,
        email_granted,
        repair_service


    from base b
    inner join
        (
            select id_repair_request,
            max(dt_granted_by) as dt_granted_by

            from base

            where approval_type = 'CONTESTATION_ANALYSIS'

            group by 1

        ) max_review_c

    on b.id_repair_request = max_review_c.id_repair_request and b.dt_granted_by = max_review_c.dt_granted_by

    where approval_type = 'CONTESTATION_ANALYSIS'

)

, budget_approval_iq (

    select distinct
        i.sk_contract,
        reviewer_type as reviewer_type_iq,
        approval_reason as approval_reason_iq,
        approval_comment as approval_comment_iq,
        is_approved as is_approved_iq,
        ts_updated as ts_updated_iq

    from ( select
            r.id_assessment,
            reviewer_type,
            approval_reason,
            approval_comment,
            is_approved,
            ts_updated

        from datalake_inspection_services_clean.reviewer r
        inner join (
                select
                id_assessment,
                max(ts_updated) as max_ts_updated

                from datalake_inspection_services_clean.reviewer
                where approval_type = 'BUDGET_APPROVAL' and reviewer_type ='TENANT'

                group by 1
                ) max_r
            on max_r.id_assessment = r.id_assessment and max_r.max_ts_updated = r.ts_updated

        ) rev

        left join inspection i
       on  i.sk_assessment = rev.id_assessment

)

, budget_approval_pp (

    select distinct
        i.sk_contract,
        reviewer_type as reviwer_type_pp,
        approval_reason as approval_reason_pp,
        approval_comment as approval_comment_pp,
        is_approved as is_approved_pp,
        ts_updated as ts_updated_pp


    from ( select
            r.id_assessment,
            reviewer_type,
            approval_reason,
            approval_comment,
            is_approved,
            ts_updated

        from datalake_inspection_services_clean.reviewer r
        inner join (
                select
                id_assessment,
                max(ts_updated) as max_ts_updated

                from datalake_inspection_services_clean.reviewer
                where approval_type = 'BUDGET_APPROVAL' and reviewer_type ='OWNER'

                group by 1
                ) max_r
            on max_r.id_assessment = r.id_assessment and max_r.max_ts_updated = r.ts_updated

        ) rev

        left join inspection i
       on  i.sk_assessment = rev.id_assessment

)

, final as (
    select DISTINCT
        all.sk_inspection,
        all.sk_inspector,
        all.sk_contract,
        all.id_repair_request,
        all.room_name,
        all.name,
        all.createdBy,
        coalesce(ra.type,rc.type,si.type,r.type, if(all.createdBy='INSPECTIONS_SERVICE',c.reason_AC,null)) as type,
        all.dt_created,
        coalesce(ra.comment,rc.comment,si.comment, r.comment, if(all.createdBy='INSPECTIONS_SERVICE',c.comment_AC,null)) as comment,
        r.grantedBy,
        coalesce(r.is_exempted,ra.is_exempted,rc.is_exempted,si.is_exempted) as is_exempted,
        coalesce(r.responsibility,ra.responsibility,rc.responsibility,si.responsibility) as responsibility,
        r.dt_granted_by,
        ci.reason as reason_iq ,
        ci.ts_created as dt_created_iq,
        ci.comment as comment_iq,
        c.grantedBy_AC,
        c.is_exempted_AC,
        responsibility_AC,
        reason_AC,
        dt_granted_by_AC,
        comment_AC,
        c.cost,
        -- item_comment_agg,
        -- tag_item_type,
        -- tag_issue_type,
        -- tag_issue_comment,
        -- icf.comment_count,
        -- icf.tag_count,
        sk_client_side,
        coalesce(si.email_granted,ra.email_created) as AR_email,
        c.email_granted as AC_email,
        high_value_tag,
        all.id_item_group,
        reviewer_type_iq,
        approval_reason_iq,
        approval_comment_iq,
        is_approved_iq,
        ts_updated_iq,
        reviwer_type_pp,
        approval_reason_pp,
        approval_comment_pp,
        is_approved_pp,
        ts_updated_pp,
        house_total_area,
        repair_service,
        rent,
        risk_category


from all
left join automatic_repairs si
    on all.id_repair_request = si.id_repair_request
left join repair_analysis ra
    on all.id_repair_request = ra.id_repair_request
left join review_comment rc
    on all.id_repair_request = rc.id_repair_request
left join review r
    on all.id_repair_request = r.id_repair_request
left join contestation c
    on all.id_repair_request = c.id_repair_request
left join contestation_iq ci
    on all.id_repair_request = ci.id_repair_request
-- left join inspection_comment_final icf
--     on all.id_item_group = icf.sk_item_group
left join budget_approval_iq baiq
    on baiq.sk_contract = all.sk_contract
left join budget_approval_pp bapp
    on bapp.sk_contract = all.sk_contract

order by dt_created desc
),

exempted_by_owner_from_BA as (
select distinct f.id_item_group
from final f
left join dw_inspections.fact_repair_request frr on f.id_item_group = frr.sk_item_group
where frr.is_exempted_by_owner_from_budget = true
),

spoc_contracts as (
select distinct sk_contract
from dw_offboarding.fact_terminations
where is_spoc_contract = true --is_spoc_control_group = true

)

select
id_repair_request,
f.sk_contract,
f.id_item_group,
room_name,
name,
createdBy,
type,
dt_created,
comment,
grantedBy,
f.is_exempted,
responsibility,
dt_granted_by,
reason_iq,
dt_created_iq,
comment_iq,
grantedBy_AC,
is_exempted_AC,
responsibility_AC,
reason_AC,
dt_granted_by_AC,
comment_AC,
cost,
-- item_comment_agg,
-- tag_item_type,
-- tag_issue_type,
-- tag_issue_comment,
-- comment_count,
-- tag_count,
sk_client_side,
-- CASE
--     WHEN tag_count IS NULL AND comment_count IS NULL THEN 'sem tag/comment'
--     WHEN (tag_count IS NULL OR tag_count = 0) AND (comment_count IS NOT NULL AND comment_count > 0) THEN 'só comentário'
--     WHEN (tag_count IS NOT NULL AND tag_count > 0) AND (comment_count IS NULL OR comment_count = 0) THEN 'só tag'
--     WHEN (tag_count IS NOT NULL AND tag_count > 0) AND (comment_count IS NOT NULL AND comment_count > 0) THEN 'tag & comentário'
--     ELSE 'unknown'
-- END AS `TAG/COMMENT`,
AR_email,
AC_email,
high_value_tag,
null as  `bytag?`,
null as  `nps owner`,
null as  `nps tenant`,
if (name in ( 'Armários','Balcão (Bancada)','Cadeiras','Cama','Cortinas','Espelho','Gabinete',
'Mesa','Painel de televisão','Persianas','Prateleiras','Rack','Sofá','Pintura','Piso','Porta','Limpeza'),'3pml','not 3pml') as 3pml,
if( (createdBy = 'INSPECTIONS_SERVICE' or createdBy = 'ADMIN' ) and (grantedBy is null ) and (f.is_exempted = True),'AR isentou',
if( (createdBy = 'INSPECTIONS_SERVICE' or createdBy = 'ADMIN' ) and (grantedBy is null) and (f.is_exempted = False), 'AR cobrou [PP não interagiu]',
if( (createdBy = 'INSPECTIONS_SERVICE' or createdBy = 'ADMIN' ) and (grantedBy ='OWNER') and (f.is_exempted = False) , 'AR cobrou [PP cobrou]',
if((createdBy = 'INSPECTIONS_SERVICE' or createdBy = 'ADMIN' ) and (grantedBy ='OWNER') and (f.is_exempted = True) , 'AR cobrou [PP isentou]',
if( createdBy = 'OWNER', 'PP comentou' , 'AR cobrou [PP não interagiu]') ) ) ) ) as status_AR,
reviewer_type_iq,
approval_reason_iq,
approval_comment_iq,
is_approved_iq,
ts_updated_iq,
reviwer_type_pp,
approval_reason_pp,
approval_comment_pp,
is_approved_pp,
ts_updated_pp,
house_total_area,
repair_service,
rent,
risk_category,
f.sk_inspection,
case when ba.id_item_group is not null then true else false end as exempted_by_owner_from_ba,
case when spc.sk_contract is not null then true else false end as spoc_contracts
from final f
left join exempted_by_owner_from_BA ba on f.id_item_group = ba.id_item_group
left join spoc_contracts spc on f.sk_contract = spc.sk_contract
where dt_created >= date('2025-01-01')
),
df_tags AS (
 with inspection as
    (
        select
            fi.sk_contract,
            fi.sk_assessment,
            fi.sk_inspection,
            fi.sk_main_inspection,
            fi.sk_inspector,
            fi.ts_synced,
            fi.sk_client_side,
            CASE WHEN dc.rent >= 2500 THEN 'high_value' ELSE 'low_value' END as high_value_tag,
            dhl.house_total_area,
            dc.rent,
            cca.risk_category_canon


        from dw_inspections.fact_inspection fi
        left join dw_inspections.dim_inspection di
        	on fi.sk_inspection = di.sk_inspection
        left join dw_rent.dim_contract dc
            on dc.sk_contract = fi.sk_contract
        left join dw_rent.dim_house_listing dhl
            on cast(dhl.id_house as varchar(255)) = fi.sk_house and dhl.is_last_version = True
        left join ( select pcf.sk_contract,
                    dca.risk_category_canon

                    from dw_credit.fact_proposal_credit_flows pcf
                    left join dw_credit.dim_credit_analysis dca
                        on pcf.sk_credit_analysis = dca.id_credit_analysis ) as cca
                    on cca.sk_contract = fi.sk_contract


        where fi.ts_synced is not null
            and di.status NOT IN ('cancelled', 'scheduled')
            and di.inspection_type in ('offboarding','verification')
            and fi.ts_synced >= date('2025-01-01')


    )

  , base_tags as (

    SELECT DISTINCT

        i.sk_contract,
        concat( cast(i2.id_item as STRING),"-",cast(it.id_item_type as STRING), if(id_item_issue
        is null,"",concat("-",cast(id_item_issue as STRING)) )) as id_item_type_issue ,
        ig.id_item_group,
        r.room_name,
        ig.name item_group_name,
        it.type item_type_name,
        iit.type issue_type_name,
        ig.status,
        ig.is_inferior_quality,
        i2.comment,
        ii.comment as issue_comment,
        is_present,
        i2.is_active ,
        ii.is_active as is_active_issue,
        ig.is_active_status,
        ig.is_active_inferior_quality,
        i2.ts_created,
        i2.ts_updated as ts_updated_item,
        ii.ts_updated as ts_updated_issue,
        ig.ts_updated as ts_updated_status

    FROM inspection i
    INNER JOIN datalake_inspection_services_clean.assessment a ON cast(a.id_inspection as STRING) = i.sk_inspection
    INNER JOIN datalake_inspection_services_clean.room r ON r.id_assessment = a.id_assessment
    INNER JOIN datalake_inspection_services_clean.item_group ig ON ig.id_room = r.id_room
    INNER JOIN datalake_inspection_services_clean.item i2 ON i2.id_item_group = ig.id_item_group
    INNER JOIN datalake_inspection_services_clean.item_type it ON it.id_item_type = i2.id_type
    LEFT JOIN datalake_inspection_services_clean.item_issue ii ON ii.id_item = i2.id_item
    LEFT JOIN datalake_inspection_services_clean.issue_type iit ON iit.id_issue_type = ii.id_type

  )

,partition_bt as (
    SELECT
    sk_contract,
    id_item_type_issue,
    id_item_group,
    room_name,
    item_group_name,
    item_type_name,
    issue_type_name,
    status,
    is_inferior_quality,
    comment,
    issue_comment,
    is_present,
    is_active,
    is_active_issue,
    is_active_status,
    is_active_inferior_quality,
    ts_created,
    ts_updated_item,
    ts_updated_issue,
    ts_updated_status,
    ROW_NUMBER() OVER(PARTITION BY id_item_type_issue ORDER BY ts_updated_item ) un_item_min,
    ROW_NUMBER() OVER(PARTITION BY id_item_type_issue ORDER BY ts_updated_item desc) un_item_max,

    ROW_NUMBER() OVER(PARTITION BY id_item_type_issue ORDER BY ts_updated_issue ) un_issue_min,
    ROW_NUMBER() OVER(PARTITION BY id_item_type_issue ORDER BY ts_updated_issue desc) un_issue_max,

    ROW_NUMBER() OVER(PARTITION BY id_item_type_issue ORDER BY ts_updated_status ) un_status_min,
    ROW_NUMBER() OVER(PARTITION BY id_item_type_issue ORDER BY ts_updated_status desc) un_status_max

    FROM base_tags

)
,house_room_item as (
SELECT DISTINCT

      sk_contract,
      id_item_type_issue ,
      id_item_group,
      room_name,
      item_group_name,
      is_present

      FROM base_tags
)
, tags_comments_before_after as (
select
  hri.sk_contract,
  hri.id_item_type_issue,
  hri.id_item_group,
  hri.room_name,
  hri.item_group_name,
  hri.is_present,

  pb_item_min.item_type_name,
  pb_item_min.comment as comment_VT,
  pb_item_max.comment as comment_AR,
  pb_item_max.is_active as is_active_max,
  pb_item_max.ts_updated_item,

  pb_issue_min.issue_type_name,
  pb_issue_min.issue_comment,
  pb_issue_max.is_active_issue as is_active_issue_max,
  pb_issue_max.ts_updated_issue,



  case when
  (pb_item_min.item_type_name is not null and hri.is_present = True and pb_item_min.item_type_name !='overview')
  or (pb_issue_min.issue_type_name is not null and pb_issue_min.issue_type_name!='working')
  then 1 else 0
  end as tag_count_min,

  case when pb_item_min.comment is not null and pb_item_min.comment != "" and
  pb_item_min.item_type_name !='other' then 1 else 0 end as comment_count_min,

  case
  when pb_item_min.comment is not null and pb_item_max.comment is not null then
  if(pb_item_min.comment != pb_item_max.comment,1,0)
  when pb_item_min.comment is  null and pb_item_max.comment is  null then 0
  when pb_item_min.comment is  null and pb_item_max.comment is not null then
  if(pb_item_max.comment != "" ,1,0)
  when pb_item_min.comment is  not null and pb_item_max.comment is  null then
  if(pb_item_min.comment != "" ,1,0)
  end as comment_changed,

  case when pb_item_min.comment is not null and pb_item_min.comment != ""
       and pb_item_max.comment = "" then 1 else 0
  end as comment_erased

from house_room_item hri

left join partition_bt pb_item_min
  on hri.id_item_type_issue = pb_item_min.id_item_type_issue and pb_item_min.un_item_min = 1
left join partition_bt pb_item_max
  on hri.id_item_type_issue = pb_item_max.id_item_type_issue and pb_item_max.un_item_max = 1

left join partition_bt pb_issue_min
  on hri.id_item_type_issue = pb_issue_min.id_item_type_issue and pb_issue_min.un_issue_min = 1
left join partition_bt pb_issue_max
  on hri.id_item_type_issue = pb_issue_max.id_item_type_issue and pb_issue_max.un_issue_max = 1

)
, before_after_aux as (
select
  sk_contract,
  id_item_type_issue,
  id_item_group,
  room_name,
  item_group_name,
  is_present,
  item_type_name,
  comment_VT,
  comment_AR,
  is_active_max,
  ts_updated_item,
  issue_type_name,
  issue_comment,
  is_active_issue_max,
  ts_updated_issue,
  tag_count_min,
  comment_count_min,
  comment_changed,
  comment_erased,

CASE
WHEN ( tag_count_min = 1 and comment_count_min = 0 and is_active_max = FALSE and is_active_issue_max = FALSE and comment_changed = 0 )
OR ( tag_count_min = 0 and comment_count_min = 0 and is_active_max is  null and is_active_issue_max = TRUE and comment_changed = 0 )
OR ( tag_count_min = 0 and comment_count_min = 1 and is_active_max = TRUE and is_active_issue_max is  null and comment_changed = 1 and comment_erased = 1)
OR ( tag_count_min = 1 and comment_count_min = 0 and is_active_max = FALSE and is_active_issue_max is  null and comment_changed = 0 )
OR ( tag_count_min = 0 and comment_count_min = 0 and is_active_max = FALSE and is_active_issue_max is  null and comment_changed = 0 )
OR ( tag_count_min = 1 and comment_count_min = 0 and is_active_max is  null and is_active_issue_max = FALSE and comment_changed = 0 )
OR ( tag_count_min = 1 and comment_count_min = 1 and is_active_max = TRUE and is_active_issue_max = FALSE and comment_changed = 1 )
OR ( tag_count_min = 0 and comment_count_min = 0 and is_active_max = TRUE and is_active_issue_max is  null and comment_changed = 0 )
OR ( tag_count_min = 0 and comment_count_min = 0 and is_active_max = FALSE and is_active_issue_max = FALSE and comment_changed = 0 )
OR ( tag_count_min = 1 and comment_count_min = 0 and is_active_max = FALSE and is_active_issue_max = TRUE and comment_changed = 0 )
OR ( tag_count_min = 0 and comment_count_min = 0 and is_active_max = FALSE and is_active_issue_max = TRUE and comment_changed = 0 )
OR ( tag_count_min = 1 and comment_count_min = 1 and is_active_max = FALSE and is_active_issue_max = FALSE and comment_changed = 1 )
OR ( tag_count_min = 1 and comment_count_min = 0 and is_active_max = TRUE and is_active_issue_max = FALSE and comment_changed = 0 )
THEN '0-0'

WHEN ( tag_count_min = 0 and comment_count_min = 1 and is_active_max is  null and is_active_issue_max is  null and comment_changed = 0 )
OR ( tag_count_min = 0 and comment_count_min = 1 and is_active_max = TRUE and is_active_issue_max is  null and comment_changed = 1 and comment_erased = 0)
OR ( tag_count_min = 1 and comment_count_min = 1 and is_active_max = FALSE and is_active_issue_max is  null and comment_changed = 0 )
OR ( tag_count_min = 0 and comment_count_min = 0 and is_active_max = TRUE and is_active_issue_max is  null and comment_changed = 1 )
OR ( tag_count_min = 0 and comment_count_min = 1 and is_active_max = TRUE and is_active_issue_max is  null and comment_changed = 0 )
OR ( tag_count_min = 1 and comment_count_min = 1 and is_active_max is  null and is_active_issue_max = FALSE and comment_changed = 0 )
OR ( tag_count_min = 1 and comment_count_min = 1 and is_active_max = TRUE and is_active_issue_max = FALSE and comment_changed = 0 )
THEN '0-1'

WHEN ( tag_count_min = 1 and comment_count_min = 0 and is_active_max is  null and is_active_issue_max is  null and comment_changed = 0 )
OR ( tag_count_min = 1 and comment_count_min = 0 and is_active_max is  null and is_active_issue_max = TRUE and comment_changed = 0 )
OR ( tag_count_min = 1 and comment_count_min = 0 and is_active_max = TRUE and is_active_issue_max is  null and comment_changed = 0 )
OR ( tag_count_min = 1 and comment_count_min = 1 and is_active_max = TRUE and is_active_issue_max is  null and comment_changed = 1 and comment_erased = 1)
OR ( tag_count_min = 1 and comment_count_min = 1 and is_active_max = TRUE and is_active_issue_max = TRUE and comment_changed = 1 and comment_erased = 1 )
THEN '1-0'

WHEN ( tag_count_min = 1 and comment_count_min = 1 and is_active_max is  null and is_active_issue_max is  null and comment_changed = 0 )
OR ( tag_count_min = 1 and comment_count_min = 1 and is_active_max = TRUE and is_active_issue_max is  null and comment_changed = 1 and comment_erased = 0)
OR ( tag_count_min = 1 and comment_count_min = 1 and is_active_max = TRUE and is_active_issue_max is  null and comment_changed = 0 )
OR ( tag_count_min = 1 and comment_count_min = 0 and is_active_max = TRUE and is_active_issue_max is  null and comment_changed = 1 )
OR ( tag_count_min = 1 and comment_count_min = 1 and is_active_max is  null and is_active_issue_max = TRUE and comment_changed = 0 )
OR ( tag_count_min = 1 and comment_count_min = 1 and is_active_max = TRUE and is_active_issue_max = TRUE and comment_changed = 1 and comment_erased = 0)
OR ( tag_count_min = 1 and comment_count_min = 1 and is_active_max = TRUE and is_active_issue_max = TRUE and comment_changed = 0 )
THEN '1-1'

else 'x-x'
END AS compilated

FROM tags_comments_before_after
WHERE NOT(tag_count_min = 0 and comment_count_min=0 and is_active_max is null and is_active_issue_max is null and comment_changed = 0 )
-- AND NOT (tag_count_min = 1 and comment_count_min=0 and is_active_max is null and is_active_issue_max is null and comment_changed = 0 )
-- AND NOT (tag_count_min = 0 and comment_count_min=1 and is_active_max is null and is_active_issue_max is null and comment_changed = 0 )
-- AND NOT (tag_count_min = 1 and comment_count_min=1 and is_active_max is null and is_active_issue_max is null and comment_changed = 0 )
)

,split_ar as (
SELECT
  sk_contract,
  id_item_group,
  room_name,
  item_group_name,
  item_type_name,
  comment_VT,
  comment_AR,
  issue_type_name,
  issue_comment,
  coalesce(ts_updated_item,ts_updated_issue ) as dt_edition_ar ,


  tag_count_min as tag_count_VT,
  comment_count_min as comment_count_VT,
  comment_changed,
  SPLIT_PART(compilated,'-',1) as tag_count_AR,
  SPLIT_PART(compilated,'-',2) as comment_count_AR

FROM before_after_aux

union all
select distinct

hri.sk_contract,
hri.id_item_group,
hri.room_name,
hri.item_group_name,
lower(pb_status_min.status) as item_type_name,
null as comment_VT,
null as comment_AR,
case when pb_status_min.is_inferior_quality = true then 'is_inferior_quality'
when pb_status_min.is_inferior_quality = false then 'similar_or_better_quality'
else null  end as issue_type_name,
null as issue_comment,
pb_status_max.ts_updated_status as dt_edition_ar,



1 as tag_count_VT,
null as comment_count_VT,
null as comment_changed,

case when pb_status_max.is_active_status = true and pb_status_max.is_active_inferior_quality = true then 1
when pb_status_max.is_active_status = false and pb_status_max.is_active_inferior_quality = true then 0
when pb_status_max.is_active_status = false and pb_status_max.is_active_inferior_quality = false then 0
when pb_status_max.is_active_status is null and pb_status_max.is_active_inferior_quality is null then 1
else 0 end as tag_count_AR,
null as comment_count_AR

from house_room_item hri
left join partition_bt pb_status_min
  on hri.id_item_type_issue = pb_status_min.id_item_type_issue and pb_status_min.un_status_min = 1
left join partition_bt pb_status_max
  on hri.id_item_type_issue = pb_status_max.id_item_type_issue and pb_status_max.un_status_max = 1

where pb_status_min.status is not null and pb_status_min.status != 'SAME'


)
,aux_max_date as (
select distinct

  id_item_group,
  max(dt_edition_ar) as dt_edition_ar

  from split_ar

  group by id_item_group
)

, tags_vt as (
SELECT
  id_item_group,

concat_ws('; ',   array_sort(collect_list(
if(item_type_name = 'other',comment_VT,
if(issue_comment is not null,issue_comment,
if(issue_type_name is not null, issue_type_name ,item_type_name  ))
) ) )) as tag_agg_VT,

  sum(tag_count_VT) as tag_count_VT
FROM split_ar

WHERE tag_count_VT = 1

GROUP BY 1

)

, tags_ar as (
SELECT
  id_item_group,
concat_ws('; ',   array_sort(collect_list(
if(item_type_name = 'other',comment_AR,
if(issue_comment is not null,issue_comment,
if(issue_type_name is not null, issue_type_name ,item_type_name  ))
) ) ))as tag_agg_AR,

  sum(tag_count_AR) as tag_count_AR
FROM split_ar

WHERE tag_count_AR = 1

GROUP BY 1


)

, comment_vt as (
SELECT distinct
  id_item_group,
  comment_VT,
  comment_count_VT

FROM split_ar

WHERE comment_count_VT = 1

)

, comment_ar as (
SELECT distinct
  id_item_group,
  comment_AR,
  comment_changed,
  comment_count_AR

FROM split_ar

WHERE comment_count_AR = 1

)


,

item_group as (

SELECT DISTINCT

      sk_contract,
      sp.id_item_group,
      room_name,
      item_group_name,
      md.dt_edition_ar



      from split_ar sp
      left join aux_max_date md
        on sp.id_item_group = md.id_item_group

)

, final as (
SELECT
ig.sk_contract,
ig.id_item_group,
ig.room_name,
ig.item_group_name,
ig.dt_edition_ar,

tag_agg_VT,
tag_agg_AR,
comment_VT,
comment_AR,
cast(case when tag_count_VT is null then 0 else tag_count_VT end as int) as tag_count_VT,
cast(case when tag_count_AR is null then 0 else tag_count_AR end as int) as tag_count_AR,
cast(case when comment_count_VT is null then 0 else comment_count_VT end as int) as comment_count_VT,
cast(case when comment_count_AR is null then 0 else comment_count_AR end as int) as comment_count_AR,
cast(case when comment_changed is null then 0 else comment_changed end as int) as comment_changed

FROM item_group ig
LEFT JOIN tags_vt tvt
  ON ig.id_item_group = tvt.id_item_group
LEFT JOIN tags_ar tar
  ON tar.id_item_group = ig.id_item_group
LEFT JOIN comment_vt cvt
  ON ig.id_item_group = cvt.id_item_group
LEFT JOIN comment_ar car
  ON ig.id_item_group = car.id_item_group

)

select
sk_contract as sk_contract_tags,
room_name as room_name_tags,
id_item_group as id_item_group_tags,
case
  when tag_count_VT = tag_count_AR then tag_agg_VT
  when tag_agg_AR is null then concat("[",tag_agg_VT,"]-[]")
  else concat("[",tag_agg_VT,"]-[",tag_agg_AR,"]")
end as tags,
case
  when comment_count_VT = comment_count_AR and comment_changed = 0  then comment_VT
  when comment_VT is null  and comment_AR is not null then concat("[]-[",comment_AR,"]")
  when comment_VT is not null and comment_AR is null then concat("[",comment_VT,"]-[]")
  else concat("[",comment_VT,"]-[",comment_AR,"]")
end as comments,


case
when tag_count_VT = 0 and comment_count_VT = 0 and tag_count_AR = 0 and comment_count_AR = 0 and comment_changed = 0 then 'sem tag/comment'
when tag_count_VT > 0 and comment_count_VT = 0 and tag_count_AR = 0 and comment_count_AR = 0 and comment_changed = 0 then 'só tag - tag oculta'
when tag_count_VT > 0 and comment_count_VT = 1 and tag_count_AR = 0 and comment_count_AR = 0 and comment_changed = 0 then 'tag & comentário - tag oculta - comentário apagado'
when tag_count_VT = 0 and comment_count_VT = 1 and tag_count_AR = 0 and comment_count_AR = 0 and comment_changed = 0 then 'só comentário - comentário apagado'

when tag_count_VT > 0 and comment_count_VT = 0 and tag_count_AR = tag_count_VT and comment_count_AR = 0 and comment_changed = 0 then 'só tag'
when tag_count_VT > 1 and comment_count_VT = 0 and tag_count_AR < tag_count_VT  and tag_count_AR > 0 and comment_count_AR = 0 and comment_changed = 0 then 'só tag - tag oculta parcialmente'
when tag_count_VT > 0 and comment_count_VT = 1 and tag_count_AR = tag_count_VT and comment_count_AR = 0 and comment_changed = 0 then 'tag & comentário - comentário apagado'
when tag_count_VT > 0 and comment_count_VT = 1 and tag_count_AR < tag_count_VT  and tag_count_AR > 0 and comment_count_AR = 0 and comment_changed = 0 then 'tag & comentário - comentário apagado - tag oculta parcialmente'

when tag_count_VT = 0 and comment_count_VT = 1 and tag_count_AR = 0 and comment_count_AR = 1 and comment_changed = 0 then 'só comentário'
when tag_count_VT = 0 and comment_count_VT = 1 and tag_count_AR = 0 and comment_count_AR = 1 and comment_changed = 1 then 'só comentário - comentário modificado'
when tag_count_VT > 0 and comment_count_VT = 1 and tag_count_AR = 0 and comment_count_AR = 1 and comment_changed = 0 then 'tag & comentário - tag oculta'
when tag_count_VT > 0 and comment_count_VT = 1 and tag_count_AR = 0 and comment_count_AR = 1 and comment_changed = 1 then 'tag & comentário - tag oculta - comentário modificado'
when tag_count_VT > 0 and comment_count_VT = 0 and tag_count_AR = 0 and comment_count_AR = 1 and comment_changed = 1 then 'só tag - tag oculta + comentário adicionado'
when tag_count_VT = 0 and comment_count_VT = 0 and tag_count_AR = 0 and comment_count_AR = 1 and comment_changed = 1 then 'sem tag/comment - comentário adicionado'

when tag_count_VT > 0 and comment_count_VT = 1 and tag_count_AR = tag_count_VT and comment_count_AR = 1 and comment_changed = 0 then 'tag & comentário'
when tag_count_VT > 0 and comment_count_VT = 1 and tag_count_AR = tag_count_VT and comment_count_AR = 1 and comment_changed = 1 then 'tag & comentário - comentário modificado'
when tag_count_VT > 0 and comment_count_VT = 1 and tag_count_AR < tag_count_VT  and tag_count_AR > 0 and comment_count_AR = 1 and comment_changed = 1 then 'tag & comentário - tag oculta parcialmente - comentário modificado'
when tag_count_VT > 0 and comment_count_VT = 0 and tag_count_AR < tag_count_VT  and tag_count_AR > 0 and comment_count_AR = 1 and comment_changed = 1 then 'só tag -  tag oculta parcialmente - comentário adicionado'
when tag_count_VT > 0 and comment_count_VT = 0 and tag_count_AR = tag_count_VT and comment_count_AR = 1 and comment_changed = 1 then 'só tag - comentário adicionado'
when tag_count_VT > 1 and comment_count_VT = 1 and tag_count_AR < tag_count_VT  and tag_count_AR > 0 and comment_count_AR = 1 and comment_changed = 0 then 'tag & comentário - tag oculta parcialmente'
else 'error'  end as status_tags,
CASE
    WHEN tag_count_AR = 0 AND comment_count_AR = 0 THEN 'sem tag/comment'
    WHEN (tag_count_AR IS NULL OR tag_count_AR = 0) AND (comment_count_AR IS NOT NULL AND comment_count_AR > 0) THEN 'só comentário'
    WHEN (tag_count_AR IS NOT NULL AND tag_count_AR > 0) AND (comment_count_AR IS NULL OR comment_count_AR = 0) THEN 'só tag'
    WHEN (tag_count_AR IS NOT NULL AND tag_count_AR > 0) AND (comment_count_AR IS NOT NULL AND comment_count_AR > 0) THEN 'tag & comentário'
    ELSE 'sem tag/comment'
END AS status_tags_pp,
tag_count_VT,
comment_count_VT,
tag_count_AR as tag_count,
comment_count_AR  as comment_count,
comment_changed,
dt_edition_ar
-- ,item_group_name
from final
)

SELECT
    id_repair_request,
    sk_contract,
    sk_client_side,
    id_item_group,
    room_name,
    name,
    createdBy,
    type,
    dt_created,
    comment,
    grantedBy,
    is_exempted,
    responsibility,
    dt_granted_by,
    reason_iq,
    dt_created_iq,
    comment_iq,
    grantedBy_AC,
    is_exempted_AC,
    responsibility_AC,
    reason_AC,
    dt_granted_by_AC,
    comment_AC,
    cost,
    tags,
    comments,
    CASE WHEN status_tags IS NULL THEN 'sem tag/comment' ELSE  status_tags END AS status_tags,
    CASE WHEN status_tags_pp IS NULL THEN 'sem tag/comment' ELSE  status_tags_pp END AS status_tags_pp,
    comment_count,
    tag_count,
    MAX(AR_email) OVER (PARTITION BY sk_contract) AS AR_email,
    MAX(AC_email) OVER (PARTITION BY sk_contract) AS AC_email,
    high_value_tag,
    "bytag?",
    spoc_contracts,
    "3pml",
    status_AR,
    reviewer_type_iq,
    approval_reason_iq,
    approval_comment_iq,
    is_approved_iq,
    ts_updated_iq,
    reviwer_type_pp,
    approval_reason_pp,
    approval_comment_pp,
    is_approved_pp,
    ts_updated_pp,
    house_total_area,
    repair_service,
    rent,
    risk_category,
    sk_inspection,
    exempted_by_owner_from_ba
FROM
    df_repairs r
LEFT JOIN
    df_tags t ON r.id_item_group = t.id_item_group_tags
WHERE dt_created >= date('2025-01-01')
    --AND sk_contract = 1023950
