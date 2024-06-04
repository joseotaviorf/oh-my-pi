WITH pp_multi AS (
  SELECT
    doh.id_owner,
    fhl.sk_house_listing/1000 AS id_house
  FROM
    datalake_pro_owners.daily_owner_houses_quantity_history AS doh
  INNER JOIN
    dw_rent.fact_house_listings AS fhl
      ON fhl.sk_owner = doh.id_owner
  WHERe
    is_pp_multi_active IS TRUE
    AND dt_houses_owned = CURRENT_DATE() - INTERVAL 1 DAY
),
contracts AS (
  SELECT DISTINCT
    dhl.id_house,
    COALESCE(dc.dt_start, dc.dt_entrance) AS dt_start_contract,
    dc.sk_contract,
    CASE
      WHEN fcp.contract_role = "landlord" THEN fcp.sk_user
      ELSE NULL
    END AS contract_user
  FROM
    dw_rent.dim_contract AS dc
  INNER JOIN
    dw_rent.fact_house_listings AS fhl
      ON fhl.sk_contract = dc.sk_contract
  INNER JOIN dw_rent.dim_house_listing dhl
    ON dhl.sk_house_listing = fhl.sk_house_listing
  LEFT JOIN dw_rent.fact_contract_people fcp
    ON dc.sk_contract = fcp.sk_contract
  WHERE
    dc.sk_contract != -1
    AND dc.status = "Ativo"
),
valid_contracts AS (
  SELECT
    sk_contract,
    id_house,
    dt_start_contract,
    contract_user
  FROM
    contracts
  WHERE
    contract_user > 0
  QUALIFY
    DENSE_RANK() OVER(PARTITION BY id_house ORDER BY id_house, dt_start_contract DESC) = 1
),
pp_multi_assistants AS (
  SELECT
    pm.*,
    dc.sk_contract,
    dc.dt_start_contract,
    dc.contract_user,
    cp.phone_number,
    CASE
      WHEN id_owner = contract_user THEN "pp_multi"
      ELSE "assistant"
    END AS role
  FROM
    pp_multi AS pm
  LEFT JOIN
    valid_contracts dc
      ON dc.id_house = pm.id_house
  LEFT JOIN
    dw_public.dim_user du
      ON dc.contract_user = du.sk_user
  LEFT JOIN
    dw_rent.fact_contract_people fcp
      ON dc.sk_contract = fcp.sk_contract
      AND fcp.sk_user = dc.contract_user
  LEFT JOIN
    datalake_ebdb_contract.contract_person cp
      ON dc.sk_contract = cp.id_contract
      AND fcp.sk_contract_person = cp.id_contract_person
  WHERE
    dc.sk_contract IS NOT NULL
)
SELECT
  REGEXP_REPLACE(phone_number, "\\s|-|\\(|\\)", "") AS phone_number,
  COLLECT_SET(contract_user) AS users,
  "pp_multi_assistants" AS whitelist_group
FROM
  pp_multi_assistants
WHERE
  role = "assistant"
  AND phone_number IS NOT NULL
  AND phone_number != 'undefined'
GROUP BY 1
