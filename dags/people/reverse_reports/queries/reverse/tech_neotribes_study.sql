-- Active engineering SWE/data roster unpivoted across up to five Neotribes team assignments.
WITH cost_center_label AS (
    SELECT
        es.assignment_number,
        CONCAT(
            LOWER(es.cost_center_code),
            ' - ',
            SUBSTRING(LOWER(es.cost_center_name), 10)
        ) AS cost_center_label
    FROM
        metric_people.employee_snapshots AS es
    WHERE
        es.is_current = TRUE
        AND es.is_primary_assignment_for_snapshot = TRUE
),
neotribes_template AS (
    SELECT
        es.assignment_number,
        es.person_number,
        es.work_email AS email,
        es.name AS nome,
        es.dt_employee_hired AS data_entrada,
        es.manager_name AS gestor,
        es.job_name AS cargo,
        es.band AS banda,
        cc.cost_center_label AS centro_de_custo,
        es.chapter,
        es.talent_readiness AS prontidao,
        es.talent_potential AS potencial,
        es.name_l1 AS layer1,
        es.name_l2 AS layer2,
        es.name_l3 AS layer3,
        es.name_l4 AS layer4,
        es.name_l5 AS layer5,
        CAST(NULL AS STRING) AS tenure_gestao,
        CAST(NULL AS STRING) AS tenure_cargo,
        tf.team_1 AS team_1_primary,
        tf.team_2,
        tf.team_3,
        tf.team_4,
        tf.team_5,
        CASE
            WHEN es.band <= 6 THEN 'a. SWEs 1 & 2'
            WHEN es.band = 7 THEN 'b. SWEs 3'
            WHEN es.band = 8 THEN 'c. SWEs 4'
            ELSE 'd. SWEs 5+'
        END AS senioridade
    FROM
        metric_people.employee_snapshots AS es
    LEFT JOIN
        cost_center_label AS cc
            ON cc.assignment_number = es.assignment_number
    LEFT JOIN
        datalake_gsheets_people_clean.team_formation_product_tech AS tf
            ON LOWER(tf.assignment_number) = LOWER(es.assignment_number)
    WHERE
        es.is_current = TRUE
        AND es.is_primary_assignment_for_snapshot = TRUE
        AND LOWER(es.status) = 'active'
        AND LOWER(es.chapter) = 'engineering'
        AND (
            LOWER(es.job_name) LIKE '%engenheiro de software%'
            OR LOWER(es.job_name) LIKE '%cientista de dados%'
            OR LOWER(es.job_name) LIKE '%machine learning engineer%'
            OR LOWER(es.job_name) LIKE '%data scientist%'
        )
),
unpivoted_teams AS (
    SELECT
        nt.assignment_number,
        nt.person_number,
        nt.email,
        nt.nome,
        nt.data_entrada,
        nt.gestor,
        nt.cargo,
        nt.banda,
        nt.centro_de_custo,
        nt.chapter,
        nt.prontidao,
        nt.potencial,
        nt.layer1,
        nt.layer2,
        nt.layer3,
        nt.layer4,
        nt.layer5,
        nt.tenure_gestao,
        nt.tenure_cargo,
        nt.team_1_primary AS team_1_primary,
        nt.senioridade
    FROM
        neotribes_template AS nt
    WHERE
        nt.team_1_primary IS NOT NULL
    UNION ALL
    SELECT
        nt.assignment_number,
        nt.person_number,
        nt.email,
        nt.nome,
        nt.data_entrada,
        nt.gestor,
        nt.cargo,
        nt.banda,
        nt.centro_de_custo,
        nt.chapter,
        nt.prontidao,
        nt.potencial,
        nt.layer1,
        nt.layer2,
        nt.layer3,
        nt.layer4,
        nt.layer5,
        nt.tenure_gestao,
        nt.tenure_cargo,
        nt.team_2 AS team_1_primary,
        nt.senioridade
    FROM
        neotribes_template AS nt
    WHERE
        nt.team_2 IS NOT NULL
    UNION ALL
    SELECT
        nt.assignment_number,
        nt.person_number,
        nt.email,
        nt.nome,
        nt.data_entrada,
        nt.gestor,
        nt.cargo,
        nt.banda,
        nt.centro_de_custo,
        nt.chapter,
        nt.prontidao,
        nt.potencial,
        nt.layer1,
        nt.layer2,
        nt.layer3,
        nt.layer4,
        nt.layer5,
        nt.tenure_gestao,
        nt.tenure_cargo,
        nt.team_3 AS team_1_primary,
        nt.senioridade
    FROM
        neotribes_template AS nt
    WHERE
        nt.team_3 IS NOT NULL
    UNION ALL
    SELECT
        nt.assignment_number,
        nt.person_number,
        nt.email,
        nt.nome,
        nt.data_entrada,
        nt.gestor,
        nt.cargo,
        nt.banda,
        nt.centro_de_custo,
        nt.chapter,
        nt.prontidao,
        nt.potencial,
        nt.layer1,
        nt.layer2,
        nt.layer3,
        nt.layer4,
        nt.layer5,
        nt.tenure_gestao,
        nt.tenure_cargo,
        nt.team_4 AS team_1_primary,
        nt.senioridade
    FROM
        neotribes_template AS nt
    WHERE
        nt.team_4 IS NOT NULL
    UNION ALL
    SELECT
        nt.assignment_number,
        nt.person_number,
        nt.email,
        nt.nome,
        nt.data_entrada,
        nt.gestor,
        nt.cargo,
        nt.banda,
        nt.centro_de_custo,
        nt.chapter,
        nt.prontidao,
        nt.potencial,
        nt.layer1,
        nt.layer2,
        nt.layer3,
        nt.layer4,
        nt.layer5,
        nt.tenure_gestao,
        nt.tenure_cargo,
        nt.team_5 AS team_1_primary,
        nt.senioridade
    FROM
        neotribes_template AS nt
    WHERE
        nt.team_5 IS NOT NULL
)
SELECT
    LOWER(ut.assignment_number) AS assignment_number,
    ut.person_number,
    LOWER(ut.email) AS email,
    LOWER(ut.nome) AS nome,
    ut.data_entrada,
    LOWER(ut.gestor) AS gestor,
    LOWER(ut.cargo) AS cargo,
    ut.banda,
    LOWER(ut.centro_de_custo) AS centro_de_custo,
    LOWER(ut.chapter) AS chapter,
    LOWER(ut.prontidao) AS prontidao,
    LOWER(ut.potencial) AS potencial,
    LOWER(ut.layer1) AS layer1,
    LOWER(ut.layer2) AS layer2,
    LOWER(ut.layer3) AS layer3,
    LOWER(ut.layer4) AS layer4,
    LOWER(ut.layer5) AS layer5,
    ut.tenure_gestao,
    ut.tenure_cargo,
    LOWER(ut.team_1_primary) AS team_1_primary,
    ut.senioridade,
    YEAR(DATE('{load_start_date}')) AS year,
    MONTH(DATE('{load_start_date}')) AS month,
    DAY(DATE('{load_start_date}')) AS day
FROM
    unpivoted_teams AS ut
