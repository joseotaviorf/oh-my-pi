WITH cte_subcategories AS (
    SELECT
        id_securities,
        id_group,
        EXPLODE_OUTER(categories) AS map_categories
    FROM
        datalake_velo_omie.cash_flows
    WHERE
        categories IS NOT NULL
)

SELECT
    id_securities,
    id_group,
    map_categories['cCodCateg'] AS id_category,
    CAST(map_categories['nDistrPercentual'] AS FLOAT) AS category_percentage,
    CAST(map_categories['nDistrValor'] AS FLOAT) AS category_value,
    CASE
        WHEN map_categories['nValorFixo'] = 'S' THEN TRUE
        WHEN map_categories['nValorFixo'] = 'N' THEN FALSE
        ELSE NULL
    END AS is_category_fixed_value
FROM
    cte_subcategories
