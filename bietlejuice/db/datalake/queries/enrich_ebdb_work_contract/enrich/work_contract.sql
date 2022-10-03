SELECT
    wc.id,
    IF (wc.contract_name = bus.hub_name_wc, bus.id_business_unit_teams, NULL) AS id_hub_teams,
    IF (wc.contract_name = bus.hub_name_wc, bus.hub_name_teams, NULL) AS hub_name_teams,
    wc.contract_name,
    REGEXP_EXTRACT(wc.contract_name, '(?<=\\[3P\\-)(.+?)(?=\\])') AS 3p_partner,
    wc.contract_name LIKE '%[3P-%]%' AS is_3p_contract,
    wc.ts_created,
    wc.ts_updated
FROM
    datalake_ebdb_clean.work_contract AS wc
LEFT JOIN
    datalake_gsheets_clean.sale_business_unit_standardization AS bus
        ON bus.hub_name_wc = wc.contract_name
 