WITH agent AS (
    SELECT
        r.id_reviewed,
        CAST(rf.rating_selected[0] AS INTEGER) AS agent_rating,
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
        rf.rating_selected AS agent_improvements
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
        rf.rating_selected AS agent_good_points
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
        SPLIT_PART(agent.id_reviewed, '-', 1) as code_visit,
        agent.agent_rating,
        ai.agent_improvements,
        agp.agent_good_points,
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
        rf.rating_selected[0] AS house_like,
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
house_negative AS (
    SELECT
        r.id_reviewed,
        rf.rating_selected AS house_negative_points
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
house_positive AS (
    SELECT
        r.id_reviewed,
        rf.rating_selected AS house_positive_points
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
        SPLIT_PART(house.id_reviewed, '-', 1) AS code_visit,
        house.house_like,
        hn.house_negative_points,
        hp.house_positive_points,
        house.dt_creation
    FROM
        house
    LEFT JOIN
        house_negative AS hn
            ON house.id_reviewed = hn.id_reviewed
    LEFT JOIN
        house_positive AS hp
            ON house.id_reviewed = hp.id_reviewed
)
SELECT
    v.id AS id_visit,
    COALESCE(agent.code_visit, house.code_visit) AS code_visit,
    agent.agent_rating,
    house.house_like,
    agent.agent_improvements,
    agent.agent_good_points,
    house.house_negative_points,
    house.house_positive_points,
    CASE
        WHEN agent.code_visit IS NOT NULL AND house.code_visit IS NOT NULL THEN 'AGENT_HOUSE'
        WHEN agent.code_visit IS NULL AND house.code_visit IS NOT NULL THEN 'HOUSE'
        WHEN agent.code_visit IS NOT NULL AND house.code_visit IS NULL THEN 'AGENT'
    END AS evaluation_domain,
    COALESCE(agent.dt_creation, house.dt_creation) AS ts_creation
FROM
    agent_evaluation AS agent
FULL OUTER JOIN
    house_evaluation AS house
        ON agent.code_visit = house.code_visit
JOIN
    datalake_ebdb_clean.visit AS v
        ON v.code = COALESCE(agent.code_visit, house.code_visit)
