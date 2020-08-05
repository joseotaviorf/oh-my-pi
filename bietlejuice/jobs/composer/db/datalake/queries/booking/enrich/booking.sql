with status_change as (
  -- get the last status-change for each booking and status
  with booking_status as (
    select
      bsc.id_reason_category,
      bsc.id_booking,
      bsc.status,
      replace(bsc.reason, '\n', '') as reason,
      bsc.reason_enum,
      row_number() OVER (
        PARTITION BY bsc.id_booking, bsc.status ORDER BY bsc.id DESC
      ) as status_change_row_number
    from
      datalake_ebdb_clean.booking_status_change bsc
  )
  select
    bs.*,
    acrc.name as reason_category
  from
    booking_status bs
  left join datalake_ebdb_clean.appointment_change_reason_category acrc
    on acrc.id = bs.id_reason_category
  where
    bs.status_change_row_number = 1
),
canceled_date as (
  with min_canceled_date as (
    select
        id as id_booking,
        min(REV) as rev_canceled
    from datalake_ebdb_clean.booking_aud
    where
        status='Cancelado'
        and mod_status = 1
    group by 1
  )
  select
    mcd.id_booking,
    -- TODO [ODS] check if milliseconds is really needed for this column
    cast(from_unixtime(ure.ts_revision/1000) as timestamp)
      + (ure.ts_revision % 1000) * interval 1 milliseconds
    as ts_first_canceled
  from min_canceled_date mcd
  join datalake_ebdb_clean.user_revision_entity ure
    on ure.id = mcd.rev_canceled
),
visit_origin as (
  select
    v.id as id_visit,
    vo_update.name as last_update_source,
    vo_create.name as first_update_source
  from datalake_ebdb_clean.visit v
  left join datalake_ebdb_clean.visit_origin vo_create
    on vo_create.id = v.id_creation_origin
  left join datalake_ebdb_clean.visit_origin vo_update
    on vo_update.id = v.id_last_update_origin
),
visitor_attendance as (
  select
    v.id_booking,
    max(if(v.type='Tenant', v.has_attended, NULL)) as has_tenant_attended,
    max(if(v.type='Agent', v.has_attended, NULL)) as has_agent_attended,
    max(if(v.type='LandLord', v.has_attended, NULL)) as has_landlord_attended
  from datalake_ebdb_clean.visitor v
  group by 1
),
visitor_absence_reason as (
  -- get valid absence reasons
  with base_reasons as (
    select
      id,
      id_booking,
      type,
      absence_reason
    from datalake_ebdb_clean.visitor
     where absence_reason is not null
  ),
    ordered_base_reasons as (
    -- identify the first absence reason per booking per visitor type
    select
      id_booking,
      type,
      absence_reason,
      row_number() over (partition by id_booking, type order by id) as absence_reason_row_number
    from
      base_reasons
  )
  select
    id_booking,
    max(if(type='Tenant', absence_reason, NULL)) as tenant_absence_reason,
    max(if(type='Agent', absence_reason, NULL)) as agent_absence_reason,
    max(if(type='Landlord', absence_reason, NULL)) as landlord_absence_reason
  from
   ordered_base_reasons
  where absence_reason_row_number = 1
  group by 1
),
reschedules as (
    select id_rescheduled_booking as id_rescheduled_from
    from datalake_ebdb_clean.booking
    where id_rescheduled_booking is not null
    group by 1 -- guaranteeing there are no future duplication on Product
),
base_booking as (
  select
    b.id,
    b.id_rescheduled_booking,
    b.id_visitor,
    b.id_visit,
    b.id_house,
    b.id_agent,
    b.id_attendant,
    b.id_rent_flow,
    b.dt_booking,
    b.status,
    b.business_context as visit_intent,
    b.type,
    b.visit_fup,
    b.slot_day,
    b.checkin_status,
    vo.last_update_source,
    vo.first_update_source,
    replace(sc.reason, '\n', '') as last_status_change_reason,
    sc.reason_enum as last_status_change_reason_enum,
    sc.reason_category as last_status_change_reason_category,
    if(vab.agent_absence_reason='Absent', NULL, vab.tenant_absence_reason)
      as tenant_absence_reason,
    vab.agent_absence_reason,
    vab.landlord_absence_reason,
    e.problem as troublesome_entrance_problem,
    if(b.status = 'Cancelado', sc.reason_enum, null) as cancellation_reason,
    case
      when b.status = 'Cancelado' then
        case
          when sc.reason_enum = 'CANCELED_HOUSE_RESERVED' then 'House Reserved'
          when sc.reason_enum = 'OTHER' then 'Other'
          when sc.reason_enum = 'CANCELED_CLIENT_GAVE_UP' then 'Tenant'
          when sc.reason_enum = 'PROPERTY_UNPUBLISHED' then 'House Unlisted'
          when sc.reason_enum = 'AGENT_SCHEDULE_REALIZED' then 'Agent'
          when sc.reason_enum = 'CANCELED_PROPERTY_SUSPENDED_ADVANCED_NEGOTIATIONS' then 'House Suspended'
          when sc.reason_enum = 'CANCELED_OWNER_SUSPENDED' then 'Consequence Management'
          when sc.reason_enum = 'CANCELED_OTHER_CLIENT' then 'Tenant'
          when sc.reason_enum = 'CANCELED_AGENT_CAN_NOT_JOIN' then 'Agent'
          when sc.reason_enum = 'CANCELED_INCORRECT_SCHEDULE' then 'Tenant'
          when sc.reason_enum = 'CANCELED_CLIENT_GAVE_UP_APARTMENT' then 'Tenant'
          when sc.reason_enum = 'CANCELED_AGENT_LATE_POOL' then 'Agent'
          when sc.reason_enum = 'AGENT_TRANSFER' then 'Agent'
          when sc.reason_enum = 'CANCELED_OWNER_CONSEQUENCE_MANAGEMENT' then 'Consequence Management'
          when sc.reason_enum = 'CANCELED_BY_TENANT_FROM_APP' then 'Tenant'
          when sc.reason_enum = 'CANCELED_OWNER_CAN_NOT_ATTEND' then 'Owner'
          when sc.reason_enum = 'SCHEDULE_CHANGE' then 'Reschedule_Tenant'
          when sc.reason_enum = 'CANCELED_CANT_FIND_ANOTHER_AGENT' then 'Agent'
          when sc.reason_enum = 'CANCELED_CLIENT_NOT_RENTING' then 'Tenant'
          when sc.reason_enum = 'CANCELED_OWNER_PROPERTY_ALREADY_RENTED_5A' then 'Owner'
          when sc.reason_enum = 'CANCELED_OWNER_CONSEQUENCE_MANAGEMENT_SUSPENDED' then 'Consequence Management'
          when sc.reason_enum = 'CANCELED_BY_TENANT_FROM_CHECK_IN' then 'Tenant'
          when sc.reason_enum = 'CANCELED_OWNER_PROPERTY_ALREADY_RENTED_OTHER' then 'Owner'
          when sc.reason_enum = 'CANCELED_OWNER_UNREACHABLE' then 'Owner'
          when sc.reason_enum = 'CANCELED_OWNER_UNREACHABLE_UNPUBLISHED' then 'Owner'
          when sc.reason_enum = 'CANCELED_CLIENT_CAN_NOT_ATTEND' then 'Tenant'
          when sc.reason_enum = 'CANCELED_AGENT_CAN_NOT_ATTEND' then 'Agent'
          when sc.reason_enum = 'CANCELED_BLOCKED_SCHEDULE' then 'Agent'
          when sc.reason_enum = 'CANCELED_SCHEDULED_OTHER_TIME' then 'Reschedule_Agent'
          when sc.reason_enum = 'CANCELED_OWNER_NO_RETURN_NEGOTIATIONS' then 'Owner'
          when sc.reason_enum = 'CANCELED_AUTOMATICALLY_PROPERTY_UNPUBLISHED' then 'House Unlisted'
          when sc.reason_enum = 'CANCELED_OWNER_NOT_RENTING' then 'Owner'
          when sc.reason_enum = 'CANCELED_CHECKIN_NOT_DONE' then 'Tenant'
          when sc.reason_enum = 'CANCELED_PROPERTY_UNAVAILABLE' then 'Owner'
          when sc.reason_enum = 'CANCELED_BY_OWNER_FROM_APP' then 'Owner'
          when sc.reason_enum = 'CANCELED_AGENT_DEACTIVATED' then 'Agent'
          when sc.reason_enum = 'CANCELED_OTHER_OWNER' then 'Owner'
          when sc.reason_enum = 'CANCELED_PROPERTY_SUSPENDED_UNAVAILABLE' then 'House Suspended'
          when sc.reason_enum = 'CANCELED_AGENT_VISIT_TOO_FAR' then 'Agent'
          when sc.reason_enum = 'CANCELED_BY_TENANT_CAN_NOT_ATTEND' then 'Tenant'
          when sc.reason_enum = 'CANCELED_BY_TENANT_NOT_INTERESTED' then 'Tenant'
          when sc.reason_enum = 'CANCELED_BY_TENANT_NOT_RENTING' then 'Tenant'
          when sc.reason_enum = 'CANCELED_BY_TENANT_NOT_RENTING_BY_5A' then 'Tenant'
          when sc.reason_enum = 'CANCELED_BY_TENANT_OTHER_REASON' then 'Tenant'
          when sc.reason_enum = 'CANCELED_OWNER_CONSEQUENCE_MANAGEMENT_REACTION_DUE_VISIT_CANCELATION' then 'Consequence Management'
          when sc.reason_enum = 'CANCELED_OWNER_CONSEQUENCE_MANAGEMENT_REACTION_DUE_NO_SHOW' then 'Consequence Management'
          else 'Unknown'
        end
    end as cancellation_reason_category,
    if(e.problem = 'LandlordNoShow', 'Absent', null) as owner_missing_reason,
    coalesce(
      nullif(
        coalesce(
          nullif(gsheets_cancel.new_reason,'CHECK ORIGEM'),
          case
            when vo.last_update_source in ('Inquilinos', 'SelfServiceWeb') then 'Tenant'
            when vo.last_update_source in ('Proprietarios', 'ProprietariosEmail') then 'Owner'
          end,
          case
            when sc.reason_enum = 'CANCELED_BY_OWNER_FROM_APP' then 'Owner'
            when sc.reason_enum = 'CANCELED_OWNER_CONSEQUENCE_MANAGEMENT_SUSPENDED' then 'Consequence Management'
            when sc.reason_enum = 'CANCELED_HOUSE_RESERVED' then 'House Reserved'
            when sc.reason_enum = 'AGENT_TRANSFER' then 'Agent'
          end,
          sc.reason_category
        ),
        'Other'
      ),
      'Unknown')
    as reason_category,
    b.ts_visit_fup,
    b.ts_created,
    b.ts_updated,
    if(date(cd.ts_first_canceled) <= date(b.dt_booking),
       cd.ts_first_canceled,
       null
    ) as ts_first_canceled,
    cast(b.dt_booking as timestamp)
      + ((b.slot_day * 15 / 60)+8) * interval 1 hours
      + abs(b.slot_day * 15 % 60) * interval 1 minutes
    as ts_booking_local_tz,
    from_utc_timestamp(b.ts_created, 'Brazil/East') as ts_created_local_tz,
    from_utc_timestamp(b.ts_visit_fup, 'Brazil/East') as ts_visit_follow_up_local_tz,
    b.is_confirmed,
    b.is_closed,
    b.is_agent_fixed,
    e.is_successful as is_entrance_successful,
    (b.status = 'Cancelado') as is_canceled,
    (b.business_context = 'SALE') as is_sale_visit,
    (b.type = 'Vistoria') as is_inspection,
    (b.type = 'Visita') as is_visit,
    (b.type = 'SessaoFotos') as is_photo_session,
    coalesce(b.visit_fup in ('NaoGostou', 'Talvez', 'VaiNegociar', 'VisitouSozinho'), false) as is_visit_completed,
    -- is a reschedule from another booking
    (b.id_rescheduled_booking is not null) as is_via_reschedule,
    -- was rescheduled to another booking
    (resc.id_rescheduled_from is not null) as has_reschedule,
    va.has_tenant_attended,
    va.has_agent_attended,
    va.has_landlord_attended,
    (e.problem <> 'LandlordNoShow') as has_owner_arrived
  from
    datalake_ebdb_clean.booking b
  left join visit_origin vo
    on b.id_visit = vo.id_visit
  left join status_change sc
    on sc.id_booking = b.id
    and sc.status = b.status
  left join canceled_date cd
    on cd.id_booking = b.id
  left join visitor_attendance va
    on b.id = va.id_booking
  left join visitor_absence_reason vab
    on b.id = vab.id_booking
  left join datalake_ebdb_clean.follow_up_details fud
    on fud.id = b.id_fup_details
  left join datalake_ebdb_clean.entrance e
    on fud.id_entrance = e.id
  left join reschedules resc
    on resc.id_rescheduled_from = b.id
  -- TODO: Migrate after gsheets dag is in Composer
  left join datalake_raw.gsheets_de_para_cancelamento gsheets_cancel
    on gsheets_cancel.reason = sc.reason
)
-- custom columns that need pre-calculated ones
select
  bb.*,
  to_utc_timestamp(bb.ts_booking_local_tz, 'Brazil/East') as ts_booking_utc,
  from_utc_timestamp(bb.ts_first_canceled, 'Brazil/East') as ts_first_canceled_local_tz,
  case
    when bb.cancellation_reason_category in (
      'Agent',
      'House Suspended',
      'House Reserved',
      'House Unlisted',
      'Consequence Management'
      ) then 'QuintoAndar'
    when bb.cancellation_reason_category in (
      'Reschedule_Tenant',
      'Reschedule_Agent'
      ) then 'Reschedule'
    else bb.cancellation_reason_category
  end as responsible
from
  base_booking bb