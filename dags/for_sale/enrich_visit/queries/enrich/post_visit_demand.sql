WITH agent AS (
    SELECT
        r.id_reviewed,
        CAST(rf.rating_selected[0] AS INTEGER) AS agent_rating,
        rf.comment as agent_rating_comment,
        r.dt_creation
    FROM
        datalake_insider_clean.review_feature AS rf
    LEFT JOIN
        datalake_insider_clean.review AS r
            ON rf.id_review = r.id
    LEFT JOIN
        datalake_insider_clean.feature AS f
            ON rf.id_feature = f.id
    WHERE
        r.type = 'post_visit_agent_rating'
        AND f.id IN (114, 117)
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY r.id_reviewed ORDER BY r.dt_creation DESC) = 1
),
agent_improvement AS (
    SELECT
        r.id_reviewed,
        rf.rating_selected AS agent_improvements,
        IF(array_contains(agent_improvements, 'thoughtfulness') OR array_contains(agent_improvements, 'Ser mais gentil e/ou atencioso'), TRUE, FALSE) AS agent_improvement_thoughtfulness,
        IF(array_contains(agent_improvements, 'punctuality') OR array_contains(agent_improvements, 'Ser mais pontual'), TRUE, FALSE) AS agent_improvement_punctuality,
        IF(array_contains(agent_improvements, 'house_features_knowledge') OR array_contains(agent_improvements, 'Ter mais conhecimento sobre o imóvel, condomínio e/ou região'), TRUE, FALSE) AS agent_improvement_house_features_knowledge,
        IF(array_contains(agent_improvements, 'rent_sale_process_knowledge') OR array_contains(agent_improvements, 'Ter mais conhecimento sobre o processo de aluguel ou venda'), TRUE, FALSE) AS agent_improvement_rent_sale_process_knowledge,
        IF(array_contains(agent_improvements, 'get_in_touch') OR array_contains(agent_improvements, 'Entrar em contato comigo'), TRUE, FALSE) AS agent_improvement_get_in_touch,
        IF(array_contains(agent_improvements, 'other') OR array_contains(agent_improvements, 'Outro'), TRUE, FALSE) AS agent_improvement_other,
        IF(array_contains(agent_improvements, 'bypass_attempt') OR array_contains(agent_improvements, 'Evitar a sugestão de negociar fora do QuintoAndar'), TRUE, FALSE) AS agent_improvement_bypass_attempt
    FROM
        datalake_insider_clean.review_feature AS rf
    LEFT JOIN
        datalake_insider_clean.review AS r
            ON rf.id_review = r.id
    LEFT JOIN
        datalake_insider_clean.feature AS f
            ON rf.id_feature = f.id
    WHERE
        r.type = 'post_visit_agent_rating'
        AND f.id IN (121, 118, 120, 115)
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY r.id_reviewed ORDER BY r.dt_creation DESC) = 1
),
agent_good_point AS (
    SELECT
        r.id_reviewed,
        rf.rating_selected AS agent_good_points,
        IF(array_contains(agent_good_points, 'thoughtfulness') OR array_contains(agent_good_points, 'Gentileza, respeito e atenção'), TRUE, FALSE) AS agent_good_thoughtfulness,
        IF(array_contains(agent_good_points, 'punctuality') OR array_contains(agent_good_points, 'Pontualidade'), TRUE, FALSE) AS agent_good_punctuality,
        IF(array_contains(agent_good_points, 'house_features_knowledge') OR array_contains(agent_good_points, 'Conhecimento sobre o imóvel, condomínio e/ou região'), TRUE, FALSE) AS agent_good_house_features_knowledge,
        IF(array_contains(agent_good_points, 'rent_sale_process_knowledge') OR array_contains(agent_good_points, 'Conhecimento sobre o processo de aluguel e venda'), TRUE, FALSE) AS agent_good_rent_sale_process_knowledge,
        IF(array_contains(agent_good_points, 'other') OR array_contains(agent_good_points, 'Outro'), TRUE, FALSE) as agent_good_other
    FROM
        datalake_insider_clean.review_feature AS rf
    LEFT JOIN
        datalake_insider_clean.review AS r
            ON rf.id_review = r.id
    LEFT JOIN
        datalake_insider_clean.feature f
            ON rf.id_feature = f.id
    WHERE
        r.type = 'post_visit_agent_rating'
        AND f.id IN (116, 119)
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY r.id_reviewed ORDER BY r.dt_creation DESC) = 1
),
agent_evaluation AS (
    SELECT
        SPLIT_PART(agent.id_reviewed, '-', 1) as visit_code,
        agent.agent_rating,
        agent.agent_rating_comment,
        ai.agent_improvements,
        agp.agent_good_points,
        CASE
            WHEN ai.agent_improvement_thoughtfulness THEN 'NEEDS_IMPROVEMENT'
            WHEN agp.agent_good_thoughtfulness THEN 'GOOD'
            ELSE NULL
        END AS agent_thoughtfulness,
        CASE
            WHEN ai.agent_improvement_punctuality THEN 'NEEDS_IMPROVEMENT'
            WHEN agp.agent_good_punctuality THEN 'GOOD'
            ELSE NULL
        END AS agent_punctuality,
        CASE
            WHEN ai.agent_improvement_house_features_knowledge THEN 'NEEDS_IMPROVEMENT'
            WHEN agp.agent_good_house_features_knowledge THEN 'GOOD'
            ELSE NULL
        END AS agent_house_features_knowledge,
        CASE
            WHEN ai.agent_improvement_rent_sale_process_knowledge THEN 'NEEDS_IMPROVEMENT'
            WHEN agp.agent_good_rent_sale_process_knowledge THEN 'GOOD'
            ELSE NULL
        END AS agent_rent_sale_process_knowledge,
        IF(ai.agent_improvement_get_in_touch, 'NEEDS_IMPROVEMENT', NULL) AS agent_get_in_touch,
        CASE
            WHEN ai.agent_improvement_other THEN 'NEEDS_IMPROVEMENT'
            WHEN agp.agent_good_other THEN 'GOOD'
            ELSE NULL
        END AS agent_other,
        IF(ai.agent_improvement_bypass_attempt, 'NEEDS_IMPROVEMENT', NULL) AS agent_bypass_attempt,
        agent.dt_creation
    FROM
        agent
    LEFT JOIN
        agent_improvement AS ai
            ON agent.id_reviewed = ai.id_reviewed
    LEFT JOIN
        agent_good_point AS agp
            ON agent.id_reviewed = agp.id_reviewed
),
house AS (
    SELECT
        r.id_reviewed,
        rf.rating_selected[0] AS house_rating,
        rf.comment as house_rating_comment,
        r.dt_creation
    FROM
        datalake_insider_clean.review_feature AS rf
    LEFT JOIN
        datalake_insider_clean.review AS r
            ON rf.id_review = r.id
    LEFT JOIN
        datalake_insider_clean.feature AS f
            ON rf.id_feature = f.id
    WHERE
        r.type = 'post_visit_house_rating'
        AND f.id = 111
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY r.id_reviewed ORDER BY r.dt_creation DESC) = 1
),
house_improvement AS (
    SELECT
        r.id_reviewed,
        rf.rating_selected AS house_improvements,
        IF(array_contains(house_improvements, 'location') OR array_contains(house_improvements, 'Localização'), TRUE, FALSE) AS house_improvement_location,
        IF(array_contains(house_improvements, 'house_conservation') OR array_contains(house_improvements, 'Conservação do imóvel'), TRUE, FALSE) AS house_improvement_house_conservation,
        IF(array_contains(house_improvements, 'neighborhood') OR array_contains(house_improvements, 'Vizinhança'), TRUE, FALSE) AS house_improvement_neighborhood,
        IF(array_contains(house_improvements, 'cost_benefit') OR array_contains(house_improvements, 'Custo-benefício'), TRUE, FALSE) AS house_improvement_cost_benefit,
        IF(array_contains(house_improvements, 'condominium_features') OR array_contains(house_improvements, 'Características do condomínio'), TRUE, FALSE) AS house_improvement_condominium_features,
        IF(array_contains(house_improvements, 'add_discrepancies') OR array_contains(house_improvements, 'Características diferentes do anúncio'), TRUE, FALSE) AS house_improvement_ad_discrepancies
    FROM
        datalake_insider_clean.review_feature AS rf
    LEFT JOIN
        datalake_insider_clean.review AS r
            ON rf.id_review = r.id
    LEFT JOIN
        datalake_insider_clean.feature AS f
            ON rf.id_feature = f.id
    WHERE
        r.type = 'post_visit_house_rating'
        AND f.id = 112
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY r.id_reviewed ORDER BY r.dt_creation DESC) = 1
),
house_good_point AS (
    SELECT
        r.id_reviewed,
        rf.rating_selected AS house_good_points,
        IF(array_contains(house_good_points, 'location') OR array_contains(house_good_points, 'Localização'), TRUE, FALSE) AS house_good_location,
        IF(array_contains(house_good_points, 'house_conservation') OR array_contains(house_good_points, 'Conservação do imóvel'), TRUE, FALSE) AS house_good_house_conservation,
        IF(array_contains(house_good_points, 'neighborhood') OR array_contains(house_good_points, 'Vizinhança'), TRUE, FALSE) AS house_good_neighborhood,
        IF(array_contains(house_good_points, 'cost_benefit') OR array_contains(house_good_points, 'Custo-benefício'), TRUE, FALSE) AS house_good_cost_benefit,
        IF(array_contains(house_good_points, 'condominium_features') OR array_contains(house_good_points, 'Características do condomínio'), TRUE, FALSE) AS house_good_condominium_features
    FROM
        datalake_insider_clean.review_feature AS rf
    LEFT JOIN
        datalake_insider_clean.review AS r
            ON rf.id_review = r.id
    LEFT JOIN
        datalake_insider_clean.feature AS f
            ON rf.id_feature = f.id
    WHERE
        r.type = 'post_visit_house_rating'
        AND f.id = 113
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY r.id_reviewed ORDER BY r.dt_creation DESC) = 1
),
house_evaluation AS (
    SELECT
        SPLIT_PART(house.id_reviewed, '-', 1) AS visit_code,
        house.house_rating,
        house.house_rating_comment,
        hi.house_improvements,
        hgp.house_good_points,
        CASE
            WHEN hi.house_improvement_location THEN 'NEEDS_IMPROVEMENT'
            WHEN hgp.house_good_location THEN 'GOOD'
            ELSE NULL
        END AS house_location,
        CASE
            WHEN hi.house_improvement_house_conservation THEN 'NEEDS_IMPROVEMENT'
            WHEN hgp.house_good_house_conservation THEN 'GOOD'
            ELSE NULL
        END AS house_conservation,
        CASE
            WHEN hi.house_improvement_neighborhood THEN 'NEEDS_IMPROVEMENT'
            WHEN hgp.house_good_neighborhood THEN 'GOOD'
            ELSE NULL
        END AS house_neighborhood,
        CASE
            WHEN hi.house_improvement_cost_benefit THEN 'NEEDS_IMPROVEMENT'
            WHEN hgp.house_good_cost_benefit THEN 'GOOD'
            ELSE NULL
        END AS house_cost_benefit,
        CASE
            WHEN hi.house_improvement_condominium_features THEN 'NEEDS_IMPROVEMENT'
            WHEN hgp.house_good_condominium_features THEN 'GOOD'
            ELSE NULL
        END AS house_condominium_features,
        IF(hi.house_improvement_ad_discrepancies, 'NEEDS_IMPROVEMENT', NULL) AS house_ad_discrepancies,
        house.dt_creation
    FROM
        house
    LEFT JOIN
        house_improvement AS hi
            ON house.id_reviewed = hi.id_reviewed
    LEFT JOIN
        house_good_point AS hgp
            ON house.id_reviewed = hgp.id_reviewed
)
SELECT
    v.id AS id_visit,
    COALESCE(agent.visit_code, house.visit_code) AS visit_code,
    agent.agent_rating,
    agent.agent_rating_comment,
    house.house_rating,
    house.house_rating_comment,
    agent.agent_improvements,
    agent.agent_good_points,
    agent.agent_thoughtfulness,
    agent.agent_punctuality,
    agent.agent_house_features_knowledge,
    agent.agent_rent_sale_process_knowledge,
    agent.agent_get_in_touch,
    agent.agent_other,
    agent.agent_bypass_attempt,
    house.house_improvements,
    house.house_good_points,
    house.house_location,
    house.house_conservation,
    house.house_neighborhood,
    house.house_cost_benefit,
    house.house_condominium_features,
    house.house_ad_discrepancies,
    CASE
        WHEN agent.visit_code IS NOT NULL AND house.visit_code IS NOT NULL THEN 'AGENT_HOUSE'
        WHEN agent.visit_code IS NULL AND house.visit_code IS NOT NULL THEN 'HOUSE'
        WHEN agent.visit_code IS NOT NULL AND house.visit_code IS NULL THEN 'AGENT'
    END AS evaluation_domain,
    COALESCE(agent.dt_creation, house.dt_creation) AS ts_creation
FROM
    agent_evaluation AS agent
FULL OUTER JOIN
    house_evaluation AS house
        ON agent.visit_code = house.visit_code
JOIN
    datalake_ebdb_clean.visit AS v
        ON v.code = COALESCE(agent.visit_code, house.visit_code)
