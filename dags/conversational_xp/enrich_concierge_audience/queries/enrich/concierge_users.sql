WITH visits as (

  SELECT
    id_visitor,
    id_house,
    business_context,
    COALESCE(code, '') AS visit_code,
    ts_visit_local_tz,
    CASE
      WHEN is_completed = TRUE THEN 1
      WHEN DATE(ts_visit_local_tz) >= current_date THEN 1
      ELSE 0
    END AS is_completed_or_scheduled_visit_today_or_future

  FROM datalake_visit.visits

  WHERE ts_visit_canceled IS NULL
    AND DATE(ts_visit_local_tz) >= DATE_SUB(current_date, 60)
),

visits_booked_for_tomorrow as(
  SELECT
    id_visitor,
    CASE WHEN COUNT(id_house) = 1 THEN 1 ELSE 0 END confirmed_1_visit,
    CASE WHEN COUNT(id_house) >= 2 THEN 1 ELSE 0 END confirmed_2_more_visit

  FROM visits

  WHERE DATE(ts_visit_local_tz) = DATE_ADD(current_date, 1)

  GROUP BY
    id_visitor
),

user_one_visit_house as (
  SELECT
    v.id_visitor as id_user,
    v.id_house,
    UPPER(v.business_context) as business_context,
    vbft.confirmed_1_visit,
    v.visit_code

  FROM visits v
  INNER JOIN visits_booked_for_tomorrow vbft
    ON v.id_visitor = vbft.id_visitor
    AND vbft.confirmed_1_visit = 1

  WHERE DATE(v.ts_visit_local_tz) = DATE_ADD(current_date, 1)

),

search_past_60_days as (
  (
    SELECT
      DISTINCT
        id_user,
        UPPER(business_context) AS business_context

    FROM datalake_amplitude_clean.170698_search_page_viewed_events

    WHERE
      make_date(year, month, day) >= DATE_SUB(current_date, 60)
      AND make_date(year, month, day) < current_date
  )
  UNION
  (
    SELECT
      DISTINCT
        id_user,
        UPPER(business_context) AS business_context

    FROM datalake_amplitude_clean.170698_search_results_page_viewed_events

    WHERE
      make_date(year, month, day) >= DATE_SUB(current_date, 60)
      AND make_date(year, month, day) < current_date
  )
),

users_bought_listing as (
  SELECT
    DISTINCT
      id_buyer

  FROM datalake_offer.sale_offer

  WHERE dt_sale_agreement_signed IS NOT NULL
    AND dt_offer_dismissed IS NULL
    AND id_buyer IS NOT NULL
),

agents as (
  SELECT
    uuid_person as id_person,
    persona
  from
    cdp_modeled_repo.tb_persona p
  where
    p.is_active AND
    p.persona = 'AGENT_BROKER'
),

base as (
  SELECT
    u.id_user,
    u.id_person as uuid_person,
    COALESCE(NULLIF(split(TRIM(u.user_name), ' ')[0], ''), 'colega') as user_first_name,
    spd.business_context,
    YEAR(current_date) AS year,
    MONTH(current_date) AS month,
    DAY(current_date) AS day,
    u.phone_number as phone_number

  FROM datalake_cdp.users u
  INNER JOIN search_past_60_days spd
    ON u.id_user = spd.id_user
  LEFT JOIN visits_booked_for_tomorrow vbft
    ON u.id_user = vbft.id_visitor
    AND COALESCE(vbft.confirmed_2_more_visit, 0) = 0
  LEFT JOIN users_bought_listing ubl
    ON u.id_user = ubl.id_buyer
  LEFT JOIN agents a
    ON u.id_person = a.id_person

  WHERE
    u.phone_number IS NOT NULL
    AND a.persona IS NULL
    AND ubl.id_buyer IS NULL

),

concierge_action_low AS (
  SELECT 'ConciergeLowIntent_presentation' AS action
  UNION ALL SELECT 'ConciergeLowIntent_variation1'
  UNION ALL SELECT 'ConciergeLowIntent_variation2'
  UNION ALL SELECT 'ConciergeTriggerQualifiedLowIntent_presentation'
  UNION ALL SELECT 'ConciergeTriggerQualifiedLowIntent_variation1'
  UNION ALL SELECT 'ConciergeTriggerQualifiedLowIntent_variation2'
),

concierge_action_med AS (
  SELECT 'ConciergeTriggerMediumIntent_v1_presentation' AS action
  UNION ALL SELECT 'ConciergeTriggerMediumIntent_v2_presentation'
  UNION ALL SELECT 'ConciergeTriggerMediumIntent_v3_presentation'
  UNION ALL SELECT 'ConciergeContactSubmissionClassifieds'
  UNION ALL SELECT 'ConciergeContactSubmissionClassifieds_presentation'
  UNION ALL SELECT 'ConciergeContactSubmissionTtc'
  UNION ALL SELECT 'ConciergeContactSubmissionTtc_presentation'
  UNION ALL SELECT 'ConciergeContactSubmissionTtcQaq_recs5_4t1q'
  UNION ALL SELECT 'ConciergeContactSubmissionTtcQaq_recs5_3t2q'
  UNION ALL SELECT 'ConciergeContactSubmissionTtcQaq_recs5_2t3q'
  UNION ALL SELECT 'ConciergeContactSubmissionTtcQaq_recs5_1t4q'
  UNION ALL SELECT 'ConciergeContactSubmissionTtcQaq_recs5_0t5q'
  UNION ALL SELECT 'ConciergeContactSubmissionTtcQaq_recs4_3t1q'
  UNION ALL SELECT 'ConciergeContactSubmissionTtcQaq_recs4_2t2q'
  UNION ALL SELECT 'ConciergeContactSubmissionTtcQaq_recs4_1t3q'
  UNION ALL SELECT 'ConciergeContactSubmissionTtcQaq_recs4_0t4q'
  UNION ALL SELECT 'ConciergeContactSubmissionTtcQaq_recs3_2t1q'
  UNION ALL SELECT 'ConciergeContactSubmissionTtcQaq_recs3_1t2q'
  UNION ALL SELECT 'ConciergeContactSubmissionTtcQaq_recs3_0t3q'
  -- TODO add new template names for FUP and new MediumIntent variation
),

concierge_action_high AS (
  SELECT 'ConciergeHighIntent_presentation_recs1' AS action
  UNION ALL SELECT 'ConciergeHighIntent_presentation_recs2'
  UNION ALL SELECT 'ConciergeHighIntent_variation1_recs1'
  UNION ALL SELECT 'ConciergeHighIntent_variation1_recs2'
  UNION ALL SELECT 'ConciergeHighIntent_variation2_recs1'
  UNION ALL SELECT 'ConciergeHighIntent_variation2_recs2'
),

concierge_action_whatsapp AS (
  SELECT action FROM concierge_action_low
  UNION ALL
  SELECT action FROM concierge_action_med
  UNION ALL
  SELECT action FROM concierge_action_high
),

jaiminho as (
  SELECT
    id_user,
    MAX(CASE WHEN TO_DATE(ts_sent) > DATE_SUB(current_date, 7)
        AND action IN (SELECT action FROM concierge_action_low)
        THEN 1 ELSE 0 END) received_low_msg_7_days,
    MAX(CASE WHEN TO_DATE(ts_sent) > DATE_SUB(current_date, 7)
        AND action IN (SELECT action FROM concierge_action_med)
        THEN 1 ELSE 0 END) received_med_msg_7_days,
    MAX(CASE WHEN TO_DATE(ts_sent) > DATE_SUB(current_date, 7)
        AND action IN (SELECT action FROM concierge_action_high)
        THEN 1 ELSE 0 END) received_high_msg_7_days,
    SUM(CASE WHEN action IN (SELECT action FROM concierge_action_low)
        THEN 1 ELSE 0 END) low_notifications,
    SUM(CASE WHEN action IN (SELECT action FROM concierge_action_med)
        THEN 1 ELSE 0 END) med_notifications,
    SUM(CASE WHEN action IN (SELECT action FROM concierge_action_high)
        THEN 1 ELSE 0 END) high_notifications

  FROM datalake_jaiminho_clean.user_notifications

  WHERE UPPER(channel) = 'WHATSAPP'
    AND UPPER(status) IN ('READ', 'SENT', 'DELIVERED')
    AND action IN (SELECT action FROM concierge_action_whatsapp)

  GROUP BY
    id_user
),

listing_page_view_events_past_days as (

  SELECT
    id_event,
    id_user,
    event_properties,
    year,
    month,
    day
  FROM datalake_amplitude_clean.170698_listing_page_viewed_events
  WHERE make_date(year, month, day) >= DATE_SUB(current_date, 28)

),

concierge_lpv_event as (

  SELECT
    DISTINCT id_user,
    1 AS concierge_lpv

  FROM listing_page_view_events_past_days
  WHERE get_json_object(event_properties, '$.recset_showcase') = 'CONCIERGE_WHATSAPP'
  GROUP BY id_user

),

listing_page_3_more AS (
  SELECT
    id_user,
    get_json_object(event_properties, '$.house_id') AS id_house,
    UPPER(get_json_object(event_properties, '$.business_context')) AS business_context,
    COUNT(DISTINCT id_event) as distinct_lpv_events

  FROM listing_page_view_events_past_days

  WHERE
    make_date(year, month, day) >= DATE_SUB(current_date, 3)
    AND make_date(year, month, day) < current_date
    AND id_user IS NOT NULL
    AND NOT COALESCE(
      ARRAY_CONTAINS(
        FROM_JSON(get_json_object(event_properties, '$.house_tags'), 'ARRAY<STRING>'),
        'rentOnTermination'
      ),
      FALSE
    )

  GROUP BY
    id_user,
    get_json_object(event_properties, '$.house_id'),
    UPPER(get_json_object(event_properties, '$.business_context'))

  HAVING COUNT(DISTINCT id_event) >= 3
),

favourite_schedule_lpv_offer_events_all as (
  (
    SELECT
      DISTINCT
        id_user,
        id_house,
        business_context,
        0 AS intent_source

    FROM listing_page_3_more
  )
  UNION
  (
    SELECT
      DISTINCT
        id_user,
        ep_house_id AS id_house,
        UPPER(business_context) AS business_context,
        1 AS intent_source

    FROM datalake_amplitude_clean.170698_listing_favorite_set_events

    WHERE
      make_date(year, month, day) >= DATE_SUB(current_date, 1)
      AND make_date(year, month, day) < current_date
      AND id_user IS NOT NULL
  )
  UNION
  (
    SELECT
      DISTINCT
        id_user,
        get_json_object(event_properties, '$.house_id') AS id_house,
        UPPER(get_json_object(event_properties, '$.business_context')) AS business_context,
        2 AS intent_source  -- SCHEDULE_PAGE_VIEWED

    FROM datalake_amplitude_clean.170698_schedule_page_viewed_events

    WHERE
      make_date(year, month, day) >= DATE_SUB(current_date, 1)
      AND make_date(year, month, day) < current_date
      AND id_user IS NOT NULL
  )
  UNION
  (
    SELECT
      rent_flow_latest.id_tenant_prospect AS id_user,
      rent_flow_latest.id_house AS id_house,
      UPPER('RENT') AS business_context,
      3 AS intent_source  -- DIRECT_OFFER: highest priority so it always wins the tie-break below

    FROM (
      SELECT
        rf.id_tenant_prospect,
        rf.id_house,
        ROW_NUMBER() OVER (
          PARTITION BY rf.id_tenant_prospect
          ORDER BY rf.ts_offer_submitted DESC
        ) AS rn
      FROM datalake_rent_flows.rent_flows AS rf
      WHERE
        rf.ts_offer_submitted IS NOT NULL
        AND DATE(rf.ts_offer_submitted) >= DATE_SUB(current_date, 1)
        AND DATE(rf.ts_offer_submitted) < current_date
    ) AS rent_flow_latest
    WHERE rent_flow_latest.rn = 1
  )
),

favourite_schedule_lpv_events AS (
  SELECT
    ranked.id_user,
    ranked.id_house,
    ranked.business_context,
    ranked.favourited_scheduled_lpv,
    ranked.intent_source
  FROM (
    SELECT
      fslea.id_user,
      fslea.id_house,
      fslea.business_context,
      1 AS favourited_scheduled_lpv,
      fslea.intent_source,
      ROW_NUMBER() OVER (
        PARTITION BY fslea.id_user
        ORDER BY fslea.intent_source DESC
      ) AS rn
    FROM favourite_schedule_lpv_offer_events_all AS fslea
    LEFT JOIN visits AS v
      ON fslea.id_user = v.id_visitor
      AND fslea.id_house = v.id_house
      AND v.is_completed_or_scheduled_visit_today_or_future = 1
    WHERE
      v.id_visitor IS NULL
      AND v.id_house IS NULL
  ) AS ranked
  WHERE ranked.rn = 1
),

latest_search_profile_filter_rows as (
  SELECT
    spf.*,
    ROW_NUMBER() OVER (PARTITION BY spf.id_search_profile ORDER BY spf.ts_updated DESC) AS rn_filter
  FROM datalake_house_listing_search_clean.search_profile_filters AS spf
),

search_cluster as (
  SELECT
    TRY_CAST(sp.id_profile_holder AS BIGINT) AS id_user,
    UPPER(TRIM(sp.business_context)) AS business_context,
    lf.events_count AS cluster_events,
    lf.ts_updated AS last_search_date,
    lf.events_count >= 10 AS has_qualified_search_cluster

  FROM latest_search_profile_filter_rows AS lf
  INNER JOIN datalake_house_listing_search_clean.search_profile AS sp
    ON lf.id_search_profile = sp.id

  WHERE lf.rn_filter = 1
    AND TRY_CAST(sp.id_profile_holder AS BIGINT) IS NOT NULL
    AND sp.profile_holder_type = 'USER'
    AND (
      (
        UPPER(TRIM(sp.business_context)) = 'RENT'
        AND UPPER(TRIM(get_json_object(lf.filters_json, '$.cost.costType'))) = 'RENT_PRICE'
      )
      OR (
        UPPER(TRIM(sp.business_context)) = 'SALE'
        AND UPPER(TRIM(get_json_object(lf.filters_json, '$.cost.costType'))) = 'SALE_PRICE'
      )
    )
),

top_cluster AS (
  SELECT
    ranked.id_user,
    ranked.business_context,
    ranked.has_qualified_search_cluster
  FROM (
    SELECT
      id_user,
      UPPER(business_context) AS business_context,
      has_qualified_search_cluster,
      ROW_NUMBER() OVER (
        PARTITION BY id_user
        ORDER BY cluster_events DESC, last_search_date DESC, business_context
      ) AS rn
    FROM search_cluster
  ) AS ranked
  WHERE ranked.rn = 1
),

owners_with_listings as (

  SELECT
    DISTINCT h.id_user AS id_user,
    hls.id_house AS id_house
  FROM
    datalake_ebdb_listing.house_listing_status AS hls
  INNER JOIN
    datalake_ebdb_listing.house AS h
      ON hls.id_house = h.id

  UNION

  SELECT
    DISTINCT h.id_user AS id_user,
    sl.id_house AS id_house
  FROM
    datalake_sale_listings.sale_listing AS sl
  INNER JOIN
    datalake_ebdb_listing.house AS h
      ON sl.id_house = h.id

),

owner_with_valid_listings as (

  SELECT
    DISTINCT owl.id_user
  FROM owners_with_listings owl
  INNER JOIN datalake_ebdb_clean.listing_business_context lbc
    ON owl.id_house = lbc.id_house
    AND lbc.status IN ('PUBLISHED', 'SUSPENDED')

),

user_respond_concierge as (

  SELECT
    DISTINCT s.id_user AS id_user,
    1 AS concierge_response
  FROM datalake_copilot_service_clean.message AS m
  INNER JOIN datalake_copilot_service_clean.session AS s
    ON m.id_session = s.id
  WHERE m.channel = 'WHATSAPP_CONCIERGE_CHAT'
    AND m.role = 'HUMAN'
    AND DATE(m.ts_created) >= DATE_SUB(current_date, 28)

),

user_snooze_status as (
        SELECT
            id_external as id_user,
            purpose_acceptance.status as snooze_status,
            purpose_acceptance.updatedAt as updated_at
        FROM (
            SELECT
                id_external,
                from_json(purpose_acceptances, 'ARRAY<STRUCT<alias: STRING, status: STRING, purpose: INT, version: STRING, document: STRING, updatedAt: TIMESTAMP>>') AS purpose_acceptances_struct
            FROM datalake_privacy_hub_clean.data_subject
            WHERE CONTAINS(purpose_acceptances, 'SNOOZE_CONCIERGE')
            )
            LATERAL VIEW EXPLODE(purpose_acceptances_struct) AS purpose_acceptance
        WHERE purpose_acceptance.alias = 'SNOOZE_CONCIERGE'
),

search_since_snooze as  (
        SELECT
            id_user,
            count(distinct id_session) as searches_since
        FROM (
                SELECT
                    uss.id_user,
                    spve.id_session
                FROM user_snooze_status uss
                LEFT JOIN datalake_amplitude_clean.170698_search_page_viewed_events spve
                    ON uss.id_user=spve.id_user
                WHERE
                  make_date(spve.year, spve.month, spve.day) >= uss.updated_at
                  AND make_date(spve.year, spve.month, spve.day) < current_date
                UNION
                SELECT
                    uss.id_user,
                    srpve.id_session
                FROM user_snooze_status uss
                LEFT JOIN datalake_amplitude_clean.170698_search_results_page_viewed_events srpve
                    ON uss.id_user=srpve.id_user
                WHERE
                  make_date(srpve.year, srpve.month, srpve.day) >= uss.updated_at
                  AND make_date(srpve.year, srpve.month, srpve.day) < current_date
        )
        GROUP BY id_user
),

blocked_users as (
  SELECT
    id_user,
    count(*) as blocked_notifications
  FROM datalake_jaiminho_clean.user_notifications
  WHERE
    datediff(current_date, make_date(year, month, day)) <= 180
    AND error_code in (21002, 21004, 21007)
  GROUP BY id_user
),

concierge_users AS (

SELECT
  ranked.id_user,
  ranked.id_house,
  ranked.user_first_name,
  ranked.user_phone,
  ranked.business_context,
  ranked.visit_code,
  ranked.snooze_status,
  ranked.intent,
  ranked.reason,
  ranked.medium_intent_reason,
  ranked.searches_since,
  ranked.low_notifications,
  ranked.notification_count,
  ranked.is_confirmed_1_visit,
  ranked.is_received_low_msg_7_days,
  ranked.is_received_med_msg_7_days,
  ranked.is_received_high_msg_7_days,
  ranked.is_favourited_scheduled_lpv,
  ranked.is_concierge_response,
  ranked.is_concierge_lpv,
  ranked.has_top_cluster,
  ranked.has_qualified_search_cluster,
  ranked.is_first_notification,
  ranked.ts_created,
  ranked.year,
  ranked.month,
  ranked.day
FROM (
SELECT
  b.id_user,
  CASE
    WHEN uovh.confirmed_1_visit = 1 THEN uovh.id_house
    WHEN fsle.favourited_scheduled_lpv = 1 THEN fsle.id_house
    ELSE NULL
  END AS id_house,
  b.user_first_name,
  b.phone_number AS user_phone,
  b.business_context,
  uovh.visit_code,
  uss.snooze_status,
  CASE WHEN
    tc.id_user IS NULL THEN 0
    ELSE 1
  END AS has_top_cluster,
  COALESCE(tc.has_qualified_search_cluster, FALSE) AS has_qualified_search_cluster,
  CASE
    WHEN uss.snooze_status = 'ACTIVE' THEN 'NOT_CLASSIFIED'
    WHEN j.received_high_msg_7_days = 1 THEN 'NOT_CLASSIFIED'
    WHEN uovh.confirmed_1_visit = 1 THEN 'HIGH'
    WHEN j.received_med_msg_7_days = 1 THEN 'NOT_CLASSIFIED'
    WHEN fsle.favourited_scheduled_lpv = 1 THEN 'MEDIUM'
    WHEN j.received_low_msg_7_days = 1 THEN 'NOT_CLASSIFIED'
    WHEN j.low_notifications >= 4 AND COALESCE(urc.concierge_response, 0) = 0 AND COALESCE(cle.concierge_lpv, 0) = 0 THEN 'NOT_CLASSIFIED'
    WHEN uss.snooze_status = 'EXPIRED' AND sss.searches_since < 10 THEN 'NOT_CLASSIFIED'
    WHEN has_top_cluster = 1 THEN 'LOW'
    ELSE 'LOW'
    END AS intent,
  CASE
    WHEN uss.snooze_status = 'ACTIVE' THEN 'SNOOZE'
    WHEN j.received_high_msg_7_days = 1 THEN 'HIGH_INTENT_MSG_RECEIVED'
    WHEN uovh.confirmed_1_visit = 1 THEN 'MEETS_CONDITIONS'
    WHEN j.received_med_msg_7_days = 1 THEN 'MED_INTENT_MSG_RECEIVED'
    WHEN fsle.favourited_scheduled_lpv = 1 THEN 'MEETS_CONDITIONS'
    WHEN j.received_low_msg_7_days = 1 THEN 'LOW_INTENT_MSG_RECEIVED'
    WHEN j.low_notifications >= 4 AND COALESCE(urc.concierge_response, 0) = 0 AND COALESCE(cle.concierge_lpv, 0) = 0 THEN 'REPETITION_CONTROL'
    WHEN has_top_cluster = 1 THEN 'MEETS_CONDITIONS'
    WHEN uss.snooze_status = 'EXPIRED' AND sss.searches_since < 10 THEN 'LOW_SEARCHES_AFTER_SNOOZE'
    ELSE 'CATCH_ALL'
    END AS reason,
  CASE
    WHEN uss.snooze_status = 'ACTIVE' THEN NULL
    WHEN j.received_high_msg_7_days = 1 THEN NULL
    WHEN uovh.confirmed_1_visit = 1 THEN NULL
    WHEN j.received_med_msg_7_days = 1 THEN NULL
    WHEN fsle.favourited_scheduled_lpv = 1 THEN
      CASE fsle.intent_source
        WHEN 3 THEN 'DIRECT_OFFER'
        WHEN 2 THEN 'SCHEDULE_PAGE_VIEWED'
        WHEN 1 THEN 'FAVORITED_LISTING'
        WHEN 0 THEN 'THREE_PLUS_LPV'
        ELSE NULL
      END
    ELSE NULL
  END AS medium_intent_reason,
  sss.searches_since,
  j.low_notifications,
  CASE
    WHEN j.received_high_msg_7_days = 1 THEN NULL
    WHEN uovh.confirmed_1_visit = 1 THEN COALESCE(j.high_notifications,0)
    WHEN j.received_med_msg_7_days = 1 THEN NULL
    WHEN fsle.favourited_scheduled_lpv = 1 THEN COALESCE(j.med_notifications,0)
    WHEN j.received_low_msg_7_days = 1 THEN NULL
    WHEN j.low_notifications >= 4 AND COALESCE(urc.concierge_response, 0) = 0 AND COALESCE(cle.concierge_lpv, 0) = 0 THEN NULL
    WHEN has_top_cluster = 1 THEN COALESCE(j.low_notifications,0)
    ELSE COALESCE(j.low_notifications, 0)
    END AS notification_count,
  uovh.confirmed_1_visit AS is_confirmed_1_visit,
  j.received_low_msg_7_days AS is_received_low_msg_7_days,
  j.received_med_msg_7_days AS is_received_med_msg_7_days,
  j.received_high_msg_7_days AS is_received_high_msg_7_days,
  fsle.favourited_scheduled_lpv AS is_favourited_scheduled_lpv,
  urc.concierge_response AS is_concierge_response,
  cle.concierge_lpv AS is_concierge_lpv,
  CASE WHEN
    COALESCE(j.low_notifications, 0)+COALESCE(j.med_notifications, 0)+COALESCE(j.high_notifications, 0) > 0 THEN False
    ELSE True
  END AS is_first_notification,
  current_timestamp() AS ts_created,
  b.year,
  b.month,
  b.day,
  ROW_NUMBER() OVER (
    PARTITION BY b.id_user
    ORDER BY
      uovh.confirmed_1_visit DESC,
      fsle.favourited_scheduled_lpv DESC,
      CASE WHEN tc.id_user IS NULL THEN 0 ELSE 1 END DESC,
      b.business_context ASC
  ) AS rn

FROM base b
LEFT JOIN datalake_ebdb_clean.contract as c
  ON b.id_user = c.id_user
  AND UPPER(c.status) = 'ATIVO'
  AND c.ts_expected_termination IS NULL
LEFT JOIN user_one_visit_house uovh
  ON uovh.id_user=b.id_user
  AND UPPER(b.business_context)=UPPER(uovh.business_context)
LEFT JOIN jaiminho j
  ON b.id_user = j.id_user
LEFT JOIN favourite_schedule_lpv_events fsle
  ON b.id_user = fsle.id_user
  AND UPPER(b.business_context)=UPPER(fsle.business_context)
LEFT JOIN top_cluster tc
  ON b.id_user = tc.id_user
  AND UPPER(b.business_context)=UPPER(tc.business_context)
LEFT JOIN owner_with_valid_listings owvl
  ON b.id_user = owvl.id_user
LEFT JOIN user_respond_concierge urc
  ON b.id_user = urc.id_user
LEFT JOIN concierge_lpv_event cle
  ON b.id_user = cle.id_user
LEFT JOIN user_snooze_status uss
  ON b.id_user = uss.id_user
LEFT JOIN search_since_snooze sss
  ON b.id_user = sss.id_user
LEFT JOIN blocked_users bu
  ON b.id_user = bu.id_user
LEFT JOIN datalake_rede_platform_clean.buyer_company bc
  ON bc.uuid_person = b.uuid_person
  AND bc.is_active
  AND bc.type = '3P'
WHERE NOT (
  UPPER(tc.business_context) = 'RENT'
  AND c.id_user IS NOT NULL
)
  AND b.business_context IS NOT NULL
  AND (
    owvl.id_user IS NULL
    OR (COALESCE(j.received_high_msg_7_days, 0) = 0 AND uovh.confirmed_1_visit = 1)
  )
  AND COALESCE(bu.blocked_notifications, 0) <= 0
  AND bc.uuid_person IS NULL
) AS ranked
WHERE ranked.rn = 1
)

SELECT
  id_user,
  id_house,
  user_first_name,
  user_phone,
  business_context,
  visit_code,
  snooze_status,
  intent,
  reason,
  medium_intent_reason,
  searches_since,
  low_notifications,
  notification_count,
  is_confirmed_1_visit,
  is_received_low_msg_7_days,
  is_received_med_msg_7_days,
  is_received_high_msg_7_days,
  is_favourited_scheduled_lpv,
  is_concierge_response,
  is_concierge_lpv,
  has_top_cluster,
  has_qualified_search_cluster,
  is_first_notification,
  ts_created,
  year,
  month,
  day
FROM
  concierge_users