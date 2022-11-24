SELECT
    CAST(NULLIF(REPLACE(id_contract, ',', ''), '') AS INT) AS id_contract,
    CAST(NULLIF(REPLACE(id_owner, ',', ''), '') AS INT) AS id_owner,
    CAST(NULLIF(REPLACE(id_house, ',', ''), '') AS INT) AS id_house,
    CAST(NULLIF(REPLACE(rent_value, ',', ''), '') AS DECIMAL(14,2)) AS rent_value,
    CAST(NULLIF(REPLACE(rent_net_value, ',', ''), '') AS DECIMAL(14,2)) AS rent_net_value,
    anticipation_fee,
    CAST(NULLIF(REPLACE(anticipation_cost, ',', ''), '') AS DECIMAL(14,2)) AS anticipation_cost,
    CAST(NULLIF(REPLACE(anticipation_value, ',', ''), '') AS DECIMAL(14,2)) AS anticipation_value,
    status,
    month AS month,
    YEAR(NULLIF(year, '')) AS year
FROM
    datalake_gsheets_raw.mra_historical;
