WITH tqc_agents AS (
  SELECT 
    acc.id_agent,
    u.id AS id_user_agent,
    u.cpf,
    u.email,
    acc.ts_status_started,
    COALESCE(acc.ts_status_ended, NOW()) AS ts_status_ended,
    u.ts_created
  FROM 
    datalake_ebdb_agents.agent_unified_contract_changes AS acc
  LEFT JOIN 
    datalake_ebdb_user.`user` AS u
      ON acc.id_agent = u.id_agent
  WHERE
    acc.is_agent_for_sale = true
    AND acc.is_agent_active
    AND NOT acc.has_blocked_schedule
    AND NULLIF(acc.3p_partner, '') IS NULL
),
gsheets_tqc_leads AS (
  SELECT 
    ROW_NUMBER() OVER(ORDER BY ts_appointment ASC NULLS FIRST) AS id,
    agent_email,
    agent_cpf,
    lead_name,
    lead_phone,
    lead_email,
    'Old' AS tqc_flow,
    'REFERRAL' AS origin,
    UPPER(CAST(is_valid_lead AS STRING)) AS status,
    ts_appointment
  FROM 
    datalake_gsheets_clean.tqc_leads
),
gsheets_tqc_agents_join AS (
  SELECT 
    tqc.id,
    COALESCE(daa1.id_agent,daa2.id_agent,dua1.id_agent,dua2.id_agent) AS id_agent,
    COALESCE(daa1.id_user_agent,daa2.id_user_agent,dua1.id,dua2.id) AS id_user_agent,
    -- When the user was created before the appointment, this is negative, and we set this to 0
    GREATEST(DATEDIFF(COALESCE(daa1.ts_created, daa2.ts_created, dua1.ts_created,dua2.ts_created),tqc.ts_appointment), 0) AS aux_deduplicate,  
    tqc.lead_name,
    tqc.lead_phone,
    tqc.lead_email,
    ah.hub_name,
    ah.city_group,
    CASE 
      WHEN ah.short_region_name = 'MG'
        THEN 'BH'
      WHEN ah.short_region_name IN ('RJ','SP','RS')
        THEN 'SP-RJ-POA'
      ELSE 'OTHER'
    END AS macro_region,
    tqc.status,
    tqc.tqc_flow,
    tqc.origin,
    tqc.ts_appointment AS ts_created
  FROM 
    gsheets_tqc_leads AS tqc
  LEFT JOIN 
    tqc_agents AS daa1
      ON tqc.agent_cpf = daa1.cpf
        AND tqc.ts_appointment::TIMESTAMP BETWEEN daa1.ts_status_started AND daa1.ts_status_ended
  LEFT JOIN 
    tqc_agents AS daa2
      ON tqc.agent_email = daa2.email
        AND tqc.ts_appointment::TIMESTAMP BETWEEN daa2.ts_status_started AND daa2.ts_status_ended
  LEFT JOIN 
    datalake_ebdb_user.`user` AS dua1
      ON tqc.agent_cpf = dua1.cpf
        AND COALESCE(dua1.id_agent,0) != 0
        AND dua1.country_code = 'BR'
  LEFT JOIN 
    datalake_ebdb_user.`user` AS dua2
      ON tqc.agent_email = dua2.email
        AND COALESCE(dua2.id_agent,0) != 0
        AND dua2.country_code = 'BR'
  LEFT JOIN
    datalake_hub_services.member_hub_allocation AS ah
      ON COALESCE(daa1.id_agent,daa2.id_agent,dua1.id_agent,dua2.id_agent) = ah.id_agent
      AND DATE(tqc.ts_appointment) = ah.dt_reference
  QUALIFY 
    ROW_NUMBER() OVER(
      PARTITION BY
        tqc.id
      ORDER BY 
        aux_deduplicate, -- We prioritize the ones that were created before the appointment (which are set to 0). Otherwise, the most recent ones after the appointment.
        ABS( -- If more than one is from before, we prioritize the ones closer to the appointment.
          DATEDIFF(
            COALESCE(daa1.ts_created, daa2.ts_created, dua1.ts_created,dua2.ts_created),
            tqc.ts_appointment
          )
        )
    ) = 1 
),
gsheets_tqc_final AS (
  SELECT 
    tqc.id,
    CONCAT(COALESCE(tqc.id_agent,tqc.id_user_agent),'_',COALESCE(du1.id,du2.id,tqc.lead_phone)) AS id_referral_flow,
    tqc.id_agent,
    tqc.id_user_agent,
    COALESCE(du1.id,du2.id) AS id_user_lead,
    tqc.lead_phone,
    GREATEST(DATEDIFF(COALESCE(du1.ts_created, du2.ts_created),tqc.ts_created), 0) AS aux_deduplicate,  
    tqc.hub_name,
    tqc.city_group,
    tqc.macro_region,
    tqc.status,
    tqc.tqc_flow,
    tqc.origin,
    tqc.ts_created
  FROM
    gsheets_tqc_agents_join AS tqc
  LEFT JOIN 
    datalake_ebdb_user.`user` AS du1
      ON tqc.lead_email = du1.email
        AND COALESCE(du1.id_agent,0) = 0
        AND du1.country_code = 'BR'
  LEFT JOIN 
    datalake_ebdb_user.`user` AS du2
      ON tqc.lead_phone = du2.main_phone
        AND COALESCE(du2.id_agent,0) = 0
        AND du2.country_code = 'BR'
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY tqc.id ORDER BY aux_deduplicate, ABS(DATEDIFF(COALESCE(du1.ts_created,du2.ts_created),tqc.ts_created))) = 1
)  
SELECT
  id_referral_flow,
  id_agent,
  id_user_agent,
  id_user_lead,
  lead_phone,
  hub_name,
  city_group,
  macro_region,
  status,
  tqc_flow,
  origin,
  ts_created
FROM 
  gsheets_tqc_final
UNION ALL
SELECT 
  CONCAT(COALESCE(lr.id_agent,au.id),'_',COALESCE(lr.id_lead,lr.phone)) AS id_referral_flow,
  lr.id_agent,
  au.id AS id_user_agent,
  lr.id_lead AS id_user_lead,
  lr.phone AS lead_phone,
  ah.hub_name,
  ah.city_group,
  CASE 
    WHEN ah.short_region_name = 'MG'
      THEN 'BH'
    WHEN ah.short_region_name IN ('RJ','SP','RS')
      THEN 'SP-RJ-POA'
    ELSE 'OTHER'
  END AS macro_region,
  lr.status,
  'New' AS tqc_flow,
  lr.origin,
  lr.ts_created AS ts_created
FROM 
  datalake_ebdb_clean.agent_lead_referral AS lr
LEFT JOIN
  datalake_ebdb_user.`user` AS au
    ON lr.id_agent = au.id_agent
LEFT JOIN 
  datalake_ebdb_user.`user` AS u
    ON lr.id_lead = u.id
LEFT JOIN
  datalake_hub_services.member_hub_allocation AS ah
    ON lr.id_agent = ah.id_agent
    AND DATE(lr.ts_created) = ah.dt_reference
WHERE
  lr.id_agent NOT IN (22605,22606,23920)
QUALIFY
  ROW_NUMBER() OVER(PARTITION BY lr.id ORDER BY ah.dt_reference DESC) = 1 -- In some cases, there is more than one hub active for the same agent at a given day. We're getting the newest one.