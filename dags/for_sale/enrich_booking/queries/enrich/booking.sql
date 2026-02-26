WITH status_change AS (
    SELECT
        id_booking,
        status,
        reason,
        reason_enum,
        reason_category
    FROM
        datalake_booking.booking_status_change_unified
),
canceled_date AS (
    SELECT
        id_booking,
        id_user as id_user_cancelation,
        ts_created as ts_first_canceled
    FROM
        datalake_booking.booking_status_change_unified
    WHERE
        status = 'Cancelado'
),
visit_origin_unified AS (
    WITH old_origin AS (
        SELECT
            v.id AS id_visit,
            v.id_real_estate_agent_rating,
            v.code,
            CASE
                WHEN vo.name = 'SelfServiceWeb' THEN 'TENANT_PWA'
                WHEN vo.name = 'Admin' THEN 'MAGIC_LINK'
                WHEN vo.name = 'Sistema' THEN 'SYSTEM'
                WHEN vo.name = 'Corretores' THEN 'AGENT_PWA'
                WHEN vo.name = 'Inquilinos' THEN 'TENANT_NATIVE'
                WHEN vo.name = 'Proprietarios' THEN 'OWNER_PWA'
                WHEN vo.name = 'Portfolio' THEN 'PORTFOLIO_MANAGER'
                WHEN vo.name = 'MagicLink' THEN 'MAGIC_LINK'
                WHEN vo.name = 'WhatsApp' THEN 'WHATSAPP'
                ELSE UPPER(vo.name)
            END AS first_update_source,
            CASE
                WHEN vo_update.name = 'SelfServiceWeb' THEN 'TENANT_PWA'
                WHEN vo_update.name = 'Admin' THEN 'MAGIC_LINK'
                WHEN vo_update.name = 'Sistema' THEN 'SYSTEM'
                WHEN vo_update.name = 'Corretores' THEN 'AGENT_PWA'
                WHEN vo_update.name = 'Inquilinos' THEN 'TENANT_NATIVE'
                WHEN vo_update.name = 'Proprietarios' THEN 'OWNER_PWA'
                WHEN vo_update.name = 'Portfolio' THEN 'PORTFOLIO_MANAGER'
                WHEN vo_update.name = 'MagicLink' THEN 'MAGIC_LINK'
                WHEN vo_update.name = 'WhatsApp' THEN 'WHATSAPP'
                ELSE UPPER(vo_update.name)
            END AS last_update_source,
            v.ts_created AS ts_visit_requested
        FROM
            datalake_ebdb_clean.visit AS v
        LEFT JOIN
            datalake_ebdb_clean.visit_origin AS vo
                ON v.id_creation_origin = vo.id
        LEFT JOIN
            datalake_ebdb_clean.visit_origin AS vo_update
                ON v.id_last_update_origin = vo_update.id
        WHERE
            DATE(v.ts_created) < '2024-11-01'
    ),
    new_origin AS (
        SELECT
            id_visit,
            MIN(channel) FILTER (WHERE event_type = 'VISIT_REQUESTED') AS first_update_source,
            MAX_BY(channel, ts_created) AS last_update_source,
            MIN(ts_created) FILTER (WHERE event_type = 'VISIT_REQUESTED') AS ts_visit_requested
        FROM
            datalake_ebdb_clean.visit_status_log
        WHERE
            DATE(ts_created) >= '2024-11-01'
        GROUP BY 1
    )
    SELECT
        id_visit,
        id_real_estate_agent_rating,
        code,
        first_update_source,
        last_update_source,
        ts_visit_requested
    FROM
        old_origin
    UNION ALL
    SELECT
        new.id_visit,
        v.id_real_estate_agent_rating,
        v.code,
        new.first_update_source,
        new.last_update_source,
        new.ts_visit_requested
    FROM
        new_origin AS new
    LEFT JOIN
        datalake_ebdb_clean.visit AS v
            ON new.id_visit = v.id
    WHERE
        new.ts_visit_requested IS NOT NULL
),
visitor_attendance AS (
    SELECT
        v.id_booking,
        MAX(IF(v.type='Tenant', v.has_attended, NULL)) AS has_tenant_attended,
        MAX(IF(v.type='Agent', v.has_attended, NULL)) AS has_agent_attended,
        MAX(IF(v.type='LandLord', v.has_attended, NULL)) AS has_landlord_attended
    FROM
        datalake_ebdb_clean.visitor AS v
    GROUP BY v.id_booking
),
visitor_absence_reason AS (
    -- get valid absence reasons
    WITH base_reasons AS (
        SELECT
            id,
            id_booking,
            type,
            absence_reason,
            ROW_NUMBER() OVER (PARTITION BY id_booking, type ORDER BY id) AS absence_reason_row_number
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
        absence_reason
    FROM
        base_reasons
    WHERE
        absence_reason_row_number = 1
    )
    SELECT
        id_booking,
        MAX(IF(type='Tenant', absence_reason, NULL)) AS tenant_absence_reason,
        MAX(IF(type='Agent', absence_reason, NULL)) AS agent_absence_reason,
        MAX(IF(type='Landlord', absence_reason, NULL)) AS landlord_absence_reason
    FROM
        ordered_base_reasons
    GROUP BY
        id_booking
),
reschedules AS (
    SELECT
        id_rescheduled_booking AS id_rescheduled_from
    FROM
        datalake_ebdb_clean.booking
    WHERE
        id_rescheduled_booking IS NOT NULL
    GROUP BY
        id_rescheduled_booking -- guaranteeing there are no future duplication on Product
),
status_log AS (
  SELECT
    id_schedule,
    id_author_user
  FROM
    datalake_ebdb_clean.visit_status_log
  WHERE
    event_type IN ('VISIT_REQUESTED', 'VISIT_RESCHEDULED')
    AND ts_created >= '2024-08-01'
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_schedule ORDER BY ts_created) = 1
),
first_booking_author_sc AS (
    SELECT DISTINCT
        bsc.id_booking,
        FIRST_VALUE(bsc.id_user) OVER (
          PARTITION BY bsc.id_booking ORDER BY bsc.id
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS id_user_creation
    FROM
        datalake_ebdb_clean.booking_status_change AS bsc
    LEFT JOIN
        datalake_ebdb_clean.booking AS b
            ON bsc.id_booking = b.id
    WHERE
        (b.type = 'Visita' AND bsc.ts_created::date < '2025-09-01')
        OR (b.type != 'Visita')
),
first_booking_author AS (
    SELECT DISTINCT
        b.id AS id_booking,
        COALESCE(sl.id_author_user, b.id_attendant, fbasc.id_user_creation) AS id_user_creation
    FROM
        datalake_ebdb_clean.booking AS b
    LEFT JOIN
        status_log AS sl
            ON b.id = sl.id_schedule
    LEFT JOIN
        first_booking_author_sc AS fbasc
            ON b.id = fbasc.id_booking
),
visitor_fixed_agent AS (
    WITH fixed_agent_disabled AS (
    -- Gets the last date the fixed_agent was disabled
        SELECT
            pfa_aud.id,
            MAX(CASE WHEN pfa_aud.is_enabled = FALSE THEN FROM_UNIXTIME(ure.ts_revision / 1000) END) AS ts_fixed_agent_disabled
        FROM
            datalake_ebdb_clean.preferred_fixed_agent_aud pfa_aud
        LEFT JOIN
            datalake_ebdb_clean.user_revision_entity ure
                ON ure.id = pfa_aud.rev
        WHERE
            pfa_aud.mod_is_enabled = true
        GROUP BY
            pfa_aud.id
    ),
    preferred_fixed_agent AS (
        SELECT
            id,
            id_user_visit_preferences,
            id_agent_data,
            id_region,
            business_context,
            ROW_NUMBER() OVER (PARTITION BY id_user_visit_preferences ORDER BY ts_updated DESC) AS rw_number,
            is_enabled,
            ts_created
        FROM
            datalake_ebdb_clean.preferred_fixed_agent AS a
    )
    -- Looks the booking date and find which agent was linked to the buyer at the period
    -- Buyers can have different fixed agents in each city, so it has to match the id_city of the house visited
    SELECT
        uvp.id_user,
        pfa.id_agent_data AS id_fixed_agent,
        b.id AS id_booking,
        pfa.business_context
    FROM
        datalake_ebdb_clean.user_visit_preferences uvp
    JOIN
        preferred_fixed_agent AS pfa
            ON pfa.id_user_visit_preferences = uvp.id
    LEFT JOIN
        fixed_agent_disabled fad
            ON fad.id = pfa.id
    JOIN
        datalake_ebdb_clean.booking b
            ON b.id_visitor = uvp.id_user
            AND b.business_context = pfa.business_context
    JOIN
        datalake_ebdb_clean.house h
            ON h.id = b.id_house
    JOIN
        datalake_region.region r
            ON r.id = h.id_region
    WHERE
    -- If the fixed_agent is active it compares bookings from pfa creation until now
    -- Otherwise it compares bookings from pfa creation until pfa disabled
        b.ts_created BETWEEN pfa.ts_created AND IF(pfa.is_enabled = TRUE, NOW(), fad.ts_fixed_agent_disabled)
        AND r.id_city = pfa.id_region -- id_region from pfa it's actually the id_city]
        AND pfa.rw_number = 1
),
booking_in_rented_house AS (
-- Track if the sale visit was in a house with rental contract active
    SELECT
        b.id,
        BOOL_OR(
          CASE
             WHEN c.status = 'Ativo' AND c.dt_started <= b.dt_booking THEN TRUE
             WHEN c.status = 'Finalizado' AND b.dt_booking BETWEEN c.dt_started AND LEAST(TO_DATE(c.ts_analyst_annulment_input), c.dt_termination) THEN TRUE
             ELSE FALSE
          END
        ) AS is_house_rented
    FROM
        datalake_ebdb_clean.booking AS b
    JOIN
        datalake_ebdb_contract.contract AS c
            ON c.id_house = b.id_house
    WHERE
        c.status in ('Ativo','Finalizado')
        AND b.dt_booking BETWEEN c.dt_started
        AND CASE
                WHEN c.status = 'Ativo' THEN NOW()
                WHEN c.status = 'Finalizado' THEN LEAST(TO_DATE(c.ts_analyst_annulment_input), c.dt_termination)
            END
        AND b.business_context = 'SALE'
    GROUP BY
        b.id
),
agent_contract_aud AS (
    SELECT
        adaud.id AS id_agent,
        adaud.rev,
        adaud.id_work_contract,
        CAST(FROM_UNIXTIME(ure.ts_revision/1000) AS TIMESTAMP) + (ure.ts_revision % 1000) * INTERVAL 1 MILLISECONDS AS ts_revision,
        LAG(adaud.id_work_contract) OVER (PARTITION BY adaud.id ORDER BY adaud.rev) AS previous_id_work_contract
    FROM
        datalake_ebdb_clean.agent_data_aud AS adaud
    LEFT JOIN
        datalake_ebdb_clean.user_revision_entity AS ure
            ON ure.id = adaud.rev
    WHERE
        adaud.id_work_contract IS NOT NULL
),
agent_contract AS (
    SELECT
        id_agent,
        id_work_contract,
        ts_revision AS ts_work_contract_start,
        LEAD(ts_revision) OVER (PARTITION BY id_agent ORDER BY rev) AS ts_work_contract_end
    FROM
        agent_contract_aud
    WHERE
        previous_id_work_contract <> id_work_contract
        OR previous_id_work_contract IS NULL
),
-- Rule to identify bookings from agents that works in HUB flow
booking_hub_agent AS (
    SELECT
        b.id,
        wc.contract_name
    FROM
        agent_contract AS ac
    JOIN
        datalake_ebdb_clean.booking AS b
            ON b.ts_created BETWEEN ac.ts_work_contract_start AND COALESCE(ac.ts_work_contract_end, CURRENT_DATE)
            AND ac.id_agent = b.id_agent
    LEFT JOIN
        datalake_ebdb_clean.work_contract AS wc
            ON wc.id = ac.id_work_contract
    WHERE
        -- Work contract that indicates agents working in HUB flow
        wc.contract_name LIKE 'HUB%'
        -- Date that the visits in HUB flow started
        AND CAST(b.ts_created AS DATE) >= '2021-07-19'
),
secretariat_on_visit_date AS (
    SELECT
        b.id,
        bsc.id_external_responsible AS id_user_secretariat_on_visit_date
    FROM
        datalake_ebdb_clean.booking AS b
    JOIN
        datalake_hub_services.buyer_secretariat_changes AS bsc
            ON b.id_visitor = bsc.id_external_lead
            AND b.dt_booking BETWEEN bsc.ts_assigned AND COALESCE(bsc.ts_unassigned, GREATEST(NOW(), b.dt_booking))
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY b.id ORDER BY bsc.ts_assigned DESC) = 1
),
last_secretariat as (
    SELECT
        b.id,
        bsc.id_external_responsible AS id_user_last_secretariat
    FROM
        datalake_ebdb_clean.booking AS b
    JOIN
        datalake_hub_services.buyer_secretariat_changes AS bsc
            ON b.id_visitor = bsc.id_external_lead
            AND bsc.is_last_responsible
),
visit_fup_vsl AS ( -- This is to handle the case where the visit_fup is not in the booking table (missing data from visit finalization rollout) so the visit finalization is enriched temporarily from visit_status_log table.
    SELECT
        id_visit,
        id_schedule,
        CASE
            WHEN event_type = 'VISIT_DONE' THEN 'VaiNegociar'
            WHEN event_type = 'VISIT_UNSUCCESSFUL' AND reason IN ('DEMAND_DID_NOT_ATTEND_VISIT', 'AGENT_DID_NOT_ATTEND_VISIT', 'SUPPLY_DID_NOT_ATTEND_VISIT') THEN 'NaoCompareceu'
            WHEN event_type = 'VISIT_UNSUCCESSFUL' AND reason IN ('ACCESS_TO_HOUSE_NOT_AUTHORIZED', 'HOUSE_KEYS_NOT_AVAILABLE', 'HOUSE_NO_LONGER_AVAILABLE_FOR_RENT', 'TENANT_LIVING_DID_NOT_ALLOW_VISIT', 'HOUSE_NO_LONGER_AVAILABLE_FOR_SALE') THEN 'EntradaNaoAutorizada'
        END AS visit_fup,
        ts_created AS ts_visit_fup
    FROM
        datalake_ebdb_clean.visit_status_log
    WHERE
        ts_created::DATE >= '2025-01-01'
        AND event_type IN ('VISIT_DONE', 'VISIT_UNSUCCESSFUL')
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_visit ORDER BY id_visit_status_log DESC) = 1
),
base_booking AS (
    SELECT
        b.id,
        hl.id_country,
        b.id_rescheduled_booking,
        b.id_visitor,
        b.id_visit,
        fba.id_user_creation,
        cd.id_user_cancelation,
        b.id_house,
        b.id_agent,
        ua.id AS id_user_sale_agent,
        b.id_attendant,
        su.id_user_5a AS id_user_sale_attendence_5a,
        sod.id_user_secretariat_on_visit_date,
        ls.id_user_last_secretariat,
        b.id_rent_flow,
        IF(b.business_context = 'SALE',
          CONCAT(b.id_visitor, '_', b.id_house),
          NULL
        ) AS id_sale_flow,
        vou.id_real_estate_agent_rating,
        IF(b.business_context = 'SALE', vfa.id_fixed_agent,NULL) AS id_sale_fixed_agent,
        vbm.id_company_supply,
        hl.uuid_company AS uuid_company_supply,
        vbm.id_company_demand,
        vbm.is_3p_supply,
        vbm.is_3p_demand,
        vbm.is_3p_lead_gen,
        vbm.has_3p_access_control,
        b.id_schedule,
        COALESCE(hl.country_code, 'Undefined') AS country_code,
        COALESCE(ct.default_timezone, 'UTC') AS default_timezone,
        b.dt_booking,
        b.status,
        b.business_context AS visit_intent,
        b.buyer_intention,
        b.type,
        COALESCE(b.visit_fup, fup_vsl.visit_fup) AS visit_fup,
        v_cin.checkin_code,
        v_cin.checkin_status AS visit_checkin_status,
        v_cin.checkin_fail_reason,
        v_cin.checkin_fail_commentary,
        b.slot_day,
        b.checkin_status,
        u.email AS user_creation_email,
        vou.first_update_source,
        vou.code,
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
                WHEN vou.last_update_source IN ('TENANT_NATIVE', 'TENANT_PWA') THEN 'Tenant'
                WHEN vou.last_update_source IN ('OWNER_PWA', 'PROPRIETARIOSEMAIL') THEN 'Owner'
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
        IF(
          b.business_context = 'SALE',
            (
              CASE
                WHEN fba.id_user_creation = ua.id THEN 'Agent'
                WHEN fba.id_user_creation = b.id_visitor THEN 'Buyer'
                WHEN fba.id_user_creation = su.id_user_5a THEN 'Secretaria'
                WHEN u.email LIKE '%quintoandar.com.br' THEN 'Admin/CX'
                ELSE 'Other'
              END
            ),
            NULL
        ) AS user_sale_booking_creator,
        bha.contract_name AS hub_agent_region,
        vbm.partner_3p_demand,
        vbm.partner_3p_supply,
        COALESCE(b.ts_visit_fup, fup_vsl.ts_visit_fup) AS ts_visit_fup,
        b.ts_created,
        b.ts_updated,
        IF(DATE(cd.ts_first_canceled) <= DATE(b.dt_booking),
           cd.ts_first_canceled,
           NULL
        ) AS ts_first_canceled,
        cd.ts_first_canceled AS ts_first_canceled_unevaluated,
        CAST(b.dt_booking AS TIMESTAMP)
          + FLOOR((b.slot_day * 15 / 60)+8) * INTERVAL 1 HOURS
          + ABS(b.slot_day * 15 % 60) * INTERVAL 1 MINUTES
        AS ts_booking_local_tz,
        FROM_UTC_TIMESTAMP(b.ts_created, COALESCE(ct.default_timezone, 'UTC')) AS ts_created_local_tz,
        FROM_UTC_TIMESTAMP(COALESCE(b.ts_visit_fup, fup_vsl.ts_visit_fup), COALESCE(ct.default_timezone, 'UTC')) AS ts_visit_follow_up_local_tz,
        b.is_confirmed,
        b.is_closed,
        b.is_agent_fixed,
        IF(bha.id IS NOT NULL, TRUE, FALSE) AS is_hub_flow,
        CASE
          WHEN COALESCE(
            (hl.is_sale_3p_supply AND b.business_context = 'SALE')
            OR (hl.is_rent_3p_supply AND b.business_context = 'RENT'),
            FALSE
          ) THEN COALESCE(hl.is_3p_supply_5a, FALSE)
          ELSE FALSE
        END AS is_3p_supply_5a,
        CASE
          WHEN COALESCE(
            (hl.is_sale_3p_supply AND b.business_context = 'SALE')
            OR (hl.is_rent_3p_supply AND b.business_context = 'RENT'),
            FALSE
          ) THEN COALESCE(hl.is_3p_supply_bh, FALSE)
          ELSE FALSE
        END AS is_3p_supply_bh,
        IF(fud.visit_type = 'VIDEO', TRUE, FALSE) AS is_virtual_visit,
        e.is_successful AS is_entrance_successful,
        (b.status = 'Cancelado') AS is_canceled,
        (b.business_context = 'SALE') AS is_sale_visit,
        (b.type = 'Vistoria') AS is_inspection,
        (b.type = 'Visita') AS is_visit,
        (b.type = 'SessaoFotos') AS is_photo_session,
        COALESCE(
            CASE
                -- Bookings migrated from Casa Mineira don't have a visit_fup
                WHEN vou.first_update_source = 'MIGRACAOCASAMINEIRA' THEN (b.status = 'Realizado')
                ELSE (COALESCE(b.visit_fup, fup_vsl.visit_fup) IN ('NaoGostou', 'Talvez', 'VaiNegociar', 'VisitouSozinho'))
            END,
            FALSE
        ) AS is_visit_completed,
        COALESCE(COALESCE(b.visit_fup, fup_vsl.visit_fup) IS NOT NULL AND vab.agent_absence_reason = 'Absent', FALSE) AS is_visit_performed,
        -- is a reschedule from another booking
        (b.id_rescheduled_booking IS NOT NULL) AS is_via_reschedule,
        -- was rescheduled to another booking
        (resc.id_rescheduled_from IS NOT NULL) AS has_reschedule,
        va.has_tenant_attended,
        va.has_agent_attended,
        va.has_landlord_attended,
        (e.problem <> 'LandlordNoShow') AS has_owner_arrived,
        CASE
            WHEN fba.id_user_creation = 194233 THEN True
            ELSE False
        END AS is_first_booking_auto,
        brh.is_house_rented,
        v_cin.ts_checkin
    FROM
        datalake_ebdb_clean.booking AS b
    LEFT JOIN
        visit_fup_vsl AS fup_vsl
            ON b.id = fup_vsl.id_schedule
    LEFT JOIN
        visit_origin_unified AS vou
            ON b.id_visit = vou.id_visit
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
    LEFT JOIN
        first_booking_author AS fba
      ON fba.id_booking = b.id
    LEFT JOIN
        visitor_fixed_agent AS vfa
            ON vfa.id_booking = b.id
    LEFT JOIN
        booking_in_rented_house AS brh
            ON brh.id = b.id
    LEFT JOIN
        booking_hub_agent AS bha
            ON bha.id = b.id
    LEFT JOIN
        datalake_visit.visit_business_model AS vbm
            ON b.id_visit = vbm.id_visit
    LEFT JOIN
        datalake_ebdb_clean.user AS ua
            ON ua.id_agent = b.id_agent
    LEFT JOIN
        datalake_hub_services.secretariat_hierarchy AS su
            ON su.id_user_5a = fba.id_user_creation
    LEFT JOIN
        datalake_ebdb_user.user AS u
            ON u.id = fba.id_user_creation
    LEFT JOIN
        datalake_ebdb_listing.house AS hl
            ON b.id_house = hl.id
    LEFT JOIN
        datalake_ebdb_clean.country AS ct
            ON ct.code = hl.country_code
    LEFT JOIN
        datalake_ebdb_clean.visit_checkin AS v_cin
            ON v_cin.id_visit = b.id_visit
    LEFT JOIN
        secretariat_on_visit_date AS sod
            ON sod.id = b.id
    LEFT JOIN
        last_secretariat AS ls
            ON ls.id = b.id
),
--CTE Cross channel
--This CTE is being created because for some reason this table was duplicated and consequently is duplicating the quantity of booking and disturbing some Fintech metrics. We are investigating this for now.
cross_channel AS (
  SELECT
    visit_code,
    event_name,
    final_attribution_app_type,
    final_attribution_media_source,
    final_attribution_source,
    final_attribution_medium,
    final_attribution_campaign,
    final_attribution_content,
    final_attribution_term,
    final_attribution_branded,
    final_attribution_origin
  FROM
    datalake_tracked_events.attribution_cross_channel
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY visit_code ORDER BY ts_event DESC) = 1
)
-- custom columns that need pre-calculated ones
SELECT
    bb.id,
    bb.id_country,
    bb.id_rescheduled_booking,
    bb.id_visitor,
    bb.id_visit,
    bb.id_user_creation,
    bb.id_user_cancelation,
    bb.id_house,
    bb.id_agent,
    bb.id_user_sale_agent,
    bb.id_attendant,
    bb.id_user_sale_attendence_5a,
    bb.id_user_secretariat_on_visit_date,
    bb.id_user_last_secretariat,
    bb.id_rent_flow,
    bb.id_sale_flow,
    bb.id_real_estate_agent_rating,
    bb.id_sale_fixed_agent,
    bb.id_company_supply,
    bb.uuid_company_supply,
    bb.id_company_demand,
    bb.is_3p_supply,
    bb.is_3p_demand,
    bb.is_3p_lead_gen,
    bb.has_3p_access_control,
    bb.id_schedule,
    bb.country_code,
    bb.default_timezone,
    bb.dt_booking,
    bb.status,
    bb.visit_intent,
    bb.buyer_intention,
    bb.type,
    bb.visit_fup,
    bb.checkin_code,
    bb.visit_checkin_status,
    bb.checkin_fail_reason,
    bb.checkin_fail_commentary,
    bb.slot_day,
    bb.checkin_status,
    bb.user_creation_email,
    bb.first_update_source,
    bb.code,
    bb.last_status_change_reason,
    bb.last_status_change_reason_enum,
    bb.last_status_change_reason_category,
    bb.tenant_absence_reason,
    bb.agent_absence_reason,
    bb.landlord_absence_reason,
    bb.troublesome_entrance_problem,
    bb.cancellation_reason,
    bb.cancellation_reason_category,
    bb.owner_missing_reason,
    bb.reason_category,
    bb.user_sale_booking_creator,
    bb.hub_agent_region,
    bb.partner_3p_demand,
    bb.partner_3p_supply,
    bb.ts_visit_fup,
    bb.ts_created,
    bb.ts_updated,
    bb.ts_first_canceled,
    bb.ts_first_canceled_unevaluated,
    bb.ts_booking_local_tz,
    bb.ts_created_local_tz,
    bb.ts_visit_follow_up_local_tz,
    bb.is_confirmed,
    bb.is_closed,
    bb.is_agent_fixed,
    bb.is_hub_flow,
    bb.is_3p_supply_5a,
    bb.is_3p_supply_bh,
    bb.is_virtual_visit,
    bb.is_entrance_successful,
    bb.is_canceled,
    bb.is_sale_visit,
    bb.is_inspection,
    bb.is_visit,
    bb.is_photo_session,
    bb.is_visit_completed,
    bb.is_visit_performed,
    bb.is_via_reschedule,
    bb.has_reschedule,
    bb.has_tenant_attended,
    bb.has_agent_attended,
    bb.has_landlord_attended,
    bb.has_owner_arrived,
    bb.is_first_booking_auto,
    bb.is_house_rented,
    bb.ts_checkin,
    TO_UTC_TIMESTAMP(bb.ts_booking_local_tz, default_timezone) AS ts_booking_utc,
    FROM_UTC_TIMESTAMP(bb.ts_first_canceled, default_timezone) AS ts_first_canceled_local_tz,
    FROM_UTC_TIMESTAMP(bb.ts_first_canceled_unevaluated, default_timezone) AS ts_first_canceled_unevaluated_local_tz,
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
    /*
    Attribution Rules, enriched with the new attribution and the old one.
    The new one starts in H2/2021.
    Using CASE WHEN instead of COALESCE to don't create strange combinations.
    */
    IF(acc.visit_code IS NOT NULL, acc.final_attribution_app_type, src.app_type) AS app_type,
    IF(acc.visit_code IS NOT NULL, COALESCE(acc.final_attribution_media_source, "Unknown"), COALESCE(src.media_source, "Unknown")) AS media_source,
    IF(acc.visit_code IS NOT NULL, acc.final_attribution_source, src.utm_source) AS utm_source,
    IF(acc.visit_code IS NOT NULL, acc.final_attribution_medium, src.utm_medium) AS utm_medium,
    IF(acc.visit_code IS NOT NULL, acc.final_attribution_campaign, src.utm_campaign) AS utm_campaign,
    IF(acc.visit_code IS NOT NULL, acc.final_attribution_content, src.utm_content) AS utm_content,
    IF(acc.visit_code IS NOT NULL, acc.final_attribution_term, src.utm_term) AS utm_term,
    IF(acc.visit_code IS NOT NULL, COALESCE(acc.final_attribution_branded, "Outro"), COALESCE(src.branded, "Outro")) AS branded,
    IF(acc.visit_code IS NOT NULL, acc.final_attribution_origin, 'old_attribution') AS final_attribution_origin,
    DATEDIFF(FROM_UTC_TIMESTAMP(bb.ts_first_canceled, default_timezone), bb.ts_created_local_tz) AS days_visit_booked_to_visit_cancelled,
    DATEDIFF(bb.ts_booking_local_tz, FROM_UTC_TIMESTAMP(bb.ts_first_canceled, default_timezone)) AS days_visit_cancelled_to_visit,
    DATEDIFF(bb.ts_booking_local_tz, bb.ts_created_local_tz) AS days_visit_booked_to_visit,
    IF(is_visit_completed, DATEDIFF(bb.ts_booking_local_tz, bb.ts_created_local_tz), NULL)
    AS days_visit_booked_to_visit_completed
FROM
    base_booking AS bb
LEFT JOIN
    datalake_ebdb_clean.visit AS v
        ON bb.id_visit = v.id
LEFT JOIN
    datalake_amplitude_visit.amplitude_visit AS src
        ON v.code = src.id_visit
LEFT JOIN
    cross_channel AS acc
        ON v.code = acc.visit_code
        AND acc.event_name IN ('visit_schedule_confirmed','debug_visit_schedule_confirmed')
