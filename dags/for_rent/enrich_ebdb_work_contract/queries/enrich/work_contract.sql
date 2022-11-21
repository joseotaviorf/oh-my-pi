WITH partner_agencies AS (
    SELECT
        id_company AS id_company_hubspot,
        REPLACE(UPPER(
            NULLIF(
                REGEXP_EXTRACT(
                    GET_JSON_OBJECT(properties, '$.tag_imobiliarias'),
                    r'\[3(?i:p)(?i:BH)?\-(.+?)\]'
                ), '') 
            ), ' ', ''
        ) AS extracted_3p_tag,
        COALESCE(
            NULLIF(GET_JSON_OBJECT(properties, '$.estado'), ''),
            NULLIF(GET_JSON_OBJECT(properties, '$.state'), '')
        ) AS partner_state,
        ts_updated
    FROM
        datalake_hubspot_clean.company
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY REPLACE(UPPER(extracted_3p_tag), ' ', '') ORDER BY ts_updated DESC) = 1
        AND extracted_3p_tag IS NOT NULL
)
SELECT
    wc.id,
    IF (wc.contract_name = bus.hub_name_wc, bus.id_business_unit_teams, NULL) AS id_hub_teams,
    pa.id_company_hubspot,
    IF (wc.contract_name = bus.hub_name_wc, bus.hub_name_teams, NULL) AS hub_name_teams,
    wc.contract_name,
    NULLIF(REGEXP_EXTRACT(wc.contract_name, '(?<=\\[3P\\-)(.+?)(?=\\])'), '') AS 3p_partner,
    wc.contract_name LIKE '%[3P-%]%' AS is_3p_contract,
    wc.contract_name LIKE '%[3P-%]%' AND partner_state IS DISTINCT FROM 'MG' AS is_3p_5a_contract,
    wc.contract_name LIKE '%[3P-%]%' AND partner_state IS NOT DISTINCT FROM 'MG' AS is_3p_bh_contract,
    wc.ts_created,
    wc.ts_updated
FROM
    datalake_ebdb_clean.work_contract AS wc
LEFT JOIN
    datalake_gsheets_clean.sale_business_unit_standardization AS bus
        ON bus.hub_name_wc = wc.contract_name
LEFT JOIN
    partner_agencies AS pa
        ON REPLACE(UPPER(NULLIF(REGEXP_EXTRACT(wc.contract_name, '(?<=\\[3P\\-)(.+?)(?=\\])'), '')), ' ', '') = pa.extracted_3p_tag
