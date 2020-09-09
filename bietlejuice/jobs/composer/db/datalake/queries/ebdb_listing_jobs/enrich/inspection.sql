with
    comments as (
        select
            id_inspection,
            max(comment is not null) as has_inspector_comment,
            max(tenant_comment is not null) as has_tenant_comment,
            max(owner_comment is not null) as has_owner_comment
        from
             datalake_ebdb_clean.inspection_item
        group by
            id_inspection
    )
select
    v.id,
    v.id_house,
    v.id_user_inspector,
    v.id_contract,
    v.id_booking,
    v.id_ref,
    v.id_final_report_pdf,
    v.status,
    v.comment,
    v.hash,
    v.browser_tenant_approval,
    v.browser_owner_approval,
    v.tenant_comment,
    v.owner_comment,
    v.ip_tenant_approval,
    v.ip_owner_approval,
    v.os_tenant_approval,
    v.os_owner_approval,
    v.type,
    v.short_review_tenant,
    v.short_review_owner,
    v.last_report_sent,
    v.key_location,
    v.key_location_details,
    v.version,
    v.schedule_observations,
    v.report_revised,
    v.is_tenant_approved,
    v.is_owner_approved,
    v.is_schedule_double_checked,
    v.is_report_finished,
    v.is_item_commented,
    v.is_final_report_created,
    coalesce(c.has_inspector_comment, false) as has_inspector_comment,
    coalesce(c.has_tenant_comment, false) as has_tenant_comment,
    coalesce(c.has_owner_comment, false) as has_owner_comment,
    v.has_inspector_got_all_info,
    v.dt_final_report_sent,
    v.dt_inspected,
    v.ts_tenant_approved,
    v.ts_owner_approved,
    v.ts_partial_tenant_report_sent,
    v.ts_partial_owner_report_sent,
    v.ts_expired,
    v.ts_created,
    v.ts_updated
from
    datalake_ebdb_clean.inspection as v
    left join comments c
        on v.id = c.id_inspection
