WITH listing_events AS (
  SELECT
    id_house AS id_entity,
    id_listing_business_context AS id_source,
    ure.id_user AS id_user_registrant,
    rev,
    business_context,
    status,
    'LBC' AS source,
    'FIRST_LISTING' AS step,
    1 AS weight,
    CAST(FROM_UNIXTIME(ure.ts_revision / 1000) AS TIMESTAMP) AS ts_event
  FROM
    datalake_ebdb_clean.listing_business_context_aud AS lbc
  JOIN datalake_ebdb_clean.user_revision_entity AS ure 
    ON lbc.rev = ure.id
  WHERE status = 'PUBLISHED'
  UNION ALL
  SELECT 
    had.id_house AS id_entity,
    NULL AS id_source,
    ure.id_user AS id_user_registrant,
    had.rev AS rev,
    'RENT' AS business_context,
    had.status,
    'HOUSE_AUD' AS source,
    'FIRST_LISTING' AS step,
    1 AS weight,
    FROM_UNIXTIME(ure.ts_revision / 1000) AS ts_event
  FROM
    datalake_ebdb_clean.house_aud AS had
  JOIN datalake_ebdb_clean.user_revision_entity AS ure 
    ON (had.rev = ure.id)
  WHERE status = 'publicado'
    AND had.is_for_rent IS TRUE
    AND FROM_UNIXTIME(ure.ts_revision / 1000) <= '2020-01-07'
),
opp_events AS (
  SELECT
    id_house AS id_entity,
    id_photographer_job AS id_source,
    ure.id_user AS id_user_registrant,
    rev,
    EXPLODE(ARRAY('RENT', 'SALE')) AS business_context,
    status,
    'PJ' AS source,
    'OPPORTUNITY' AS step,
    2 AS weight,
    COALESCE(
      CAST(FROM_UNIXTIME(ure.ts_revision / 1000) AS TIMESTAMP),
      ts_photo_job_requested,
      ts_scheduled,
      ts_session_started,
      ts_photos_uploaded
    ) AS ts_event
  FROM
    datalake_ebdb_clean.photographer_job_aud AS pj
  JOIN datalake_ebdb_clean.user_revision_entity AS ure 
    ON pj.rev = ure.id
),
qualified_events AS (
    SELECT 
        hda.id_house AS id_entity,
        hda.id_draft AS id_source,
        id_user_registrant,
        CAST(-1 AS BIGINT) AS rev,
        hda.business_context,
        hda.status,
        'BOB' AS source,
        -- Useful for explode in two events
        EXPLODE(ARRAY('QUALIFIED', 'AV_QUALIFIED')) AS step, 
        3 AS weight,
        hda.ts_created AS ts_event
    FROM datalake_bob.house_draft_business_context AS hda
    WHERE hda.id_house IS NOT NULL
),
all_events AS (
  SELECT *
  FROM listing_events
  UNION ALL
  SELECT *
  FROM opp_events
  UNION ALL
  SELECT *
  FROM qualified_events
),
conversion_lookup AS (
  SELECT 
    id_lead, 
    id_house, 
    supply_source, 
    business_context
  FROM datalake_supply_flows.conversion_lookup
  GROUP BY ALL
),
events_and_discards AS (
  SELECT 
    al.id_entity,
    al.id_source,
    al.id_user_registrant,
    cl.id_lead,
    cl.supply_source,
    al.rev,
    al.business_context,
    al.status,
    al.source,
    al.step,
    al.weight,
    CAST(NULL AS STRING) as reason, 
    CAST(NULL AS STRING) as drop_step, 
    al.ts_event
  FROM all_events AS al
  LEFT JOIN conversion_lookup AS cl
    ON (al.id_entity = cl.id_house)
      AND (al.business_context = cl.business_context)
  UNION ALL
  SELECT 
    id_entity,
    id_source,
    id_user_registrant,
    id_lead,
    '1P' AS supply_source,
    rev,
    business_context,
    status,
    source,
    step,
    weight,
    reason,
    drop_step,
    ts_event
  FROM datalake_supply_flows.prospects_events
)

SELECT *
FROM events_and_discards
WHERE id_entity IS NOT NULL