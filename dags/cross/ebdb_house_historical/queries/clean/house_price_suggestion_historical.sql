WITH values_updates AS (
    SELECT
        id,
        house_id,
        prediction_id,
        STRUCT(
            deal_objective_lower_anchor,
            deal_objective_upper_anchor,
            lower_bound_limit,
            rule,
            suggested_lower_bound_price,
            suggested_price,
            suggested_upper_bound_price,
            suggestion_certainty,
            upper_bound_limit
        ) AS current_values,
        LEAD(
            STRUCT(
                deal_objective_lower_anchor,
                deal_objective_upper_anchor,
                lower_bound_limit,
                rule,
                suggested_lower_bound_price,
                suggested_price,
                suggested_upper_bound_price,
                suggestion_certainty,
                upper_bound_limit
            )
        ) OVER(PARTITION BY id ORDER BY ts_cdc_transaction, cdc_transaction_id) AS next_values,
        business_context,
        op_cdc,
        created_at,
        updated_at,
        ts_cdc_transaction,
        ts_database_transaction,
        year,
        month,
        day
    FROM
        datalake_ebdb_transactional.HousePriceSuggestion
    WHERE
        op_cdc IN ('r', 'c', 'u')
        AND MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
    id,
    house_id AS id_house,
    prediction_id AS id_prediction,
    current_values.deal_objective_lower_anchor,
    current_values.deal_objective_upper_anchor,
    current_values.lower_bound_limit,
    current_values.rule,
    current_values.suggested_lower_bound_price,
    current_values.suggested_price,
    current_values.suggested_upper_bound_price,
    current_values.suggestion_certainty,
    current_values.upper_bound_limit,
    business_context,
    op_cdc,
    created_at AS ts_created,
    updated_at AS ts_updated,
    ts_cdc_transaction,
    ts_database_transaction,
    year,
    month,
    day
FROM
    values_updates
WHERE
    next_values IS NULL
    OR current_values IS DISTINCT FROM next_values
