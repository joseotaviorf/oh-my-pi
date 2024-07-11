WITH conversion_taxonomy AS (
    SELECT 
        hda.id AS id_draft,
        sp.id_external AS id_house,
        EXPLODE(
            ARRAY(
                IF(hda.is_for_rent, 'RENT', NULL),
                IF(hda.is_for_sale, 'SALE', NULL)
            )
        ) AS business_context,
        hda.type,
        hda.ops_team,
        hda.ops_company,
        hda.ops_contact_type,
        hda.ops_contact_channel,
        1 AS source,
        'QUALIFIED' AS funnel_step,
        h.id_region,
        r.id_main AS id_user_registrant,
        hda.ts_created AS ts_event
    FROM 
        datalake_bob.house_draft AS hda
    JOIN 
        datalake_bob_clean.submission_progress AS sp
            ON hda.id = sp.id_house_draft
    LEFT JOIN 
        datalake_bob_clean.registrar AS r
            ON hda.registrar = r.id
    LEFT JOIN 
        datalake_ebdb_clean.house AS h
            ON sp.id_external = h.id
),
extract_context_discard AS (
    SELECT 
        cd.id,
        cd.id_prospect,
        cd.id_user AS id_user_registrant,
        cd.business_context,
        GET_JSON_OBJECT(cd.attendance_info, '$.team') AS team,
        GET_JSON_OBJECT(cd.attendance_info, '$.company') AS company,
        GET_JSON_OBJECT(cd.attendance_info, '$.contactType') AS contact_type,
        GET_JSON_OBJECT(cd.attendance_info, '$.contactChannel') AS contact_channel,
        cd.reason,
        sds.funnel_step,
        cd.ts_created,
        cd.ts_updated
    FROM 
        datalake_wololo_clean.context_discard AS cd
    JOIN
        datalake_supply_flows.supply_discards_settings AS sds
            ON cd.reason = sds.discards_reason
    QUALIFY ROW_NUMBER() OVER (PARTITION BY cd.id_prospect, cd.business_context, sds.funnel_step ORDER BY cd.ts_created DESC) = 1
),
extract_wololo AS (
  SELECT
        p.id AS id_prospect,
        p.id_reference AS id_lead_ebdb,
        p.id_external AS id_lead_rene,
        'owner_conversion' AS origin,
        EXPLODE(
            ARRAY(
            IF(p.is_for_rent, 'RENT', NULL),
            IF(p.is_for_sale, 'SALE', NULL)
            )
        ) AS business_context,
        l.id_region
    FROM
        datalake_wololo_clean.prospect AS p
    LEFT JOIN 
        datalake_ebdb_clean.lead AS l
            ON p.id_reference = l.id
),
discards_taxonomy AS (
    SELECT 
        p.id_lead_ebdb,
        p.business_context,
        p.id_region,
        p.id_prospect,
        p.origin AS application,
        td.team AS ops_agent,
        td.company AS ops_partner,
        td.contact_type AS ops_approach,
        td.contact_channel AS ops_contact_medium,
        2 AS source,
        funnel_step,
        td.id_user_registrant,
        td.ts_created AS ts_event
    FROM
        extract_wololo AS p
    JOIN 
        extract_context_discard AS td
            USING (id_prospect, business_context)
),
original_flow AS (
    SELECT 
        NULL AS id_lead,
        id_house,
        business_context,
        id_user_registrant,
        source,
        type AS application,
        funnel_step,
        id_region,
        CASE 
            WHEN ops_team = 'CAPTA_AI' THEN 'acquisition'
            WHEN ops_team IS NOT NULL THEN 'conversion'
            ELSE NULL
        END AS ops_objective,
        ops_team AS ops_agent,
        ops_company AS ops_partner,
        ops_contact_type AS ops_approach,
        ops_contact_channel AS ops_contact_medium,
        ts_event,
        NOW() AS ts_load
    FROM 
        conversion_taxonomy
    WHERE 
        business_context IS NOT NULL
        AND id_house IS NOT NULL
    UNION ALL 
    SELECT 
        id_lead_ebdb AS id_lead,
        NULL AS id_house,
        business_context,
        id_user_registrant,
        source,
        application,
        funnel_step,
        id_region,
        CASE 
            WHEN ops_agent = 'CAPTA_AI' THEN 'acquisition'
            WHEN ops_agent IS NOT NULL THEN 'conversion'
            ELSE NULL
        END AS ops_objective,
        ops_agent,
        ops_partner,
        ops_approach,
        ops_contact_medium,
        ts_event,
        NOW() AS ts_load
    FROM 
        discards_taxonomy
    WHERE 
        id_lead_ebdb IS NOT NULL
),
all_tables AS (
    SELECT 
        id_lead,
        id_house,
        business_context,
        id_user_registrant,
        source,
        application,
        funnel_step,
        id_region,
        ops_objective,
        ops_agent,
        ops_partner,
        ops_approach,
        ops_contact_medium,
        ts_event,
        ts_load
    FROM 
        original_flow
    UNION ALL
    SELECT 
      id_lead,
      id_house,
      business_context,
      id_user_registrant,
      source,
      application,
      funnel_step,
      id_region,
      ops_objective,
      ops_agent,
      ops_partner,
      ops_approach,
      ops_contact_medium,
      ts_event,
      ts_load
    FROM 
        datalake_supply_flows.fallback_taxonomy
)

SELECT 
    COALESCE(b.id_lead, cl.id_lead) AS id_lead,
    b.id_house,
    id_user_registrant,
    id_region,
    b.business_context,
    b.source,
    SF_NORMALIZE_STRING(b.application) AS application,
    funnel_step,
    SF_NORMALIZE_STRING(COALESCE(b.ops_objective, oa.ops_objective)) AS ops_objective,
    SF_NORMALIZE_STRING(COALESCE(b.ops_agent, oa.ops_agent)) AS ops_agent,
    SF_NORMALIZE_STRING(COALESCE(b.ops_partner, oa.ops_partner)) AS ops_partner,
    SF_NORMALIZE_STRING(b.ops_approach) AS ops_approach,
    SF_NORMALIZE_STRING(b.ops_contact_medium) AS ops_contact_medium,
    IF(b.id_user_registrant IS NOT NULL AND oa.id_user IS NOT NULL, TRUE, FALSE) AS has_ops_agents_table,
    ts_event,
    ts_load
FROM 
    all_tables AS b
LEFT JOIN 
    datalake_supply_flows.conversion_lookup AS cl
        ON (b.id_house = cl.id_house)
        AND (b.business_context = cl.business_context)
        AND (cl.supply_source = '1P')
LEFT JOIN 
    datalake_supply_flows.operations_agents AS oa
        ON (b.id_user_registrant = oa.id_user)
QUALIFY ROW_NUMBER() OVER (PARTITION BY b.id_house, COALESCE(b.id_lead, cl.id_lead), b.business_context ORDER BY b.source ASC) = 1