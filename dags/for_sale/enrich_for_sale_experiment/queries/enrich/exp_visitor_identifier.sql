SELECT
    CONCAT_WS('_', id_neotribe, id_experiment, identifier_bc) AS id_element_exp,
    identifier,
    id_neotribe,
    id_experiment,
    name_neotribe,
    name_experiment,
    identifier_type,
    business_context,
    test_group,
    documentation_link,
    additional_information,
    dt_identifier_started,
    dt_identifier_ended
FROM
    datalake_for_sale_experiment.exp_1_1_visits_boosting_agents
UNION ALL
SELECT
    CONCAT_WS('_', id_neotribe, id_experiment, identifier_bc) AS id_element_exp,
    identifier,
    id_neotribe,
    id_experiment,
    name_neotribe,
    name_experiment,
    identifier_type,
    business_context,
    test_group,
    documentation_link,
    additional_information,
    dt_identifier_started,
    dt_identifier_ended
FROM
    datalake_for_sale_experiment.exp_1_2_visits_boosting_agents_area_increased_to_800m
UNION ALL
SELECT
    CONCAT_WS('_', id_neotribe, id_experiment, identifier_bc) AS id_element_exp,
    identifier,
    id_neotribe,
    id_experiment,
    name_neotribe,
    name_experiment,
    identifier_type,
    business_context,
    test_group,
    documentation_link,
    additional_information,
    dt_identifier_started,
    dt_identifier_ended
FROM
    datalake_for_sale_experiment.exp_1_3_visits_confirmation_agent
UNION ALL
SELECT
    CONCAT_WS('_', id_neotribe, id_experiment, identifier_bc) AS id_element_exp,
    identifier,
    id_neotribe,
    id_experiment,
    name_neotribe,
    name_experiment,
    identifier_type,
    business_context,
    test_group,
    documentation_link,
    additional_information,
    dt_identifier_started,
    dt_identifier_ended
FROM
    datalake_for_sale_experiment.exp_1_4_visits_confirmation_agent_jan13th_onward
