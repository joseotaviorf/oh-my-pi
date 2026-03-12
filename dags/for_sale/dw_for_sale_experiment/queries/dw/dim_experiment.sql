SELECT
    CONCAT_WS('_', id_neotribe, id_experiment, business_context) AS sk_neotribe_exp,
    id_neotribe AS sk_neotribe,
    id_experiment AS sk_experiment,
    name_neotribe,
    name_experiment,
    identifier_type,
    business_context,
    documentation_link,
    additional_information,
    MIN(dt_identifier_started) AS dt_started,
    MAX(dt_identifier_ended) AS dt_ended
FROM
    datalake_for_sale_experiment.exp_identifier_unified
GROUP BY 1,2,3,4,5,6,7,8,9
