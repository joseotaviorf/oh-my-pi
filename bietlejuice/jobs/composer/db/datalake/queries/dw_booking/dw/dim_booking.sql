with
-- removing duplicates rows due to case difference in the taxonomy
taxonomy_demand as (
    with taxonomy_min_ids as (
        select
            min(cast(id as bigint)) as id
        from datalake_raw.gsheets_taxonomy_demand
        group by
            lower(app_type),
            lower(utm_source),
            lower(utm_medium),
            lower(branded),
            lower(first_update_source),
            flg_via_reschedule
    )
    select
        cast(td.id as bigint) as id,
        td.app_type,
        td.utm_source,
        td.utm_medium,
        td.branded,
        td.first_update_source,
        cast(td.flg_via_reschedule as boolean) as flg_via_reschedule,
        td.category as mkt_category,
        td.flow as mkt_flow,
        td.completion as mkt_completion,
        td.channel as mkt_channel,
        td.medium as mkt_medium,
        td.origin as mkt_origin,
        td.source as mkt_source,
        td.platform as mkt_platform
    from datalake_raw.gsheets_taxonomy_demand td
    join taxonomy_min_ids td_min
        on td.id = td_min.id
)
select
    b.id as sk_booking,
    coalesce(td.id, -1) as sk_rent_flow_taxonomy,
    b.id as id_booking,
    b.id_visitor,
    b.id_visit,
    b.id_house,
    b.id_agent,
    b.id_attendant,
    b.id_rent_flow,
    b.id_rescheduled_booking,
    b.visit_intent,
    b.type,
    b.is_visit_completed,
    b.is_visit_performed,
    b.is_closed,
    b.has_reschedule,
    b.is_via_reschedule,
    coalesce(src.is_branded, false) as is_branded,
    b.has_tenant_attended,
    b.has_agent_attended,
    -- TODO [ODS] review this rule
    coalesce(b.has_owner_arrived, true) as has_owner_arrived,
    b.is_entrance_successful,
    b.is_visit_created_from_app,
    b.is_visit_last_updated_from_app,
    b.visit_fup,
    b.status,
    b.slot_day,
    substring(b.last_status_change_reason, 1, 200) as last_status_change_reason,
    b.cancellation_reason,
    b.cancellation_reason_category,
    b.reason_category,
    b.responsible,
    b.last_update_source,
    b.first_update_source,
    b.tenant_absence_reason,
    b.agent_absence_reason,
    b.owner_missing_reason,
    b.troublesome_entrance_problem,
    b.checkin_status,
    src.app_type,
    -- TODO [ODS] review this rule
    coalesce(src.media_source, "Unknown") as media_source,
    src.adjust_network,
    src.utm_source,
    src.utm_medium,
    src.utm_campaign,
    src.utm_content,
    src.utm_term,
    case when td.id is null then 'Not Mapped' else td.mkt_category end as mkt_category,
    case when td.id is null then 'Not Mapped' else td.mkt_flow end as mkt_flow,
    case when td.id is null then 'Not Mapped' else td.mkt_completion end as mkt_completion,
    case when td.id is null then 'Not Mapped' else td.mkt_origin end as mkt_origin,
    case when td.id is null then 'Not Mapped' else td.mkt_channel end as mkt_channel,
    case when td.id is null then 'Not Mapped' else td.mkt_medium end as mkt_medium,
    case when td.id is null then 'Not Mapped' else td.mkt_source end as mkt_source,
    case when td.id is null then 'Not Mapped' else td.mkt_platform end as mkt_platform,
    b.ts_visit_fup,
    b.ts_visit_follow_up_local_tz,
    b.ts_booking_utc,
    b.ts_booking_local_tz,
    b.ts_first_canceled,
    b.ts_first_canceled_local_tz,
    b.ts_created,
    b.ts_created_local_tz,
    b.ts_updated,
    now() as ts_load
from datalake_booking.booking b
left join datalake_ebdb_clean.visit v
    on b.id_visit = v.id
left join datalake_amplitude_visit.amplitude_visit src
    on v.code = src.id_visit
left join taxonomy_demand td
    on lower(coalesce(td.app_type, '')) = lower(coalesce(src.app_type, ''))
    and lower(coalesce(td.utm_source, '')) = lower(coalesce(src.utm_source, ''))
    and lower(coalesce(td.utm_medium, '')) = lower(coalesce(src.utm_medium, ''))
    -- TODO [ODS] use flag is_branded from datalake_amplitude_visit.amplitude_visit
    and lower(coalesce(td.branded, '')) = lower(coalesce(src.branded, 'Outro'))
    and lower(coalesce(td.first_update_source, '')) = lower(coalesce(b.first_update_source, ''))
    and coalesce(td.flg_via_reschedule, false) = coalesce(b.is_via_reschedule, false)
    