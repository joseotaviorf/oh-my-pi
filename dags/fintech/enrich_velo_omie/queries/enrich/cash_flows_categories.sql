WITH cte_subcategories AS (
    SELECT
        id_securities,
        EXPLODE_OUTER(categories) AS map_categories
    FROM
        datalake_velo_omie.cash_flows
    WHERE
        categories IS NOT NULL
)

SELECT
    id_securities,
    map_categories['cCodCateg'] AS id_category,
    map_categories['nDistrPercentual'] AS category_percentage,
    map_categories['nDistrValor'] AS category_value,
    CASE
        WHEN map_categories['nValorFixo'] = 'S' THEN TRUE
        WHEN map_categories['nValorFixo'] = 'N' THEN FALSE
        ELSE NULL
    END AS is_category_fixed_value
FROM
    cte_subcategories
