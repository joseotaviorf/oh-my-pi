SELECT DISTINCT
    id_neotribe || '_' || id_experiment AS sk_neotribe_exp,
    id_neotribe AS sk_neotribe,
    id_experiment AS sk_experiment,
    name_neotribe,
    name_experiment,
    identifier_type,
    business_context,
    documentation_link,
    additional_information,
    dt_started,
    dt_ended
FROM
    datalake_for_sale_experiment.exp_1_1_visits_boosting_agents
