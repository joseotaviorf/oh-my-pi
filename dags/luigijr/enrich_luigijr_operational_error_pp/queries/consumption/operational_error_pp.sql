with inspection as
    (
        SELECT
            fi.sk_contract,
            fi.sk_assessment,
            fi.sk_inspection,
            fi.sk_main_inspection,
            fi.sk_inspector,
            fi.ts_synced,
            fi.sk_client_side,
            concat('https://crm-pwa-imoveis.quintoandar.com.br/imoveis/',cast(fi.sk_house as STRING),'/vistorias/',cast(fi.sk_client_side as STRING),
      '/revisar') as link_vistoria,
            CASE WHEN dc.rent >= 2500 THEN 'high_value' ELSE 'low_value' END as high_value_tag,
            dc.rent,
            DATE(da.dt_owner_limit_revision) as sent_to_owner_review_limit_dt,
            di.ai_repair_analysis_control_group,
            di.ai_repair_analysis_wave_name
        FROM dw_inspections.fact_inspection fi
        LEFT JOIN dw_inspections.dim_inspection di ON fi.sk_inspection = di.sk_inspection
        LEFT JOIN dw_rent.dim_contract dc ON dc.sk_contract = fi.sk_contract
        LEFT JOIN dw_inspections.dim_assessment AS da ON da.sk_assessment = fi.sk_assessment

        WHERE fi.ts_synced is not null
            and di.status NOT IN ('cancelled', 'scheduled')
            and di.inspection_type in ('offboarding','verification')
            -- MUDANÇA: Sintaxe do date_add
            and fi.ts_synced >= date_add(current_date(), -360)

    )
, base as
(
    SELECT
        sk_inspection,
        sk_inspector,
        sk_contract,
        id_repair_request,
        is_exempted,
        is_exempted_repair_analysis,
        is_exempted_review_comment,
        is_exempted_automatic_repairs,
        createdBy,
        type,
        name,
        room_name,
        comment,
        grantedBy,
        dt_granted_by,
        responsibility,
        cost,
        dt_created,
        approval_type,
        created_type,
        email_created,
        email_granted,
        link_vistoria,
        id_item_group,
        high_value_tag,
        repair_service,
        rent,
        reason_AC,
        is_exempted_AC,
        AR_email,
        IF(name IN ('Armários','Balcão (Bancada)','Cadeiras','Cama','Cortinas','Espelho','Gabinete','Mesa','Painel de televisão','Persianas','Prateleiras','Rack','Sofá','Pintura','Piso','Porta','Limpeza'), '3pml', 'not 3pml') AS tres_pml
    FROM ( -- Subquery para o SELECT DISTINCT original do CTE 'base'
        SELECT DISTINCT
            i.sk_inspection, i.sk_inspector, i.sk_contract, rr.id_repair_request,
            rr.is_exempted,
            CASE WHEN createdBy.reviewer_type = 'ADMIN' AND (grantedBy.approval_type is null OR grantedBy.approval_type = 'REPAIR_ANALYSIS') THEN rr.is_exempted ELSE NULL END AS is_exempted_repair_analysis,
            CASE WHEN createdBy.reviewer_type = 'OWNER' AND (grantedBy.approval_type is null OR grantedBy.approval_type = 'REVIEW') THEN rr.is_exempted ELSE NULL END AS is_exempted_review_comment,
            CASE WHEN (grantedBy.approval_type IS NULL or grantedby.approval_type = 'REPAIR_ANALYSIS') and createdBy.reviewer_type = 'INSPECTIONS_SERVICE' THEN rr.is_exempted ELSE NULL END AS is_exempted_automatic_repairs,
            createdBy.reviewer_type AS createdBy, rr.type, ig.name, r.room_name, rr.comment,
            grantedBy.reviewer_type AS grantedBy, rr.ts_granted AS dt_granted_by, rr.responsibility,
            rr.cost, rr.ts_created AS dt_created, grantedBy.approval_type, createdBy.approval_type AS created_type,
            duc.email AS email_created, dug.email AS email_granted, i.link_vistoria, rr.id_item_group,
            i.high_value_tag, rr.repair_service, i.rent,
            FIRST_VALUE(CASE WHEN grantedBy.approval_type = 'CONTESTATION_ANALYSIS' THEN type ELSE NULL END) IGNORE NULLS OVER (PARTITION BY id_repair_request ORDER BY rr.ts_granted DESC) as reason_AC,
            FIRST_VALUE(CASE WHEN grantedBy.approval_type = 'CONTESTATION_ANALYSIS' THEN rr.is_exempted ELSE NULL END) IGNORE NULLS OVER (PARTITION BY id_repair_request ORDER BY rr.ts_granted DESC) as is_exempted_AC,
            COALESCE((CASE WHEN createdBy.reviewer_type = 'INSPECTIONS_SERVICE' AND (grantedBy.approval_type is null or grantedBy.approval_type = 'REPAIR_ANALYSIS' ) THEN dug.email END),(CASE WHEN createdBy.reviewer_type = 'ADMIN' AND (grantedBy.approval_type is null OR grantedBy.approval_type = 'REPAIR_ANALYSIS') THEN duc.email END)) as AR_email

        FROM datalake_inspection_services_clean.repair_request AS rr
        LEFT JOIN datalake_inspection_services_clean.reviewer AS createdBy ON createdBy.id_reviewer = rr.id_reviewer
        INNER JOIN datalake_inspection_services_clean.item_group AS ig ON rr.id_item_group = ig.id_item_group
        INNER JOIN datalake_inspection_services_clean.room AS r ON ig.id_room = r.id_room
        INNER JOIN inspection AS i ON i.sk_assessment = r.id_assessment
        LEFT JOIN datalake_inspection_services_clean.reviewer AS grantedBy ON grantedBy.id_reviewer = rr.id_granted_by
        LEFT JOIN dw_public.dim_user AS duc ON duc.sk_user = createdBy.id_user
        LEFT JOIN dw_public.dim_user AS dug ON dug.sk_user = grantedBy.id_user
        WHERE rr.ts_created >= date('2025-01-01') and NOT(createdBy.reviewer_type = 'INSPECTIONS_SERVICE' AND (rr.has_automatic_identification_accepted = FALSE OR rr.has_automatic_identification_accepted IS NULL))
      )
)
-- OTIMIZAÇÃO: Reescrevendo 'review' para evitar self-join na CTE 'base'
, review as
(
    SELECT
        id_repair_request,
        is_exempted,
        grantedBy,
        dt_granted_by,
        responsibility,
        comment,
        type
    FROM (
        SELECT
            b.id_repair_request,
            CASE WHEN is_exempted IS NULL THEN FALSE ELSE is_exempted END AS is_exempted,
            grantedBy,
            b.dt_granted_by,
            responsibility,
            b.comment,
            b.type,
            -- Usamos ROW_NUMBER para pegar apenas a última 'grant' por request
            ROW_NUMBER() OVER(
                PARTITION BY b.id_repair_request
                ORDER BY b.dt_granted_by DESC
            ) as rn
        FROM base b -- Apenas UMA referência a 'base'
        WHERE b.approval_type = 'REVIEW'
          and (b.createdBy = 'ADMIN' OR b.createdBy = 'INSPECTIONS_SERVICE')
    )
    -- Filtramos apenas a mais recente (rn = 1), que é o
    -- equivalente ao MAX(dt_granted_by) + JOIN da query original
    WHERE rn = 1
),
class_status as (
    SELECT
        all.sk_contract,
        all.sk_inspection,
        all.id_item_group,
        all.name,
        all.room_name,
        r.grantedBy,
        all.createdBy,
        CASE WHEN coalesce(r.is_exempted,is_exempted_repair_analysis,is_exempted_review_comment,is_exempted_automatic_repairs) IS NULL THEN FALSE ELSE coalesce(r.is_exempted,is_exempted_repair_analysis,is_exempted_review_comment,is_exempted_automatic_repairs) END as is_exempted,

        CASE WHEN all.createdby = 'ADMIN' AND r.grantedby = 'OWNER'
              and (CASE WHEN coalesce(r.is_exempted,is_exempted_repair_analysis,is_exempted_review_comment,is_exempted_automatic_repairs)IS NULL THEN FALSE ELSE coalesce(r.is_exempted,is_exempted_repair_analysis,is_exempted_review_comment,is_exempted_automatic_repairs) END) = true
                THEN 'AR cobrou - PP isentou'
              WHEN all.createdby = 'ADMIN' AND r.grantedby = 'OWNER' and (CASE WHEN coalesce(r.is_exempted,is_exempted_repair_analysis,is_exempted_review_comment,is_exempted_automatic_repairs) IS NULL THEN FALSE ELSE coalesce(r.is_exempted,is_exempted_repair_analysis,is_exempted_review_comment,is_exempted_automatic_repairs) END) = false THEN 'AR cobrou - PP cobrou'
              WHEN all.createdby = 'ADMIN' AND (r.grantedby IS NULL or r.grantedby = 'ADMIN')  and  (CASE WHEN coalesce(r.is_exempted,is_exempted_repair_analysis,is_exempted_review_comment,is_exempted_automatic_repairs) IS NULL THEN FALSE ELSE coalesce(r.is_exempted,is_exempted_repair_analysis,is_exempted_review_comment,is_exempted_automatic_repairs) END) = false THEN 'AR cobrou - PP não interagiu'
              WHEN (all.createdby = 'ADMIN' or all.createdby = 'INSPECTIONS_SERVICE') AND r.grantedby IS NULL and (CASE WHEN coalesce(r.is_exempted,is_exempted_repair_analysis,is_exempted_review_comment,is_exempted_automatic_repairs)IS NULL THEN FALSE ELSE coalesce(r.is_exempted,is_exempted_repair_analysis,is_exempted_review_comment,is_exempted_automatic_repairs) END) = true THEN 'AR isentou'
              WHEN all.createdby = 'INSPECTIONS_SERVICE' AND r.grantedby = 'OWNER' and (CASE WHEN coalesce(r.is_exempted,is_exempted_repair_analysis,is_exempted_review_comment,is_exempted_automatic_repairs)IS NULL THEN FALSE ELSE coalesce(r.is_exempted,is_exempted_repair_analysis,is_exempted_review_comment,is_exempted_automatic_repairs) END) = true THEN 'Reparo automático - PP isentou'
              WHEN all.createdby = 'INSPECTIONS_SERVICE' AND r.grantedby = 'OWNER' and (CASE WHEN coalesce(r.is_exempted,is_exempted_repair_analysis,is_exempted_review_comment,is_exempted_automatic_repairs) IS NULL THEN FALSE ELSE coalesce(r.is_exempted,is_exempted_repair_analysis,is_exempted_review_comment,is_exempted_automatic_repairs) END)= false THEN 'Reparo automático - PP cobrou'
              WHEN all.createdby = 'INSPECTIONS_SERVICE' AND (r.grantedby IS NULL or r.grantedby = 'ADMIN') and (CASE WHEN coalesce(r.is_exempted,is_exempted_repair_analysis,is_exempted_review_comment,is_exempted_automatic_repairs) IS NULL THEN FALSE ELSE coalesce(r.is_exempted,is_exempted_repair_analysis,is_exempted_review_comment,is_exempted_automatic_repairs) END) = false THEN 'Reparo automático - PP não interagiu' END AS status_ar
        FROM base as all
        LEFT JOIN review r ON all.id_repair_request = r.id_repair_request
) ,
 status as (
    SELECT
        sk_contract,
        sk_inspection,
        id_item_group,
        name,
        room_name,
        SUM(CASE WHEN status_AR = 'AR cobrou - PP isentou' THEN 1 ELSE 0 END) AS AR_cobrou_PP_isentou,
        SUM(CASE WHEN status_AR = 'AR cobrou - PP cobrou' THEN 1 ELSE 0 END) AS AR_cobrou_PP_cobrou,
        SUM(CASE WHEN status_AR = 'AR cobrou - PP não interagiu' THEN 1 ELSE 0 END) AS AR_cobrou_PP_nao_interagiu,
        SUM(CASE WHEN status_AR = 'AR isentou' THEN 1 ELSE 0 END) AS AR_isentou,
        CASE WHEN SUM(CASE WHEN status_AR = 'AR cobrou - PP isentou' THEN 1 ELSE 0 END) > 0 THEN 'AR cobrou - PP isentou'
              WHEN SUM(CASE WHEN status_AR = 'AR cobrou - PP cobrou' THEN 1 ELSE 0 END) > 0 THEN 'AR cobrou - PP cobrou'
              WHEN SUM(CASE WHEN status_AR = 'AR cobrou - PP não interagiu' THEN 1 ELSE 0 END) > 0 THEN 'AR cobrou - PP não interagiu'
              WHEN SUM(CASE WHEN status_AR = 'AR isentou' THEN 1 ELSE 0 END) > 0 THEN 'AR isentou'
              WHEN SUM(CASE WHEN status_AR = 'Reparo automático - PP isentou' THEN 1 ELSE 0 END) > 0 THEN 'Reparo automático - PP isentou'
              WHEN SUM(CASE WHEN status_AR = 'Reparo automático - PP cobrou' THEN 1 ELSE 0 END) > 0 THEN 'Reparo automático - PP cobrou'
              WHEN SUM(CASE WHEN status_AR = 'Reparo automático - PP não interagiu' THEN 1 ELSE 0 END) > 0 THEN 'Reparo automático - PP não interagiu'
              ELSE 'AR não comentou' end as status
    FROM class_status
    GROUP BY 1,2,3,4,5
),
exempted_by_owner_from_BA AS (
    SELECT DISTINCT f.id_item_group
    FROM base AS f
    LEFT JOIN dw_inspections.fact_repair_request AS frr ON f.id_item_group = frr.sk_item_group
    WHERE frr.is_exempted_by_owner_from_budget = TRUE
    AND frr.ts_created >= date('2025-01-01')
),
spoc_contracts AS (
    SELECT DISTINCT sk_contract
    FROM dw_offboarding.fact_terminations
    WHERE is_spoc_contract = TRUE
    AND ts_termination_request >= date('2025-01-01')
),
-- CTE 2: 'base_tags' - Simplificada para conter apenas colunas necessárias
 base_tags as (
    SELECT
        i.sk_contract,
        concat( cast(i2.id_item as STRING),"-",cast(it.id_item_type as STRING), if(id_item_issue is null,"",concat("-",cast(id_item_issue as STRING)) )) as id_item_type_issue ,
        ig.id_item_group,
        it.type item_type_name,
        iit.type issue_type_name,
        ig.status,
        ig.is_inferior_quality,
        i2.comment,
        is_present,
        i2.is_active ,
        ii.is_active as is_active_issue,
        ig.is_active_status,
        ig.is_active_inferior_quality,
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
-- CTE 3: 'partition_bt' - Inalterada, pois é a base dos cálculos
, partition_bt as (
    SELECT
        sk_contract,
        id_item_type_issue,
        id_item_group,
        item_type_name,
        issue_type_name,
        status,
        is_inferior_quality,
        comment,
        is_present,
        is_active,
        is_active_issue,
        is_active_status,
        is_active_inferior_quality,
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
-- CTE 4: 'house_room_item' - Simplificada
, house_room_item as (
    SELECT DISTINCT
        sk_contract,
        id_item_type_issue ,
        id_item_group,
        is_present
    FROM base_tags
)
-- CTE 5: 'tags_comments_before_after' - Simplificada
, tags_comments_before_after as (
    select
        hri.sk_contract,
        hri.id_item_group,
        hri.id_item_type_issue,
        hri.is_present,
        pb_item_max.is_active as is_active_max,
        pb_issue_max.is_active_issue as is_active_issue_max,
        case when
            (pb_item_min.item_type_name is not null and hri.is_present = True and pb_item_min.item_type_name !='overview')
            or (pb_issue_min.issue_type_name is not null and pb_issue_min.issue_type_name!='working')
        then 1 else 0
        end as tag_count_min,
        case when pb_item_min.comment is not null and pb_item_min.comment != "" and
            pb_item_min.item_type_name !='other' then 1 else 0
        end as comment_count_min,

        case
            when pb_item_min.comment is not null and pb_item_max.comment is not null then
                if(pb_item_min.comment != pb_item_max.comment,1,0)
            when pb_item_min.comment is null and pb_item_max.comment is null then 0
            when pb_item_min.comment is null and pb_item_max.comment is not null then
                if(pb_item_max.comment != "" ,1,0)
            when pb_item_min.comment is not null and pb_item_max.comment is null then
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
-- CTE 6: 'before_after_aux' - Simplificada para passar menos colunas
, before_after_aux as (
    select
        sk_contract,
        id_item_group,
        tag_count_min,
        comment_count_min,
        comment_changed,
        CASE
            WHEN ( tag_count_min = 1 and comment_count_min = 0 and is_active_max = FALSE and is_active_issue_max = FALSE and comment_changed = 0 )
            OR ( tag_count_min = 0 and comment_count_min = 0 and is_active_max is null and is_active_issue_max = TRUE and comment_changed = 0 )
            OR ( tag_count_min = 0 and comment_count_min = 1 and is_active_max = TRUE and is_active_issue_max is null and comment_changed = 1 and comment_erased = 1)
            OR ( tag_count_min = 1 and comment_count_min = 0 and is_active_max = FALSE and is_active_issue_max is null and comment_changed = 0 )
            OR ( tag_count_min = 0 and comment_count_min = 0 and is_active_max = FALSE and is_active_issue_max is null and comment_changed = 0 )
            OR ( tag_count_min = 1 and comment_count_min = 0 and is_active_max is null and is_active_issue_max = FALSE and comment_changed = 0 )
            OR ( tag_count_min = 1 and comment_count_min = 1 and is_active_max = TRUE and is_active_issue_max = FALSE and comment_changed = 1 )
            OR ( tag_count_min = 0 and comment_count_min = 0 and is_active_max = TRUE and is_active_issue_max is null and comment_changed = 0 )
            OR ( tag_count_min = 0 and comment_count_min = 0 and is_active_max = FALSE and is_active_issue_max = FALSE and comment_changed = 0 )
            OR ( tag_count_min = 1 and comment_count_min = 0 and is_active_max = FALSE and is_active_issue_max = TRUE and comment_changed = 0 )
            OR ( tag_count_min = 0 and comment_count_min = 0 and is_active_max = FALSE and is_active_issue_max = TRUE and comment_changed = 0 )
            OR ( tag_count_min = 1 and comment_count_min = 1 and is_active_max = FALSE and is_active_issue_max = FALSE and comment_changed = 1 )
            OR ( tag_count_min = 1 and comment_count_min = 0 and is_active_max = TRUE and is_active_issue_max = FALSE and comment_changed = 0 )
            THEN '0-0'
            WHEN ( tag_count_min = 0 and comment_count_min = 1 and is_active_max is null and is_active_issue_max is null and comment_changed = 0 )
            OR ( tag_count_min = 0 and comment_count_min = 1 and is_active_max = TRUE and is_active_issue_max is null and comment_changed = 1 and comment_erased = 0)
            OR ( tag_count_min = 1 and comment_count_min = 1 and is_active_max = FALSE and is_active_issue_max is null and comment_changed = 0 )
            OR ( tag_count_min = 0 and comment_count_min = 0 and is_active_max = TRUE and is_active_issue_max is null and comment_changed = 1 )
            OR ( tag_count_min = 0 and comment_count_min = 1 and is_active_max = TRUE and is_active_issue_max is null and comment_changed = 0 )
            OR ( tag_count_min = 1 and comment_count_min = 1 and is_active_max is null and is_active_issue_max = FALSE and comment_changed = 0 )
            OR ( tag_count_min = 1 and comment_count_min = 1 and is_active_max = TRUE and is_active_issue_max = FALSE and comment_changed = 0 )
            THEN '0-1'
            WHEN ( tag_count_min = 1 and comment_count_min = 0 and is_active_max is null and is_active_issue_max is null and comment_changed = 0 )
            OR ( tag_count_min = 1 and comment_count_min = 0 and is_active_max is null and is_active_issue_max = TRUE and comment_changed = 0 )
            OR ( tag_count_min = 1 and comment_count_min = 0 and is_active_max = TRUE and is_active_issue_max is null and comment_changed = 0 )
            OR ( tag_count_min = 1 and comment_count_min = 1 and is_active_max = TRUE and is_active_issue_max is null and comment_changed = 1 and comment_erased = 1)
            OR ( tag_count_min = 1 and comment_count_min = 1 and is_active_max = TRUE and is_active_issue_max = TRUE and comment_changed = 1 and comment_erased = 1 )
            THEN '1-0'
            WHEN ( tag_count_min = 1 and comment_count_min = 1 and is_active_max is null and is_active_issue_max is null and comment_changed = 0 )
            OR ( tag_count_min = 1 and comment_count_min = 1 and is_active_max = TRUE and is_active_issue_max is null and comment_changed = 1 and comment_erased = 0)
            OR ( tag_count_min = 1 and comment_count_min = 1 and is_active_max = TRUE and is_active_issue_max is null and comment_changed = 0 )
            OR ( tag_count_min = 1 and comment_count_min = 0 and is_active_max = TRUE and is_active_issue_max is null and comment_changed = 1 )
            OR ( tag_count_min = 1 and comment_count_min = 1 and is_active_max is null and is_active_issue_max = TRUE and comment_changed = 0 )
            OR ( tag_count_min = 1 and comment_count_min = 1 and is_active_max = TRUE and is_active_issue_max = TRUE and comment_changed = 1 and comment_erased = 0)
            OR ( tag_count_min = 1 and comment_count_min = 1 and is_active_max = TRUE and is_active_issue_max = TRUE and comment_changed = 0 )
            THEN '1-1'
            else 'x-x'
        END AS compilated
    FROM tags_comments_before_after
    WHERE NOT(tag_count_min = 0 and comment_count_min=0 and is_active_max is null and is_active_issue_max is null and comment_changed = 0 )
)
-- CTE 7: 'split_ar' - Simplificada e com sintaxe SparkSQL
, split_ar as (
    SELECT
        sk_contract,
        id_item_group,
        tag_count_min as tag_count_VT,
        comment_count_min as comment_count_VT,
        comment_changed,
        -- MUDANÇA: Sintaxe de SPLIT_PART (Trino) para split() (SparkSQL)
        CAST(split(compilated,'-')[0] as INT) as tag_count_AR,
        CAST(split(compilated,'-')[1] as INT) as comment_count_AR
    FROM before_after_aux
    union all

    select distinct
        hri.sk_contract,
        hri.id_item_group,
        1 as tag_count_VT,
        null as comment_count_VT,
        null as comment_changed,
        case
            when pb_status_max.is_active_status = true and pb_status_max.is_active_inferior_quality = true then 1
            when pb_status_max.is_active_status = false and pb_status_max.is_active_inferior_quality = true then 0
            when pb_status_max.is_active_status = false and pb_status_max.is_active_inferior_quality = false then 0
            when pb_status_max.is_active_status is null and pb_status_max.is_active_inferior_quality is null then 1
            else 0
        end as tag_count_AR,
        null as comment_count_AR
    from house_room_item hri
    left join partition_bt pb_status_min
        on hri.id_item_type_issue = pb_status_min.id_item_type_issue and pb_status_min.un_status_min = 1
    left join partition_bt pb_status_max
        on hri.id_item_type_issue = pb_status_max.id_item_type_issue and pb_status_max.un_status_max = 1
    where pb_status_min.status is not null and pb_status_min.status != 'SAME'
)
-- CTE 8: 'final_counts' - NOVA CTE que substitui 5 CTEs (tags_vt, tags_ar, comment_vt, comment_ar, item_group, final)
, final_counts as (
    SELECT
        sk_contract,
        id_item_group,
        COALESCE(SUM(tag_count_VT), 0) AS tag_count_VT,
        COALESCE(SUM(tag_count_AR), 0) AS tag_count_AR,
        COALESCE(MAX(comment_count_VT), 0) AS comment_count_VT,
        COALESCE(MAX(comment_count_AR), 0) AS comment_count_AR,
        COALESCE(MAX(comment_changed), 0) AS comment_changed
    FROM split_ar
    GROUP BY
        sk_contract,
        id_item_group
),
final_tags as (
select
    sk_contract,
    id_item_group,
    -- Lógica para 'status_tags_pp' (inalterada)
    CASE
        WHEN tag_count_AR = 0 AND comment_count_AR = 0 THEN 'sem tag/comment'
        WHEN (tag_count_AR IS NULL OR tag_count_AR = 0) AND (comment_count_AR IS NOT NULL AND comment_count_AR > 0) THEN 'só comentário'
        WHEN (tag_count_AR IS NOT NULL AND tag_count_AR > 0) AND (comment_count_AR IS NULL OR comment_count_AR = 0) THEN 'só tag'
        WHEN (tag_count_AR IS NOT NULL AND tag_count_AR > 0) AND (comment_count_AR IS NOT NULL AND comment_count_AR > 0) THEN 'tag & comentário'
        ELSE 'sem tag/comment'
    END AS status_tags_pp,
    -- Lógica para 'status_tags' (inalterada)
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
        else 'error'
    end as status_tags
from final_counts
),
ar_final as (
-- OTIMIZAÇÃO: Removido 'DISTINCT' redundante, pois 'GROUP BY' já garante a unicidade
SELECT
    base.sk_contract,  --1
    base.id_item_group, --2
    base.room_name, -- 3
    base.name, --4
    tres_pml, --5
    base.high_value_tag, --6
    CASE WHEN ba.id_item_group IS NOT NULL THEN TRUE ELSE FALSE END AS exempted_by_owner_from_ba, --7
    CASE WHEN spc.sk_contract IS NOT NULL THEN TRUE ELSE FALSE END AS spoc_contracts,  --8
    status, -- 9
    COALESCE(t.status_tags_pp, 'sem tag/comment') AS status_tags_pp, --10
    COALESCE(t.status_tags, 'sem tag/comment') as status_tags, --11
    CASE WHEN  COALESCE(t.status_tags_pp, 'sem tag/comment') != COALESCE(t.status_tags, 'sem tag/comment') THEN 1 ELSE 0 END as edicao , --12,
    concat_ws(',', collect_set(CASE WHEN is_exempted_AC = TRUE THEN reason_AC END)) AS reason_AC_indevido, --13
    concat_ws(',', collect_set(CASE WHEN is_exempted_AC = FALSE THEN reason_AC END)) AS reason_AC_devido,  --14

    COUNT(CASE WHEN is_exempted_AC = TRUE THEN 1 END) AS pp_comentario_indevido, --15
    COUNT(CASE WHEN is_exempted_AC = FALSE THEN 1 END) AS pp_comentario_devido --16

FROM base
LEFT JOIN exempted_by_owner_from_BA AS ba ON base.id_item_group = ba.id_item_group
LEFT JOIN spoc_contracts AS spc ON base.sk_contract = spc.sk_contract
LEFT JOIN status as s on s.id_item_group = base.id_item_group
LEFT JOIN final_tags t ON t.id_item_group = base.id_item_group
WHERE base.createdby = 'OWNER'
--and base.sk_contract = 728467
GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12
),
erro_operacional as (
SELECT
    ar_final.sk_contract,
    ar_final.id_item_group,
    ar_final.room_name,
    ar_final.name,
    ar_final.tres_pml,
    ar_final.high_value_tag,
    ar_final.exempted_by_owner_from_ba,
    ar_final.spoc_contracts,
    ar_final.status,
    ar_final.status_tags_pp,
    ar_final.status_tags,
    ar_final.edicao,
    ar_final.reason_AC_indevido,
    ar_final.reason_AC_devido,
    ar_final.pp_comentario_indevido,
    ar_final.pp_comentario_devido,
   SUM(CASE WHEN status_tags_pp != 'sem tag/comment' and high_value_tag = 'low_value'
             AND tres_pml = '3pml' and status = 'AR não comentou' and exempted_by_owner_from_ba = FALSE and reason_AC_devido not like '%REPAIR_ANALYSIS_NOTE_BUDGETING%'
             AND spoc_contracts = FALSE THEN 1 ---- Erro 01

             WHEN status_tags_pp != 'sem tag/comment' and status = 'AR isentou' and pp_comentario_devido > 0  and exempted_by_owner_from_ba = FALSE
             AND reason_AC_devido not like '%REPAIR_ANALYSIS_NOTE_BUDGETING%'AND spoc_contracts = FALSE THEN 1 ---- Erro 02

             WHEN status_tags_pp != 'sem tag/comment' and status = 'AR cobrou - PP não interagiu' and pp_comentario_devido > 0
             AND exempted_by_owner_from_ba = FALSE and reason_AC_devido not like '%REPAIR_ANALYSIS_NOTE_BUDGETING%'AND spoc_contracts = FALSE THEN 1 ---- Erro 03

             WHEN status_tags_pp != 'sem tag/comment' and status = 'AR cobrou - PP cobrou' and pp_comentario_devido > 0
             AND exempted_by_owner_from_ba = FALSE and reason_AC_devido not like '%REPAIR_ANALYSIS_NOTE_BUDGETING%'AND spoc_contracts = FALSE THEN 1 ---- Erro 04

             WHEN status_tags_pp != 'sem tag/comment' and status = 'AR cobrou - PP isentou' and pp_comentario_devido > 0
             AND exempted_by_owner_from_ba = FALSE and reason_AC_devido not like '%REPAIR_ANALYSIS_NOTE_BUDGETING%'AND spoc_contracts = FALSE THEN 1 ---- Erro 05
             END) erro_operacional_pp
FROM ar_final
         GROUP BY
    ar_final.sk_contract,
    ar_final.id_item_group,
    ar_final.room_name,
    ar_final.name,
    ar_final.tres_pml,
    ar_final.high_value_tag,
    ar_final.exempted_by_owner_from_ba,
    ar_final.spoc_contracts,
    ar_final.status,
    ar_final.status_tags_pp,
    ar_final.status_tags,
    ar_final.edicao,
    ar_final.reason_AC_indevido,
    ar_final.reason_AC_devido,
    ar_final.pp_comentario_indevido,
    ar_final.pp_comentario_devido
),
analise_1 AS (
SELECT
    ft.sk_contract,
    ft.sk_ticket,
    da.email,
    to_date(dt.ts_created_brt) as created_date,
    to_date(ft.ts_solved) as solved_date,
    CASE WHEN dt.tags like '%sheets_serviços_zendesk_an1%' THEN TRUE ELSE FALSE END as check_tkt_an1,
    dt.subject
FROM dw_customer_support.fact_tickets ft
LEFT JOIN dw_customer_support.dim_ticket dt
    ON ft.sk_ticket = dt.sk_ticket
LEFT JOIN dw_customer_support.dim_zendesk_user du
    ON ft.sk_zendesk_assignee_user = du.sk_zendesk_user
LEFT JOIN dw_customer_support.dim_analyst da on da.full_name = du.name

WHERE dt.group_name in ('Análise de reparos [OFF] [POS] [BACK] ')
    AND dt.status not in ('deleted')
    AND dt.tags not like '%closed_by_merge%'
    AND dt.tags not like '%fechamento_em_massa_19102023%'
    AND (to_date(dt.ts_created_brt) >= DATE '2024-01-01' OR to_date(ft.ts_solved) >= DATE '2024-01-06')
    AND CAST(ft.sk_ticket as STRING) not in ('67559749','67559785','67559036','67315629','67632524','67578670','67613882','67562139','67577586','67619607','67558654','67549115','67558995','67562220','67558702','67580136','67550673',
                                            '67549581','67551316','67547746','67550817','67548006','67559280','67549806','67558037','67558304','67632030','67318645','67619528','67549211','67318289','67557940','67551383','67558242') -- tickets na caixa errada
UNION ALL
SELECT CAST(c.id_contract AS INTEGER),
c.case_number,
u.email,
date(c.ts_created) as created_date,
date(c.ts_closed) as solved_date,
FALSE as check_tkt_an1, -- não se aplica
c.case_subject
FROM datalake_salesforce_clean.cases AS c
  INNER JOIN datalake_salesforce_clean.record_types AS rt
      ON rt.id_record_type = c.id_record_type AND rt.record_type_name IN ('Análise de Reparos')
  LEFT JOIN datalake_salesforce_clean.users AS u
      ON u.id_user_salesforce = c.id_owner
  WHERE c.is_deleted = FALSE
    AND c.ts_created >= DATE('2026-04-23')
    AND c.case_status NOT IN ('CANCELED')
    AND u.email IS NOT NULL),
analise_tsk_aux AS (
    SELECT
        fit.sk_contract,
        fit.sk_task,
        MAX(dit.ts_start - INTERVAL 3 HOURS) AS start_tsk_dt,
        MAX(dit.ts_completed - INTERVAL 3 HOURS) AS completed_tsk_dt
    FROM dw_crm.fact_inspection_tasks fit
    LEFT JOIN dw_crm.dim_inspection_task dit
        ON fit.sk_task = dit.sk_task AND fit.sk_contract > 0
    WHERE dit.titles IN ('[Qualidade de Vistoria - Offboarding]', '[Agendamento de Vistoria de Saída]')
    GROUP BY 1, 2
),
analise_tsk AS (
    SELECT
        sk_contract,
        sk_task,
        start_tsk_dt,
        completed_tsk_dt,
        ww_comm1.dt_end_1 AS max_comm1_an2,
        ww_fin_comm.dt_end_3 AS max_fin_comm_an2,
        ww_fin_tsk.dt_end_4 AS max_fin_tsk_an2,
        row_number() OVER (PARTITION BY sk_contract ORDER BY start_tsk_dt DESC) AS rk
    FROM analise_tsk_aux
    LEFT JOIN datalake_date.workday_window ww_fin_tsk
        ON to_date(start_tsk_dt) = ww_fin_tsk.dt_ref AND ww_fin_tsk.id_city = 39
    LEFT JOIN datalake_date.workday_window ww_comm1
        ON to_date(start_tsk_dt) = ww_comm1.dt_ref AND ww_comm1.id_city = 39
    LEFT JOIN datalake_date.workday_window ww_fin_comm
        ON to_date(start_tsk_dt) = ww_fin_comm.dt_ref AND ww_fin_comm.id_city = 39
),
comm_public AS (
    SELECT
        sk_ticket,
        (ts_event - INTERVAL 3 HOURS) AS first_reply_date,
        row_number() OVER (PARTITION BY sk_ticket ORDER BY ts_event ASC) AS rk
    FROM dw_customer_support.fact_ticket_events
    WHERE is_public = TRUE
),
analise_2 AS (
    SELECT
        tsk.sk_contract,
        to_date(tsk.start_tsk_dt) AS start_tsk_dt,
        ft.sk_ticket,
        dt.ts_created_brt,
        reply_time_min_business,
        CASE
            WHEN CAST(get_json_object(dt.custom_fields, '$."Conclusão na Análise de Contestação"') AS STRING) LIKE '%intermediação%' THEN 'Intermediação'
            WHEN CAST(get_json_object(dt.custom_fields, '$."Conclusão na Análise de Contestação"') AS STRING) LIKE '%específicos%' THEN 'Reparos especifícos'
            ELSE CAST(get_json_object(dt.custom_fields, '$."Conclusão na Análise de Contestação"') AS STRING)
        END AS resolution_notation,
        CASE
            WHEN to_date(cp.first_reply_date) <= DATE '2023-11-20' THEN to_date(cp.first_reply_date)
            WHEN to_date(ft.ts_solved) > DATE '2023-11-20' THEN to_date(ft.ts_solved)
            ELSE NULL
        END AS first_reply,
        to_date(ft.ts_solved) AS solved_date,
        CASE WHEN dt.tags LIKE '%sheets_serviços_zendesk_an1%' THEN TRUE ELSE FALSE END AS check_tkt_an1,
        dt.subject,
        max_comm1_an2,
        max_fin_comm_an2,
        max_fin_tsk_an2,
          COALESCE(
            CAST(get_json_object(dt.custom_fields, '$.Tipo de Cliente [PRE-SAIDA]') AS VARCHAR(255)),
            CAST(get_json_object(dt.custom_fields, '$.Tipo de Cliente') AS VARCHAR(255))
        ) AS client_type,
        da.email,
        tsk.sk_task,
        row_number() OVER (PARTITION BY ft.sk_contract ORDER BY dt.ts_created_brt DESC) AS rk
    FROM analise_tsk tsk
    LEFT JOIN dw_customer_support.fact_tickets ft
        ON tsk.sk_contract = ft.sk_contract
    LEFT JOIN dw_customer_support.dim_ticket dt
        ON ft.sk_ticket = dt.sk_ticket
    LEFT JOIN comm_public cp
        ON cp.sk_ticket = ft.sk_ticket AND cp.rk = 1
    LEFT JOIN dw_customer_support.dim_zendesk_user du
        ON ft.sk_zendesk_assignee_user = du.sk_zendesk_user
    LEFT JOIN dw_customer_support.dim_analyst da on da.full_name = du.name
    WHERE dt.group_name IN ('Análise de Vistorias II - Reativa [SO] ')
   AND COALESCE(
            CAST(get_json_object(dt.custom_fields, '$.Tipo de Cliente [PRE-SAIDA]') AS VARCHAR(255)),
            CAST(get_json_object(dt.custom_fields, '$.Tipo de Cliente') AS VARCHAR(255))
        ) LIKE '%proprietário%'
        AND dt.tags LIKE '%ticket_ativo%'
        AND tsk.rk = 1
        AND du.email IS NOT NULL
UNION ALL
SELECT CAST(c.id_contract AS INTEGER),
date(c.ts_created) as created_date,
c.case_number,
(date(c.ts_created) - INTERVAL 3 HOURS) AS created_date_brt,
0 AS reply_time_min_business, -- não se aplica
null as resolution_notation, -- não de aplica
null as first_reply, -- não de aplica
date(c.ts_closed) as solved_date,
FALSE as check_tkt_an1, -- não se aplica
c.case_subject,
null as max_comm1_an2,  -- não se aplica
null as max_fin_comm_an2,  -- não se aplica
null as max_fin_tsk_an2,  -- não se aplica
null as client_type, -- não se aplica
u.email,
null AS id_task, -- não se aplica
1 as rk -- não se aplica
FROM datalake_salesforce_clean.cases AS c
  INNER JOIN datalake_salesforce_clean.record_types AS rt
      ON rt.id_record_type = c.id_record_type AND rt.record_type_name IN ('Análise de Contestação')
  LEFT JOIN datalake_salesforce_clean.users AS u
      ON u.id_user_salesforce = c.id_owner
  WHERE c.is_deleted = FALSE
    AND c.ts_created >= DATE('2026-04-23')
    AND c.case_status NOT IN ('CANCELED')
    AND u.email IS NOT NULL
),
amplitude_events_cte AS (
    SELECT
        ib.id_inspection,
        MAX(CASE WHEN get_json_object(ird.event_properties, '$.user_type') = 'Proprietario' THEN 1 END) AS pp_open,
        MIN(CASE WHEN get_json_object(ird.event_properties, '$.user_type') = 'Proprietario' THEN ird.ts_event END) AS pp_open_dt,
        MAX(CASE WHEN get_json_object(ird.event_properties, '$.user_type') = 'Inquilino' THEN 1 END) AS iq_open,
        MIN(CASE WHEN get_json_object(ird.event_properties, '$.user_type') = 'Inquilino' THEN ird.ts_event END) AS iq_open_dt
    FROM datalake_amplitude_clean.170698_inspection_review_home_page_viewed_events AS ird
    JOIN datalake_inspections.inspection_booking AS ib ON ib.id_client_side = get_json_object(ird.event_properties, '$.inspection_id')
    WHERE
        ird.year >= 2025
        AND get_json_object(ird.event_properties, '$.user_type') IN ('Proprietario', 'Inquilino')
        AND ib.inspection_type = 'offboarding'
    GROUP BY 1
),
tfs as (
SELECT sk_contract, date(ts_termination_finished) as dt_tf FROM dw_offboarding.fact_terminations
WHERE ts_termination_finished is not null
)
SELECT
    solved_date as dt_ac,
    date(dt_tf) as dt_tf,
    coalesce(solved_date, date(dt_tf)) as dt_ancoragem,
    i.sk_inspection,
    a.sk_contract,
    CASE WHEN DATE(amp.pp_open_dt) <= DATE(f.sent_to_owner_review_limit_dt) THEN amp.pp_open END AS pp_open,
    pp_open_dt,
    CASE WHEN i.ai_repair_analysis_control_group = FALSE and i.ai_repair_analysis_wave_name != '' THEN 1 ELSE 0 END AS valida_robo,
    SUM(eo.erro_operacional_pp) as erro_operacional_pp,
    max(edicao) as edicao
FROM analise_2 as a
LEFT JOIN inspection as i on i.sk_contract = a.sk_contract
LEFT JOIN tfs as t on t.sk_contract = a.sk_contract
LEFT JOIN erro_operacional as eo on eo.sk_contract = a.sk_contract
LEFT JOIN amplitude_events_cte AS amp ON amp.id_inspection = CAST(i.sk_inspection AS STRING)
LEFT JOIN inspection as f ON f.sk_inspection = i.sk_inspection
GROUP BY 1,2,3,4,5,6,7,8
