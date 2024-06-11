WITH fl_events AS(
  SELECT
    id_lead,
    id_entity,
    id_user_registrant,
    business_context,
    supply_source,
    step,
    weight,
    ts_event,
    rev
  FROM
    datalake_supply_flows.conversion_staging
  WHERE
    step = 'FIRST_LISTING' 
  QUALIFY ROW_NUMBER() OVER (PARTITION BY id_entity, business_context ORDER BY rev, ts_event) = 1 -- First Listing Event
),
opp_events AS (
  SELECT
    id_lead,
    id_entity,
    id_user_registrant,
    business_context,
    supply_source,
    step,
    weight,
    ts_event,
    rev
  FROM
    datalake_supply_flows.conversion_staging
  WHERE
    step = 'OPPORTUNITY'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY id_entity, business_context ORDER BY rev, ts_event) = 1 -- First Opp Event
),
bob_events AS (
  SELECT
    id_lead,
    id_entity,
    business_context,
    ts_event AS ts_event_qualified
  FROM
    datalake_supply_flows.conversion_staging
  WHERE
    step = 'QUALIFIED'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY id_entity, business_context ORDER BY rev, ts_event) = 1

),
lbc_editing_events AS (
  -- Some events are not being captured by the conversion_staging table, so we need to get them from the listing_business_context_aud table
  SELECT
    lbca.id_house AS id_entity,
    lbca.business_context,
    FROM_UNIXTIME(ure.ts_revision / 1000) AS ts_event
  FROM
    datalake_ebdb_clean.listing_business_context_aud as lbca
  JOIN 
    datalake_ebdb_clean.user_revision_entity AS ure 
      ON lbca.rev = ure.id
  WHERE
    lbca.status = 'EDITING' 
  QUALIFY ROW_NUMBER() OVER (PARTITION BY lbca.id_house, lbca.business_context ORDER BY ure.ts_revision) = 1
),
3p_events AS (
  SELECT 
    id_lead, 
    business_context,
    supply_source
  FROM datalake_supply_flows.conversion_events_3p
  GROUP BY ALL
),
discards_events_aq2o AS (
  SELECT 
    id_lead,
    id_entity,
    business_context,
    step,
    rev,
    reason,
    ts_event,
    MIN(ts_event) OVER (PARTITION BY id_entity, business_context) AS ts_first_discard,
    MAX(ts_event) OVER (PARTITION BY id_entity, business_context) AS ts_last_discard
  FROM
    datalake_supply_flows.conversion_staging
  WHERE 
    step = 'PROSPECT' AND (drop_step = 'AQ2O') -- Only AQ20 events
  QUALIFY ROW_NUMBER() OVER (PARTITION BY id_entity, business_context ORDER BY rev, ts_event DESC) = 1 -- The last drop AQ2O
),
-- FIRST LISTING EVENTS
t1 AS (
  SELECT
    id_lead,
    id_entity,
    id_user_registrant,
    business_context,
    supply_source,
    step,
    weight,
    ts_event AS ts_event_original,
    ts_event AS ts_event_adjusted,
    rev,
    'conversion_o2fl' AS business_event,
    CAST(NULL AS STRING) AS reason,
    'T1.0' AS aux_group,
    FALSE AS aux_data_event
  FROM
    fl_events
),
-- OPPORTUNITY EVENTS
opp_ongoing AS (
  SELECT
    opp.id_lead,
    opp.id_entity,
    opp.id_user_registrant,
    opp.business_context,
    opp.supply_source,
    opp.step,
    opp.weight,
    opp.ts_event AS ts_event_original,
    TIMESTAMPADD(DAY, scs.ongoing_window, opp.ts_event) AS ts_ongoing, -- This window was setup in config table
    opp.ts_event AS ts_event_adjusted, -- The minor data between the event and the first listing
    opp.rev,
    scs.ongoing_window
  FROM
    opp_events AS opp
  JOIN 
    bob_events AS qual -- PEGO TODOS QUE TEM EVENTOS NO QUALIFIED
      USING (id_entity, business_context)
  LEFT ANTI JOIN 
    fl_events AS fl -- FILTRO SOMENTE OS QUE NÃO TEM EVENTOS DE FIRST LISTING 
      USING (id_entity, business_context)
  LEFT JOIN 
    datalake_supply_flows.supply_conversion_settings AS scs
      USING (step)
),
t2_0 AS (
    SELECT
      cs.id_lead,
      id_entity,
      cs.id_user_registrant,
      business_context,
      cs.supply_source,
      cs.step,
      cs.weight,
      cs.ts_event AS ts_event_original,
      LEAST(cs.ts_event, fl.ts_event) AS ts_event_adjusted,
      cs.rev,
      'conversion_aq2o' AS business_event,
      CAST(NULL AS STRING) AS reason,
      'T2.0' AS aux_group,
      FALSE AS aux_data_event
    FROM
      opp_events AS cs
    JOIN 
      fl_events AS fl -- Cases with listing
        USING (id_entity, business_context) -- We had some cases that don't have leads, so I brought by id_house + context
    QUALIFY ROW_NUMBER() OVER (PARTITION BY id_entity, business_context ORDER BY cs.rev, cs.ts_event) = 1
),
t2_1 AS (
  SELECT 
      id_lead,
      id_entity,
      id_user_registrant,
      business_context,
      supply_source,
      step,
      weight,
      ts_event_original,
      ts_ongoing AS ts_event_adjusted,
      rev,
      EXPLODE(ARRAY('drop_o2fl','conversion_aq2o'))  AS business_event,
      CONCAT('MORE_THAN_', ongoing_window, '_DAYS_ON_STATUS') AS reason,
      'T2.1' AS aux_group,
      TRUE AS aux_data_event
  FROM 
    opp_ongoing
  WHERE
    ts_ongoing <= CURRENT_TIMESTAMP() -- Expired events based on window
),
t2_2 AS (
  SELECT 
      id_lead,
      id_entity,
      id_user_registrant,
      business_context,
      supply_source,
      step,
      weight,
      ts_event_original,
      ts_event_adjusted,
      rev,
      EXPLODE(ARRAY('ongoing_o2fl','conversion_aq2o')) AS business_event,
      CAST(NULL AS STRING) AS reason,
      'T2.2' AS aux_group,
      TRUE AS aux_data_event
  FROM 
    opp_ongoing
  WHERE 
    ts_ongoing > CURRENT_TIMESTAMP() -- Events that are still ongoing
),
t2_3 AS (
  SELECT
    cs.id_lead,
    id_entity,
    cs.id_user_registrant,
    ee.business_context,
    cs.supply_source,
    cs.step,
    cs.weight,
    cs.ts_event AS ts_event_original,
    cs.ts_event AS ts_event_adjusted,
    cs.rev,
    'conversion_aq2o' AS business_event,
    CAST(NULL AS STRING) AS reason,
    'T2.3' AS aux_group,
    FALSE AS aux_data_event
  FROM
    opp_events AS cs
  INNER JOIN lbc_editing_events AS ee -- Edited house into LBC
    USING (id_entity, business_context)
  LEFT ANTI JOIN fl_events AS fl -- Removing listed houses
    USING (id_entity, business_context)
  LEFT ANTI JOIN bob_events AS fl -- Removing bob houses
    USING (id_entity, business_context)
),
t2 AS (
  SELECT *
  FROM t2_0
  UNION ALL
  SELECT *
  FROM t2_1
  UNION ALL
  SELECT *
  FROM t2_2
  UNION ALL
  SELECT *
  FROM t2_3
),
ongoing_aq2o AS (
  SELECT
    qual.id_lead,
    qual.id_entity,
    qual.id_user_registrant,
    qual.business_context,
    qual.supply_source,
    qual.step,
    qual.weight,
    qual.rev,
    d.reason,
    qual.ts_event AS ts_event_original,
    TIMESTAMPADD(DAY, scs.ongoing_window, qual.ts_event) AS ts_ongoing,
    d.ts_event AS ts_event_discard,
    d.ts_first_discard,
    d.ts_last_discard,
    scs.ongoing_window
  FROM
    datalake_supply_flows.conversion_staging AS qual
  LEFT ANTI JOIN
    opp_events AS opp
      USING (id_entity, business_context)
  LEFT ANTI JOIN 
    fl_events AS fl
      USING (id_entity, business_context)
  LEFT JOIN 
    datalake_supply_flows.supply_conversion_settings AS scs
      USING (step)
  LEFT JOIN 
    discards_events_aq2o AS d
      USING (id_lead, business_context)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY qual.id_entity, qual.business_context, qual.step ORDER BY qual.rev, qual.ts_event) = 1
),
-- QUALIFIED EVENTS
t3_0 AS (
  SELECT
    qual.id_lead,
    qual.id_entity,
    qual.id_user_registrant,
    qual.business_context,
    qual.supply_source,
    qual.step,
    qual.weight,
    qual.ts_event AS ts_event_original,
    LEAST(qual.ts_event, opp.ts_event) AS ts_event_adjusted,
    NULL AS ts_first_discard,
    NULL AS ts_last_discard,
    qual.rev,
    'conversion_q2aq' AS business_event,
    qual.reason,
    'T3.0' AS aux_group,
    FALSE AS aux_data_event
  FROM
    datalake_supply_flows.conversion_staging AS qual
  LEFT JOIN 
    opp_events AS opp
      USING (id_entity, business_context)
  WHERE
    qual.step = 'AV_QUALIFIED'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY qual.id_entity, qual.business_context ORDER BY qual.rev, qual.ts_event) = 1 -- PRIMEIRA CONVERSÃO Q/AQ
  UNION ALL
  SELECT
    qual.id_lead,
    qual.id_entity,
    qual.id_user_registrant,
    qual.business_context,
    qual.supply_source,
    qual.step,
    qual.weight,
    qual.ts_event AS ts_event_original,
    LEAST(qual.ts_event, opp.ts_event) AS ts_event_adjusted,
    NULL AS ts_first_discard,
    NULL AS ts_last_discard,
    qual.rev,
    'conversion_p2q' AS business_event,
    qual.reason,
    'T3.0' AS aux_group,
    FALSE AS aux_data_event
  FROM
    datalake_supply_flows.conversion_staging AS qual
  LEFT JOIN 
    opp_events AS opp
      USING (id_entity, business_context)
  WHERE
    qual.step = 'QUALIFIED'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY qual.id_entity, qual.business_context ORDER BY qual.rev, qual.ts_event) = 1 -- PRIMEIRA CONVERSÃO Q/AQ
),
t3_1 AS (
  -- DROP AQ2O
  SELECT 
      id_lead,
      id_entity,
      id_user_registrant,
      business_context,
      supply_source,
      'AV_QUALIFIED' AS step,
      weight,
      ts_event_original,
      ts_ongoing AS ts_event_adjusted,
      ts_event_original AS ts_first_discard,
      ts_ongoing AS ts_last_discard, 
      rev,
      'drop_aq2o' AS business_event,
      CONCAT('MORE_THAN_', ongoing_window, '_DAYS_ON_STATUS') AS reason,
      'T3.1' AS aux_group,
      TRUE AS aux_data_event
  FROM 
    ongoing_aq2o
  WHERE 
    ts_event_discard IS NULL
      AND ts_ongoing <= CURRENT_TIMESTAMP() 
      AND step = 'AV_QUALIFIED'
),
t3_2 AS (
  SELECT
    id_lead,
    id_entity,
    id_user_registrant,
    business_context,
    supply_source,
    'AV_QUALIFIED' AS step,
    weight,
    ts_event_original,
    ts_event_original AS ts_event_adjusted, 
    ts_event_original AS ts_first_discard, 
    ts_event_original AS ts_last_discard, 
    rev,
    'ongoing_aq2o' AS business_event,
    NULL AS reason,
    'T3.2' AS aux_group,
    TRUE AS aux_data_event
  FROM 
    ongoing_aq2o
  WHERE
    ts_event_discard IS NULL
      AND ts_ongoing > CURRENT_TIMESTAMP() 
      AND step = 'AV_QUALIFIED'
),
t3_3 AS (
  SELECT 
    id_lead,
    id_entity,
    id_user_registrant,
    business_context,
    supply_source,
    'AV_QUALIFIED' AS step,
    weight,
    ts_event_original,
    GREATEST(ts_event_discard, ts_event_original) AS ts_event_adjusted,
    ts_first_discard,
    ts_last_discard,
    rev,
    'drop_aq2o' AS business_event,
    reason,
    'T3.3' AS aux_group,
    FALSE AS aux_data_event
  FROM 
    ongoing_aq2o
  WHERE 
    ts_event_discard IS NOT NULL
  UNION
  SELECT 
    id_lead,
    id_entity,
    id_user_registrant,
    business_context,
    supply_source,
    'QUALIFIED' AS step,
    weight,
    ts_event_original,
    GREATEST(ts_event_discard, ts_event_original) AS ts_event_adjusted, 
    NULL AS ts_first_discard,
    NULL AS ts_last_discard,
    rev,
    'conversion_p2q' AS business_event,
    NULL AS reason,
    'T3.3' AS aux_group,
    FALSE AS aux_data_event
  FROM 
    ongoing_aq2o
  WHERE 
    ts_event_discard IS NOT NULL
  UNION
  SELECT 
    id_lead,
    id_entity,
    id_user_registrant,
    business_context,
    supply_source,
    'AV_QUALIFIED' AS step,
    weight,
    ts_event_original,
    GREATEST(ts_event_discard, ts_event_original) AS ts_event_adjusted, 
    NULL AS ts_first_discard,
    NULL AS ts_last_discard,
    rev,
    'conversion_q2aq' AS business_event,
    NULL AS reason,
    'T3.3' AS aux_group,
    FALSE AS aux_data_event
  FROM 
    ongoing_aq2o
  WHERE 
    ts_event_discard IS NOT NULL
),
t3 AS (
  SELECT *
  FROM t3_0
  UNION
  SELECT *
  FROM t3_1
  UNION
  SELECT *
  FROM t3_2
  UNION
  SELECT *
  FROM t3_3
),
-- PROSPECTS Q2AQ EVENTS
discards_events_q2aq AS (
  SELECT 
    id_lead,
    id_entity,
    id_user_registrant,
    business_context,
    supply_source,
    rev,
    step,
    IF(drop_step = 'Q2AQ', 4, 5) AS weight,
    reason,
    drop_step,
    ts_event,
    MIN(ts_event) OVER (PARTITION BY id_entity, business_context) AS ts_first_discard,
    MAX(ts_event) OVER (PARTITION BY id_entity, business_context) AS ts_last_discard
  FROM 
    datalake_supply_flows.conversion_staging
  LEFT ANTI JOIN 
    fl_events AS fl
      USING (id_lead, business_context)
  LEFT ANTI JOIN 
    bob_events AS qual
      USING (id_lead, business_context)
  LEFT ANTI JOIN 
    t3 
      USING (id_lead, business_context)
  WHERE 
    step = 'PROSPECT' AND drop_step = ('Q2AQ')
),
last_discards_q2aq AS (
  SELECT 
    id_lead,
    id_entity,
    id_user_registrant,
    business_context,
    supply_source,
    rev,
    'QUALIFIED' AS step,
    'drop_q2aq' AS business_event,
    weight,
    reason,
    drop_step,
    ts_event,
    FALSE AS aux_data_event,
    ts_first_discard,
    ts_last_discard
  FROM 
    discards_events_q2aq
  QUALIFY RANK() OVER (PARTITION BY id_lead, business_context ORDER BY rev, ts_event DESC) = 1 -- ÚLTIMO EVENTO DE DESCARTE
  UNION ALL
  SELECT 
    id_lead,
    id_entity,
    id_user_registrant,
    business_context,
    supply_source,
    rev,
    'QUALIFIED' AS step,
    'conversion_p2q' AS business_event,
    weight,
    NULL AS reason, -- LIMPEZA DA COLUNA
    drop_step,
    ts_event,
    TRUE AS aux_data_event,
    NULL AS ts_first_discard,
    NULL AS ts_last_discard
  FROM 
    discards_events_q2aq
  QUALIFY RANK() OVER (PARTITION BY id_lead, business_context ORDER BY rev, ts_event DESC) = 1 -- ÚLTIMO EVENTO DE DESCARTE
),
t4 AS (
  SELECT 
    p.id_lead_ebdb AS id_lead,
    d.id_entity,
    d.id_user_registrant,
    p.business_context,
    p.supply_source,
    d.step,
    d.weight,
    d.ts_event AS ts_event_original,
    d.ts_event AS ts_event_adjusted,
    d.rev,
    d.business_event,
    d.reason,
    'T4.0' AS aux_group,
    d.aux_data_event,
    d.ts_first_discard,
    d.ts_last_discard
  FROM 
    datalake_supply_flows.acquisition_tracking AS p
  JOIN 
    last_discards_q2aq AS d
      ON (p.id_lead_ebdb = d.id_lead)
      AND (p.business_context = d.business_context)
      AND (p.funnel_step = 'PROSPECT')
),
discards_events_p2q AS (
  SELECT 
    id_lead,
    id_entity,
    id_user_registrant,
    business_context,
    supply_source,
    rev,
    step,
    IF(drop_step = 'Q2AQ', 4, 5) AS weight, -- SE EVENTO Q2AQ, VEM ANTES (ETAPA 4)
    reason,
    drop_step,
    ts_event,
    MIN(ts_event) OVER (PARTITION BY id_entity, business_context) AS ts_first_discard, -- PEGANDO DATAS DE PRIMEIRO E ÚLTIMO DESCARTE
    MAX(ts_event) OVER (PARTITION BY id_entity, business_context) AS ts_last_discard
  FROM 
    datalake_supply_flows.conversion_staging
  LEFT ANTI JOIN 
    fl_events AS fl
      USING (id_lead, business_context)
  LEFT ANTI JOIN 
    bob_events AS qual
      USING (id_lead, business_context)
  LEFT ANTI JOIN 
    t4 AS discards_q2aq 
      USING (id_lead, business_context)
  WHERE 
    step = 'PROSPECT' AND drop_step = ('P2Q')
  QUALIFY ROW_NUMBER() OVER (PARTITION BY id_lead, business_context ORDER BY rev, ts_event DESC) = 1 -- ÚLTIMO EVENTO DE DESCARTE
),
ongoing_p2q AS (
  SELECT 
    p.id_lead_ebdb AS id_lead,
    p.id_lead_ebdb AS id_entity,
    CAST(NULL AS BIGINT) AS id_user_registrant,
    p.business_context,
    p.supply_source,
    p.funnel_step,
    5 AS weight,
    p.ts_event,
    TIMESTAMPADD(DAY, scs.ongoing_window, p.ts_event) AS ts_ongoing, -- FAÇO A SOMA DE 30 DIAS NA DATA DO EVENTO DE OPP
    p.ts_event AS ts_first_discard,
    TIMESTAMPADD(DAY, scs.ongoing_window, p.ts_event) AS ts_last_discard,
    ongoing_window
  FROM datalake_supply_flows.acquisition_tracking AS p
  LEFT ANTI JOIN 
    discards_events_p2q AS d
      ON (p.id_lead_ebdb = d.id_lead)
      AND (p.business_context = d.business_context)
  LEFT ANTI JOIN 
    fl_events AS fl
      ON (fl.id_lead = p.id_lead_ebdb)
      AND (fl.business_context = p.business_context)
  LEFT ANTI JOIN 
    bob_events AS qual
      ON (qual.id_lead = p.id_lead_ebdb)
      AND (qual.business_context = p.business_context)
  LEFT ANTI JOIN 
    t2 AS opp -- Removing opportunities
      ON (opp.id_lead = p.id_lead_ebdb)
        AND (opp.business_context = p.business_context)
  LEFT ANTI JOIN 
    t4 AS discards_q2aq   -- Removing discards Q2AQ
      ON (discards_q2aq.id_lead = p.id_lead_ebdb)
      AND (discards_q2aq.business_context = p.business_context)
  LEFT ANTI JOIN 
    t3 AS discards_aq2o -- Removing discards AQ2O
      ON (discards_aq2o.id_lead = p.id_lead_ebdb)
        AND (discards_aq2o.business_context = p.business_context)
  LEFT ANTI JOIN 
    3p_events AS 3pe -- Removing 3P events
      ON (3pe.id_lead = p.id_lead_ebdb)
        AND (3pe.business_context = p.business_context)
        AND (3pe.supply_source = p.supply_source)
  LEFT JOIN 
    datalake_supply_flows.supply_conversion_settings AS scs
      ON (scs.step = p.funnel_step)
  WHERE 
    p.funnel_step = 'PROSPECT'
),
t5_1 AS (
  SELECT 
    id_lead,
    id_entity,
    id_user_registrant,
    business_context,
    supply_source,
    funnel_step AS step,
    weight,
    ts_event AS ts_event_original,
    ts_ongoing AS ts_event_adjusted, -- DATA DO ÚLTIMO DESCARTE
    ts_first_discard,
    ts_last_discard,
    NULL AS rev,
    'drop_p2q' AS business_event,
    CONCAT('MORE_THAN_', ongoing_window, '_DAYS_ON_STATUS') AS reason,
    'T5.1' AS aux_group,
    TRUE AS aux_data_event
  FROM 
    ongoing_p2q
  WHERE 
    ts_ongoing <= CURRENT_TIMESTAMP()
),
t5_2 AS (
  SELECT 
    id_lead,
    id_entity,
    id_user_registrant,
    business_context,
    supply_source,
    funnel_step AS step,
    weight,
    ts_event AS ts_event_original,
    ts_event AS ts_event_adjusted,
    NULL AS ts_first_discard,
    NULL AS ts_last_discard,
    NULL AS rev,
    'ongoing_p2q' AS business_event,
    NULL AS reason,
    'T5.2' AS aux_group,
    TRUE AS aux_data_event
  FROM 
    ongoing_p2q
  WHERE 
    ts_ongoing > CURRENT_TIMESTAMP()
),
t5_3 AS (
  SELECT 
    id_lead,
    id_entity,
    id_user_registrant,
    business_context,
    supply_source,
    step,
    weight,
    ts_event AS ts_event_original,
    ts_last_discard AS ts_event_adjusted,
    ts_first_discard,
    ts_last_discard,
    rev,
    'drop_p2q' AS business_event,
    reason,
    'T5.3' AS aux_group,
    FALSE AS aux_data_event
  FROM 
    discards_events_p2q
),
t5 AS (
  SELECT * 
  FROM t5_1
  UNION ALL
  SELECT *
  FROM t5_2
  UNION ALL
  SELECT *
  FROM t5_3
),
original_events_reorg AS (
  SELECT
    id_lead,
    id_entity,
    id_user_registrant,
    business_context,
    supply_source,
    step,
    weight,
    ts_event_original,
    ts_event_adjusted,
    CAST(NULL AS TIMESTAMP) AS ts_first_discard,
    CAST(NULL AS TIMESTAMP) AS ts_last_discard,
    rev,
    business_event,
    reason,
    aux_group,
    aux_data_event
  FROM 
    t1
  UNION ALL
  SELECT
    id_lead,
    id_entity,
    id_user_registrant,
    business_context,
    supply_source,
    step,
    weight,
    ts_event_original,
    ts_event_adjusted,
    CAST(NULL AS TIMESTAMP) AS ts_first_discard,
    CAST(NULL AS TIMESTAMP) AS ts_last_discard,
    rev,
    business_event,
    reason,
    aux_group,
    aux_data_event
  FROM 
    t2
  UNION ALL
  SELECT     
    id_lead,
    id_entity,
    id_user_registrant,
    business_context,
    supply_source,
    step,
    weight,
    ts_event_original,
    ts_event_adjusted,
    ts_first_discard,
    ts_last_discard,
    rev,
    business_event,
    reason,
    aux_group,
    aux_data_event
  FROM 
    t3
  UNION ALL
  SELECT     
    id_lead,
    id_entity,
    id_user_registrant,
    business_context,
    supply_source,
    step,
    weight,
    ts_event_original,
    ts_event_adjusted,
    ts_first_discard,
    ts_last_discard,
    rev,
    business_event,
    reason,
    aux_group,
    aux_data_event
  FROM 
    t4
  UNION ALL
  SELECT     
    id_lead,
    id_entity,
    id_user_registrant,
    business_context,
    supply_source,
    step,
    weight,
    ts_event_original,
    ts_event_adjusted,
    ts_first_discard,
    ts_last_discard,
    rev,
    business_event,
    reason,
    aux_group,
    aux_data_event
  FROM 
    t5
)

SELECT 
  *
FROM original_events_reorg