WITH cluster_ppmulti_per_month AS (
  SELECT 
      CAST(doq.id_owner AS INTEGER) AS id_owner,
      CASE 
          WHEN doq.id_owner IN (2982090, 4133107,7418653) THEN 'Short Stay'
          WHEN doq.id_owner IN (4166683,9005414,213199,6446899,1895145,9468263,7418653,4133107,416663,7109194,75535,1673646,2982090,145322,495270,3930579,70225) THEN 'Corporate'
          WHEN doq.ongoing_houses > 15 THEN 'Investors (15+)'
          WHEN doq.ongoing_houses > 10 THEN 'Investors (10-15)'
          WHEN doq.ongoing_houses >= 5 THEN 'Long-tail (5-10)'
          WHEN doq.ongoing_houses > 0 THEN 'Amateurs'
      END AS type_pp,
      doq.ongoing_houses,
      doq.is_pp_multi_active,
      doq.dt_houses_owned
  FROM 
      datalake_pro_owners.daily_owner_houses_quantity_history doq    
  WHERE 
      year = YEAR(CURRENT_DATE - INTERVAL '1' DAY)
      AND month = MONTH(CURRENT_DATE - INTERVAL '1' DAY)
      AND day = DAY(CURRENT_DATE - INTERVAL '1' DAY)
      AND (doq.ongoing_houses >= 5 OR doq.is_pp_multi_active)

),
assistants AS (
    SELECT DISTINCT
        lc.id_house,
        CAST(c.id AS INTEGER) AS id_contract,
        CAST((CASE WHEN cp.contract_role = 'landlord' THEN COALESCE(cp.id_user_contract_person, -1) ELSE NULL END) AS INTEGER) AS contract_user        
    FROM 
        datalake_ebdb_contract.contract AS c        
    INNER JOIN 
      datalake_listing_contracts.listing_contracts AS lc
        ON c.id = lc.id_contract       
    LEFT JOIN 
      datalake_ebdb_contract.contract_person AS cp 
        ON c.id = cp.id_contract     
    WHERE 
      c.status = 'Ativo'
    QUALIFY  
      DENSE_RANK() OVER(PARTITION BY lc.id_house ORDER BY lc.id_house, coalesce(c.dt_started, c.dt_entered) DESC) = 1
),
pp_multi_proprety_info AS (
    SELECT 
        CAST(ca.id_owner AS INTEGER) AS id_owner,
        h.id AS id_house        
    FROM 
        cluster_ppmulti_per_month AS ca
    LEFT JOIN  
          datalake_ebdb_listing.house AS h 
            ON h.id_user = ca.id_owner
),
property_assistants AS (
    SELECT
        CAST(pm.id_owner AS INTEGER) AS id_owner,
        pm.id_house, 
        CASE 
            WHEN (ass.contract_user IS NULL OR ass.contract_user = -1) THEN NULL 
            ELSE ass.contract_user 
        END AS id_user_assistant,
        ass.contract_user
    FROM 
        pp_multi_proprety_info AS pm
    LEFT JOIN 
        assistants AS ass 
            ON ass.id_house = pm.id_house  
    WHERE 
        ass.id_contract IS NOT NULL
),
pp_multi_last_status AS (
    SELECT
        id_owner,
        CAST(MAX(ts_pro_owner_started) AS DATE) AS dt_last_pro_owner_started
    FROM
        datalake_pro_owners.pro_owner_history
    WHERE
        is_pro_owner = true
    GROUP BY
        1
),
ppmulti_and_assistants AS (
    SELECT 
        DISTINCT 
        CASE 
            WHEN (pa.contract_user IS NULL OR pa.contract_user = -1) THEN ca.id_owner 
            ELSE pa.contract_user 
        END AS id_user_contract_final,
        CASE 
            WHEN (CASE WHEN (pa.contract_user IS NULL OR pa.contract_user = -1) THEN ca.id_owner 
                    ELSE pa.contract_user 
                    END = ca.id_owner) THEN 'PP'  
            ELSE 'ASS' 
        END AS role_user_contract_final,
        ca.id_owner AS id_owner,
        CASE 
            WHEN id_user_contract_final = ca.id_owner
            THEN NULL 
            ELSE pa.id_user_assistant
        END id_user_assistant,
        ca.type_pp AS cluster_pp_multi,    
        ca.ongoing_houses AS ongoing_houses_pp_multi,
        ca.is_pp_multi_active AS is_active_pp_multi,
        base_pp.dt_last_pro_owner_started,
        ca.dt_houses_owned AS dt_last_pro_owner_finished
    FROM 
        cluster_ppmulti_per_month AS ca
    LEFT JOIN 
        property_assistants AS pa 
        ON pa.id_owner = ca.id_owner
    LEFT JOIN 
        pp_multi_last_status AS base_pp 
        ON base_pp.id_owner = ca.id_owner
)
SELECT
    id_user_contract_final AS id_user,
    u.name AS user_name,
    u.email AS user_email, 
    role_user_contract_final AS user_role,
    id_owner,
    id_user_assistant,
    cluster_pp_multi,
    ongoing_houses_pp_multi,
    is_active_pp_multi,
    dt_last_pro_owner_started,
    dt_last_pro_owner_finished
FROM
    ppmulti_and_assistants AS paa
LEFT JOIN 
    datalake_ebdb_user.user AS u 
        ON id_user_contract_final = u.id 
QUALIFY 
    -- If the user is PPM and ASS, the priority relationship is PPM
    DENSE_RANK() OVER( PARTITION BY id_user_contract_final, dt_last_pro_owner_finished ORDER BY role_user_contract_final DESC) = 1
    -- If the user has an ASS of more than two PPM, the priority relationship is the one associated with the PPM with the highest number of ongoing houses
    AND DENSE_RANK() OVER( PARTITION BY id_user_contract_final, role_user_contract_final, dt_last_pro_owner_finished ORDER BY ongoing_houses_pp_multi DESC, dt_last_pro_owner_started DESC) = 1
