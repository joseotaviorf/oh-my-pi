SELECT
    id_element_exp AS sk_element_exp,
    CONCAT_WS('_', id_neotribe, id_experiment, business_context) AS sk_neotribe_exp,
    id_neotribe AS sk_neotribe,
    id_experiment AS sk_experiment,
    identifier AS sk_identifier,
    identifier_type,
    test_group,
    dt_identifier_started
FROM
    datalake_for_sale_experiment.exp_visitor_identifier
