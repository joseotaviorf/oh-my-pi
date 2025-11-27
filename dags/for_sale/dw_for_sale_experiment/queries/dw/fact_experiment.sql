SELECT
    id_neotribe || '_' || id_experiment || '_' || identifier AS sk_element_exp,
    id_neotribe || '_' || id_experiment AS sk_neotribe_exp,
    id_neotribe AS sk_neotribe,
    id_experiment AS sk_experiment,
    identifier AS sk_identifier,
    identifier_type,
    test_group,
    dt_identifier_started
FROM
    datalake_for_sale_experiment.exp_1_1_visits_boosting_agents
