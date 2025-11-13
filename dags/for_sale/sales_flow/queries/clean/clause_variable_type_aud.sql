SELECT
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    input_type,
    input_type_mod AS mod_input_type,
    element,
    element_mod AS mod_element,
    options,
    options_mod AS mod_options,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.clause_variable_type_aud
