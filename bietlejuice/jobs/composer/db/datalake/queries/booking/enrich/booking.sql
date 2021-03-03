WITH status_change AS (
  -- get the last status-change for each booking and status
  WITH booking_status AS (
    SELECT
      bsc.id_reason_category,
      bsc.id_booking,
      bsc.status,
      REPLACE(bsc.reason, '\n', '') AS reason,
      bsc.reason_enum,
      ROW_NUMBER() OVER (
        PARTITION BY bsc.id_booking, bsc.status ORDER BY bsc.id DESC
      ) AS status_change_row_number
    FROM
      datalake_ebdb_clean.booking_status_change AS bsc
  )
  SELECT
    bs.*,
    acrc.name AS reason_category
  FROM
    booking_status AS bs
  LEFT JOIN
    datalake_ebdb_clean.appointment_change_reason_category AS acrc
      ON acrc.id = bs.id_reason_category
  WHERE
    bs.status_change_row_number = 1
),
canceled_date AS (
  WITH min_canceled_date AS (
    SELECT
        id AS id_booking,
        MIN(REV) AS rev_canceled
    FROM
      datalake_ebdb_clean.booking_aud
    WHERE
        status = 'Cancelado'
        AND mod_status = 1
    GROUP BY 1
  )
  SELECT
    mcd.id_booking,
    -- TODO [ODS] check if milliseconds is really needed for this column
    CAST(FROM_UNIXTIME(ure.ts_revision/1000) AS TIMESTAMP)
      + (ure.ts_revision % 1000) * INTERVAL 1 MILLISECONDS
    AS ts_first_canceled
  FROM
    min_canceled_date AS mcd
  JOIN
    datalake_ebdb_clean.user_revision_entity AS ure
      ON ure.id = mcd.rev_canceled
),
visit_origin AS (
  SELECT
    v.id AS id_visit,
    v.id_real_estate_agent_rating,
    v.code,
    vo_create.is_app AS is_visit_created_from_app,
    vo_update.is_app AS is_visit_last_updated_from_app,
    vo_update.name AS last_update_source,
    vo_create.name AS first_update_source
  FROM
    datalake_ebdb_clean.visit AS v
  LEFT JOIN
    datalake_ebdb_clean.visit_origin AS vo_create
      ON vo_create.id = v.id_creation_origin
  LEFT JOIN 
    datalake_ebdb_clean.visit_origin AS vo_update
      ON vo_update.id = v.id_last_update_origin
),
visitor_attendance AS (
  SELECT
    v.id_booking,
    MAX(IF(v.type='Tenant', v.has_attended, NULL)) AS has_tenant_attended,
    MAX(IF(v.type='Agent', v.has_attended, NULL)) AS has_agent_attended,
    MAX(IF(v.type='LandLord', v.has_attended, NULL)) AS has_landlord_attended
  FROM
    datalake_ebdb_clean.visitor AS v
  GROUP BY 1
),
visitor_absence_reason AS (
  -- get valid absence reasons
  WITH base_reasons AS (
    SELECT
      id,
      id_booking,
      type,
      absence_reason
    FROM
      datalake_ebdb_clean.visitor
     WHERE
      absence_reason IS NOT NULL
  ),
    ordered_base_reasons AS (
    -- identify the first absence reason per booking per visitor type
    SELECT
      id_booking,
      type,
      absence_reason,
      ROW_NUMBER() OVER (PARTITION BY id_booking, type ORDER BY id) AS absence_reason_row_number
    FROM
      base_reasons
  )
  SELECT
    id_booking,
    MAX(IF(type='Tenant', absence_reason, NULL)) AS tenant_absence_reason,
    MAX(IF(type='Agent', absence_reason, NULL)) AS agent_absence_reason,
    MAX(IF(type='Landlord', absence_reason, NULL)) AS landlord_absence_reason
  FROM
   ordered_base_reasons
  WHERE
    absence_reason_row_number = 1
  GROUP BY 1
),
reschedules AS (
    SELECT
      id_rescheduled_booking AS id_rescheduled_from
    FROM
      datalake_ebdb_clean.booking
    WHERE
      id_rescheduled_booking IS NOT NULL
    GROUP BY 1 -- guaranteeing there are no future duplication on Product
),
base_booking AS (
  SELECT
    b.id,
    b.id_rescheduled_booking,
    b.id_visitor,
    b.id_visit,
    b.id_house,
    b.id_agent,
    b.id_attendant,
    b.id_rent_flow,
    IF(b.business_context = 'SALE', 
      CONCAT(b.id_visitor, '_', b.id_house), 
      NULL
    ) AS id_sale_flow,
    vo.id_real_estate_agent_rating,
    b.dt_booking,
    b.status,
    b.business_context AS visit_intent,
    b.buyer_intention,
    b.type,
    b.visit_fup,
    b.slot_day,
    b.checkin_status,
    vo.last_update_source,
    vo.first_update_source,
    vo.is_visit_created_from_app,
    vo.is_visit_last_updated_from_app,
    vo.code,
    REPLACE(sc.reason, '\n', '') AS last_status_change_reason,
    sc.reason_enum AS last_status_change_reason_enum,
    sc.reason_category AS last_status_change_reason_category,
    IF(vab.agent_absence_reason='Absent', NULL, vab.tenant_absence_reason)
      AS tenant_absence_reason,
    vab.agent_absence_reason,
    vab.landlord_absence_reason,
    e.problem AS troublesome_entrance_problem,
    IF(b.status = 'Cancelado', sc.reason_enum, NULL) AS cancellation_reason,
    CASE
      WHEN b.status = 'Cancelado' THEN
        CASE
          WHEN sc.reason_enum = 'CANCELED_HOUSE_RESERVED' THEN 'House Reserved'
          WHEN sc.reason_enum = 'OTHER' THEN 'Other'
          WHEN sc.reason_enum = 'CANCELED_CLIENT_GAVE_UP' THEN 'Tenant'
          WHEN sc.reason_enum = 'PROPERTY_UNPUBLISHED' THEN 'House Unlisted'
          WHEN sc.reason_enum = 'AGENT_SCHEDULE_REALIZED' THEN 'Agent'
          WHEN sc.reason_enum = 'CANCELED_PROPERTY_SUSPENDED_ADVANCED_NEGOTIATIONS' THEN 'House Suspended'
          WHEN sc.reason_enum = 'CANCELED_OWNER_SUSPENDED' THEN 'Consequence Management'
          WHEN sc.reason_enum = 'CANCELED_OTHER_CLIENT' THEN 'Tenant'
          WHEN sc.reason_enum = 'CANCELED_AGENT_CAN_NOT_JOIN' THEN 'Agent'
          WHEN sc.reason_enum = 'CANCELED_INCORRECT_SCHEDULE' THEN 'Tenant'
          WHEN sc.reason_enum = 'CANCELED_CLIENT_GAVE_UP_APARTMENT' THEN 'Tenant'
          WHEN sc.reason_enum = 'CANCELED_AGENT_LATE_POOL' THEN 'Agent'
          WHEN sc.reason_enum = 'AGENT_TRANSFER' THEN 'Agent'
          WHEN sc.reason_enum = 'CANCELED_OWNER_CONSEQUENCE_MANAGEMENT' THEN 'Consequence Management'
          WHEN sc.reason_enum = 'CANCELED_BY_TENANT_FROM_APP' THEN 'Tenant'
          WHEN sc.reason_enum = 'CANCELED_OWNER_CAN_NOT_ATTEND' THEN 'Owner'
          WHEN sc.reason_enum = 'SCHEDULE_CHANGE' THEN 'Reschedule_Tenant'
          WHEN sc.reason_enum = 'CANCELED_CANT_FIND_ANOTHER_AGENT' THEN 'Agent'
          WHEN sc.reason_enum = 'CANCELED_CLIENT_NOT_RENTING' THEN 'Tenant'
          WHEN sc.reason_enum = 'CANCELED_OWNER_PROPERTY_ALREADY_RENTED_5A' THEN 'Owner'
          WHEN sc.reason_enum = 'CANCELED_OWNER_CONSEQUENCE_MANAGEMENT_SUSPENDED' THEN 'Consequence Management'
          WHEN sc.reason_enum = 'CANCELED_BY_TENANT_FROM_CHECK_IN' THEN 'Tenant'
          WHEN sc.reason_enum = 'CANCELED_OWNER_PROPERTY_ALREADY_RENTED_OTHER' THEN 'Owner'
          WHEN sc.reason_enum = 'CANCELED_OWNER_UNREACHABLE' THEN 'Owner'
          WHEN sc.reason_enum = 'CANCELED_OWNER_UNREACHABLE_UNPUBLISHED' THEN 'Owner'
          WHEN sc.reason_enum = 'CANCELED_CLIENT_CAN_NOT_ATTEND' THEN 'Tenant'
          WHEN sc.reason_enum = 'CANCELED_AGENT_CAN_NOT_ATTEND' THEN 'Agent'
          WHEN sc.reason_enum = 'CANCELED_BLOCKED_SCHEDULE' THEN 'Agent'
          WHEN sc.reason_enum = 'CANCELED_SCHEDULED_OTHER_TIME' THEN 'Reschedule_Agent'
          WHEN sc.reason_enum = 'CANCELED_OWNER_NO_RETURN_NEGOTIATIONS' THEN 'Owner'
          WHEN sc.reason_enum = 'CANCELED_AUTOMATICALLY_PROPERTY_UNPUBLISHED' THEN 'House Unlisted'
          WHEN sc.reason_enum = 'CANCELED_OWNER_NOT_RENTING' THEN 'Owner'
          WHEN sc.reason_enum = 'CANCELED_CHECKIN_NOT_DONE' THEN 'Tenant'
          WHEN sc.reason_enum = 'CANCELED_PROPERTY_UNAVAILABLE' THEN 'Owner'
          WHEN sc.reason_enum = 'CANCELED_BY_OWNER_FROM_APP' THEN 'Owner'
          WHEN sc.reason_enum = 'CANCELED_AGENT_DEACTIVATED' THEN 'Agent'
          WHEN sc.reason_enum = 'CANCELED_OTHER_OWNER' THEN 'Owner'
          WHEN sc.reason_enum = 'CANCELED_PROPERTY_SUSPENDED_UNAVAILABLE' THEN 'House Suspended'
          WHEN sc.reason_enum = 'CANCELED_AGENT_VISIT_TOO_FAR' THEN 'Agent'
          WHEN sc.reason_enum = 'CANCELED_BY_TENANT_CAN_NOT_ATTEND' THEN 'Tenant'
          WHEN sc.reason_enum = 'CANCELED_BY_TENANT_NOT_INTERESTED' THEN 'Tenant'
          WHEN sc.reason_enum = 'CANCELED_BY_TENANT_NOT_RENTING' THEN 'Tenant'
          WHEN sc.reason_enum = 'CANCELED_BY_TENANT_NOT_RENTING_BY_5A' THEN 'Tenant'
          WHEN sc.reason_enum = 'CANCELED_BY_TENANT_OTHER_REASON' THEN 'Tenant'
          WHEN sc.reason_enum = 'CANCELED_OWNER_CONSEQUENCE_MANAGEMENT_REACTION_DUE_VISIT_CANCELATION' THEN 'Consequence Management'
          WHEN sc.reason_enum = 'CANCELED_OWNER_CONSEQUENCE_MANAGEMENT_REACTION_DUE_NO_SHOW' THEN 'Consequence Management'
          ELSE 'Unknown'
        END
    END AS cancellation_reason_category,
    IF(e.problem = 'LandlordNoShow', 'Absent', NULL) AS owner_missing_reason,
    COALESCE(
      NULLIF(
        COALESCE(
          NULLIF(gsheets_cancel.new_reason,'CHECK ORIGEM'),
          CASE
            WHEN vo.last_update_source IN ('Inquilinos', 'SelfServiceWeb') THEN 'Tenant'
            WHEN vo.last_update_source IN ('Proprietarios', 'ProprietariosEmail') THEN 'Owner'
          END,
          CASE
            WHEN sc.reason_enum = 'CANCELED_BY_OWNER_FROM_APP' THEN 'Owner'
            WHEN sc.reason_enum = 'CANCELED_OWNER_CONSEQUENCE_MANAGEMENT_SUSPENDED' THEN 'Consequence Management'
            WHEN sc.reason_enum = 'CANCELED_HOUSE_RESERVED' THEN 'House Reserved'
            WHEN sc.reason_enum = 'AGENT_TRANSFER' THEN 'Agent'
          END,
          sc.reason_category
        ),
        'Other'
      ),
      'Unknown')
    AS reason_category,
    b.ts_visit_fup,
    b.ts_created,
    b.ts_updated,
    IF(DATE(cd.ts_first_canceled) <= DATE(b.dt_booking),
       cd.ts_first_canceled,
       NULL
    ) AS ts_first_canceled,
    CAST(b.dt_booking AS TIMESTAMP)
      + ((b.slot_day * 15 / 60)+8) * INTERVAL 1 HOURS
      + abs(b.slot_day * 15 % 60) * INTERVAL 1 MINUTES
    AS ts_booking_local_tz,
    FROM_UTC_TIMESTAMP(b.ts_created, 'Brazil/East') AS ts_created_local_tz,
    FROM_UTC_TIMESTAMP(b.ts_visit_fup, 'Brazil/East') AS ts_visit_follow_up_local_tz,
    b.is_confirmed,
    b.is_closed,
    b.is_agent_fixed,
    e.is_successful AS is_entrance_successful,
    (b.status = 'Cancelado') AS is_canceled,
    (b.business_context = 'SALE') AS is_sale_visit,
    (b.type = 'Vistoria') AS is_inspection,
    (b.type = 'Visita') AS is_visit,
    (b.type = 'SessaoFotos') AS is_photo_session,
    COALESCE(b.visit_fup IN ('NaoGostou', 'Talvez', 'VaiNegociar', 'VisitouSozinho'), FALSE) AS is_visit_completed,
    COALESCE(b.visit_fup IS NOT NULL AND vab.agent_absence_reason = 'Absent', FALSE) AS is_visit_performed,
    -- is a reschedule from another booking
    (b.id_rescheduled_booking IS NOT NULL) AS is_via_reschedule,
    -- was rescheduled to another booking
    (resc.id_rescheduled_from IS NOT NULL) AS has_reschedule,
    va.has_tenant_attended,
    va.has_agent_attended,
    va.has_landlord_attended,
    (e.problem <> 'LandlordNoShow') AS has_owner_arrived
  FROM
    datalake_ebdb_clean.booking AS b
  LEFT JOIN
    visit_origin AS vo
      ON b.id_visit = vo.id_visit
  LEFT JOIN
    status_change AS sc
      ON sc.id_booking = b.id
      AND sc.status = b.status
  LEFT JOIN
    canceled_date AS cd
      ON cd.id_booking = b.id
  LEFT JOIN
    visitor_attendance AS va
      ON b.id = va.id_booking
  LEFT JOIN
    visitor_absence_reason AS vab
      ON b.id = vab.id_booking
  LEFT JOIN
    datalake_ebdb_clean.follow_up_details AS fud
      ON fud.id = b.id_fup_details
  LEFT JOIN
    datalake_ebdb_clean.entrance AS e
      ON fud.id_entrance = e.id
  LEFT JOIN
    reschedules AS resc
      ON resc.id_rescheduled_from = b.id
  LEFT JOIN
    datalake_gsheets_clean.from_to_cancellation AS gsheets_cancel
      ON gsheets_cancel.reason = sc.reason
)
-- custom columns that need pre-calculated ones
SELECT
  bb.*,
  TO_UTC_TIMESTAMP(bb.ts_booking_local_tz, 'Brazil/East') AS ts_booking_utc,
  FROM_UTC_TIMESTAMP(bb.ts_first_canceled, 'Brazil/East') AS ts_first_canceled_local_tz,
  CASE
    WHEN bb.cancellation_reason_category IN (
      'Agent',
      'House Suspended',
      'House Reserved',
      'House Unlisted',
      'Consequence Management'
      ) THEN 'QuintoAndar'
    WHEN bb.cancellation_reason_category IN (
      'Reschedule_Tenant',
      'Reschedule_Agent'
      ) THEN 'Reschedule'
    ELSE bb.cancellation_reason_category
  END AS responsible,
  DATEDIFF(FROM_UTC_TIMESTAMP(bb.ts_first_canceled, 'Brazil/East'), bb.ts_created_local_tz) AS days_visit_booked_to_visit_cancelled,
  IF(is_visit_completed, DATEDIFF(bb.ts_booking_local_tz, bb.ts_created_local_tz), NULL)
   AS days_visit_booked_to_visit_completed 
FROM
  base_booking AS bb
