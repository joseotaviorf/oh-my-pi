WITH
cte_ev AS (
    SELECT
        "Executivo de Visitas" AS agent_role,
        dt_opening AS bonus_start_date,
        dt_bonus_cutoff AS bonus_end_date,
        hub AS business_unit_id,
        bonus_fee
    FROM
        datalake_gsheets_clean.hub_bonus
),
cte_en AS (
    SELECT
        "Executivo de Negociação" AS agent_role,
        dt_bonus AS bonus_start_date,
        dt_bonus_end AS bonus_end_date,
        hub AS business_unit_id,
        bonus_value AS bonus_fee
    FROM
        datalake_gsheets_clean.negotiation_executive_bonus
),
cte_final AS (
    SELECT * FROM cte_ev
    UNION ALL
    SELECT * FROM cte_en
)

SELECT *,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day
FROM
    cte_final
