WITH partner_agencies_aux AS (
    SELECT
        id_company AS id_company_hubspot,
        NULLIF(
            REGEXP_EXTRACT(
                GET_JSON_OBJECT(properties, '$.tag_imobiliarias'),
                r'\[3(?i:p)(?i:BH)?\-(.+?)\]'
        ), '') AS extracted_3p_tag,
        COALESCE(
            NULLIF(GET_JSON_OBJECT(properties, '$.estado'), ''),
            NULLIF(GET_JSON_OBJECT(properties, '$.state'), '')
        ) AS partner_state,
        ROW_NUMBER() OVER(PARTITION BY id_company ORDER BY ts_updated DESC) = 1 AS is_most_recent_row,
        ts_updated
    FROM
        datalake_hubspot_clean.company
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY REPLACE(UPPER(extracted_3p_tag), ' ', '') ORDER BY ts_updated DESC) = 1
        AND extracted_3p_tag IS NOT NULL
),
partner_agencies AS (
    SELECT
        paa.id_company_hubspot,
        REPLACE(UPPER(paa.extracted_3p_tag), ' ', '') AS extracted_3p_tag,
        current_paa.extracted_3p_tag AS current_tag,
        paa.partner_state,
        paa.ts_updated
    FROM
        partner_agencies_aux AS paa
    LEFT JOIN
        partner_agencies_aux AS current_paa
            ON paa.id_company_hubspot = current_paa.id_company_hubspot
            AND current_paa.is_most_recent_row
),
work_contract_aux AS (
  SELECT
      wc.id,
      IF(wc.contract_name = bus.hub_name_wc, bus.id_business_unit_teams, NULL) AS id_hub_teams,
      pa.id_company_hubspot,
      IF(wc.contract_name = bus.hub_name_wc, bus.hub_name_teams, NULL) AS hub_name_teams,
      wc.contract_name,
      COALESCE(pa.current_tag, NULLIF(REGEXP_EXTRACT(wc.contract_name, '(?<=\\[3P\\-)(.+?)(?=\\])'), '')) AS 3p_partner,
      wc.contract_name LIKE '%[3P-%]%' AS is_3p_contract,
      wc.contract_name LIKE '%[3P-%]%' AND partner_state IS DISTINCT FROM 'MG' AS is_3p_5a_contract,
      wc.contract_name LIKE '%[3P-%]%' AND partner_state IS NOT DISTINCT FROM 'MG' AS is_3p_bh_contract,
      wc.ts_created,
      wc.ts_updated
  FROM
      datalake_ebdb_clean.work_contract AS wc
  LEFT JOIN
      datalake_gsheets_clean.sale_business_unit_standardization AS bus -- kept this source only for historical purpose.
          ON bus.hub_name_wc = wc.contract_name
  LEFT JOIN
      partner_agencies AS pa
          ON REPLACE(UPPER(NULLIF(REGEXP_EXTRACT(wc.contract_name, '(?<=\\[3P\\-)(.+?)(?=\\])'), '')), ' ', '') = pa.extracted_3p_tag
),
hubspot_company_name_history AS (
  SELECT DISTINCT
    id_company AS id_company_hubspot,
    name AS hubspot_company_name
  FROM
    datalake_hubspot.company_history
)
SELECT
  wc.id,
  wc.id_hub_teams,
  COALESCE(wc.id_company_hubspot, cs.id_hubspot, ch.id_company_hubspot, wcm.id_hubspot) AS id_company_hubspot,
  wc.hub_name_teams,
  wc.contract_name,
  wc.3p_partner,
  wc.is_3p_contract,
  wc.is_3p_5a_contract,
  wc.is_3p_bh_contract,
  wc.ts_created,
  wc.ts_updated
FROM
  work_contract_aux AS wc
LEFT JOIN
  datalake_company.company_sks AS cs
    ON wc.3p_partner = cs.trade_name
    OR wc.3p_partner = cs.company_name
    OR wc.3p_partner = cs.hubspot_company_name
LEFT JOIN
  hubspot_company_name_history AS ch
    ON wc.3p_partner = ch.hubspot_company_name
LEFT JOIN
  datalake_gsheets_clean.work_contract_matches AS wcm
    ON wc.3p_partner = wcm.3p_partner
GROUP BY
  ALL