SELECT
    id,
    house_id AS id_house,
    prediction_id AS id_prediction,
    business_context,
    lower_bound_limit,
    upper_bound_limit,
    suggested_lower_bound_price,
    suggested_upper_bound_price,
    suggested_price,
    deal_objective_lower_anchor,
    deal_objective_upper_anchor,
    suggestion_certainty,
    rule,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_ebdb_raw.HousePriceSuggestion
