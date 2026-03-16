WITH ceo_history AS (
    SELECT
        aa.assignment_number,
        GREATEST(aa.dt_effective_started, j.dt_valid_from) AS dt_from,
        LEAST(
            COALESCE(aa.dt_effective_ended, DATE('9999-12-31')),
            COALESCE(j.dt_valid_to, DATE('9999-12-31'))
        ) AS dt_to
    FROM
        datalake_pin_core_clean.all_assignments AS aa
    INNER JOIN
        datalake_people.job_with_salary_table AS j
        ON aa.id_job = j.id_job
        AND aa.dt_effective_started <= COALESCE(j.dt_valid_to, DATE('9999-12-31'))
        AND COALESCE(aa.dt_effective_ended, DATE('9999-12-31')) >= j.dt_valid_from
    WHERE
        TRY_CAST(j.band AS INT) = (
            SELECT MAX(TRY_CAST(band AS INT))
            FROM datalake_people.job_with_salary_table
            WHERE TRY_CAST(band AS INT) IS NOT NULL
        )
),
filtered_managers_history AS (
    SELECT DISTINCT
        id_map_emp.assignment_number,
        id_map_mgr.assignment_number AS manager_assignment_number,
        supervisor.dt_effective_started,
        supervisor.dt_effective_ended
    FROM
        datalake_people.identifier_mapping AS id_map_emp
    INNER JOIN
        datalake_pin_core_clean.assignment_supervisor AS supervisor
        ON id_map_emp.id_assignment = supervisor.id_assignment
    LEFT JOIN
        datalake_people.identifier_mapping AS id_map_mgr
        ON id_map_mgr.id_assignment = supervisor.id_manager_assignment
    WHERE
        supervisor.is_primary
        AND supervisor.manager_type = 'LINE_MANAGER'
        AND supervisor.dt_effective_started <= CURRENT_DATE
        AND NOT supervisor.id_manager_assignment IS NULL
        AND NOT id_map_emp.is_user_test
        AND NOT id_map_mgr.is_user_test
),
level_1 AS (
    SELECT
        assignment_number,
        manager_assignment_number AS manager_assignment_number_1,
        dt_effective_started AS dt_valid_from,
        dt_effective_ended AS dt_valid_to
    FROM
        filtered_managers_history
),
level_2 AS (
    SELECT DISTINCT
        lvl_1.assignment_number,
        lvl_1.manager_assignment_number_1,
        mgr_history.manager_assignment_number AS manager_assignment_number_2,
        GREATEST(lvl_1.dt_valid_from, mgr_history.dt_effective_started) AS dt_valid_from,
        LEAST(lvl_1.dt_valid_to, mgr_history.dt_effective_ended) AS dt_valid_to
    FROM
        level_1 AS lvl_1
    INNER JOIN
        filtered_managers_history AS mgr_history
        ON lvl_1.manager_assignment_number_1 = mgr_history.assignment_number
    WHERE
        lvl_1.dt_valid_to >= mgr_history.dt_effective_started
        AND mgr_history.dt_effective_ended >= lvl_1.dt_valid_from
),
level_3 AS (
    SELECT DISTINCT
        lvl_2.assignment_number,
        lvl_2.manager_assignment_number_1,
        lvl_2.manager_assignment_number_2,
        mgr_history.manager_assignment_number AS manager_assignment_number_3,
        GREATEST(lvl_2.dt_valid_from, mgr_history.dt_effective_started) AS dt_valid_from,
        LEAST(lvl_2.dt_valid_to, mgr_history.dt_effective_ended) AS dt_valid_to
    FROM
        level_2 AS lvl_2
    INNER JOIN
        filtered_managers_history AS mgr_history
        ON lvl_2.manager_assignment_number_2 = mgr_history.assignment_number
    WHERE
        lvl_2.dt_valid_to >= mgr_history.dt_effective_started
        AND mgr_history.dt_effective_ended >= lvl_2.dt_valid_from
),
level_4 AS (
    SELECT DISTINCT
        lvl_3.assignment_number,
        lvl_3.manager_assignment_number_1,
        lvl_3.manager_assignment_number_2,
        lvl_3.manager_assignment_number_3,
        mgr_history.manager_assignment_number AS manager_assignment_number_4,
        GREATEST(lvl_3.dt_valid_from, mgr_history.dt_effective_started) AS dt_valid_from,
        LEAST(lvl_3.dt_valid_to, mgr_history.dt_effective_ended) AS dt_valid_to
    FROM
        level_3 AS lvl_3
    INNER JOIN
        filtered_managers_history AS mgr_history
        ON lvl_3.manager_assignment_number_3 = mgr_history.assignment_number
    WHERE
        lvl_3.dt_valid_to >= mgr_history.dt_effective_started
        AND mgr_history.dt_effective_ended >= lvl_3.dt_valid_from
),
level_5 AS (
    SELECT DISTINCT
        lvl_4.assignment_number,
        lvl_4.manager_assignment_number_1,
        lvl_4.manager_assignment_number_2,
        lvl_4.manager_assignment_number_3,
        lvl_4.manager_assignment_number_4,
        mgr_history.manager_assignment_number AS manager_assignment_number_5,
        GREATEST(lvl_4.dt_valid_from, mgr_history.dt_effective_started) AS dt_valid_from,
        LEAST(lvl_4.dt_valid_to, mgr_history.dt_effective_ended) AS dt_valid_to
    FROM
        level_4 AS lvl_4
    INNER JOIN
        filtered_managers_history AS mgr_history
        ON lvl_4.manager_assignment_number_4 = mgr_history.assignment_number
    WHERE
        lvl_4.dt_valid_to >= mgr_history.dt_effective_started
        AND mgr_history.dt_effective_ended >= lvl_4.dt_valid_from
),
level_6 AS (
    SELECT DISTINCT
        lvl_5.assignment_number,
        lvl_5.manager_assignment_number_1,
        lvl_5.manager_assignment_number_2,
        lvl_5.manager_assignment_number_3,
        lvl_5.manager_assignment_number_4,
        lvl_5.manager_assignment_number_5,
        mgr_history.manager_assignment_number AS manager_assignment_number_6,
        GREATEST(lvl_5.dt_valid_from, mgr_history.dt_effective_started) AS dt_valid_from,
        LEAST(lvl_5.dt_valid_to, mgr_history.dt_effective_ended) AS dt_valid_to
    FROM
        level_5 AS lvl_5
    INNER JOIN
        filtered_managers_history AS mgr_history
        ON lvl_5.manager_assignment_number_5 = mgr_history.assignment_number
    WHERE
        lvl_5.dt_valid_to >= mgr_history.dt_effective_started
        AND mgr_history.dt_effective_ended >= lvl_5.dt_valid_from
),
level_7 AS (
    SELECT DISTINCT
        lvl_6.assignment_number,
        lvl_6.manager_assignment_number_1,
        lvl_6.manager_assignment_number_2,
        lvl_6.manager_assignment_number_3,
        lvl_6.manager_assignment_number_4,
        lvl_6.manager_assignment_number_5,
        lvl_6.manager_assignment_number_6,
        mgr_history.manager_assignment_number AS manager_assignment_number_7,
        GREATEST(lvl_6.dt_valid_from, mgr_history.dt_effective_started) AS dt_valid_from,
        LEAST(lvl_6.dt_valid_to, mgr_history.dt_effective_ended) AS dt_valid_to
    FROM
        level_6 AS lvl_6
    INNER JOIN
        filtered_managers_history AS mgr_history
        ON lvl_6.manager_assignment_number_6 = mgr_history.assignment_number
    WHERE
        lvl_6.dt_valid_to >= mgr_history.dt_effective_started
        AND mgr_history.dt_effective_ended >= lvl_6.dt_valid_from
),
level_8 AS (
    SELECT DISTINCT
        lvl_7.assignment_number,
        lvl_7.manager_assignment_number_1,
        lvl_7.manager_assignment_number_2,
        lvl_7.manager_assignment_number_3,
        lvl_7.manager_assignment_number_4,
        lvl_7.manager_assignment_number_5,
        lvl_7.manager_assignment_number_6,
        lvl_7.manager_assignment_number_7,
        mgr_history.manager_assignment_number AS manager_assignment_number_8,
        GREATEST(lvl_7.dt_valid_from, mgr_history.dt_effective_started) AS dt_valid_from,
        LEAST(lvl_7.dt_valid_to, mgr_history.dt_effective_ended) AS dt_valid_to
    FROM
        level_7 AS lvl_7
    INNER JOIN
        filtered_managers_history AS mgr_history
        ON lvl_7.manager_assignment_number_7 = mgr_history.assignment_number
    WHERE
        lvl_7.dt_valid_to >= mgr_history.dt_effective_started
        AND mgr_history.dt_effective_ended >= lvl_7.dt_valid_from
),
level_9 AS (
    SELECT DISTINCT
        lvl_8.assignment_number,
        lvl_8.manager_assignment_number_1,
        lvl_8.manager_assignment_number_2,
        lvl_8.manager_assignment_number_3,
        lvl_8.manager_assignment_number_4,
        lvl_8.manager_assignment_number_5,
        lvl_8.manager_assignment_number_6,
        lvl_8.manager_assignment_number_7,
        lvl_8.manager_assignment_number_8,
        mgr_history.manager_assignment_number AS manager_assignment_number_9,
        GREATEST(lvl_8.dt_valid_from, mgr_history.dt_effective_started) AS dt_valid_from,
        LEAST(lvl_8.dt_valid_to, mgr_history.dt_effective_ended) AS dt_valid_to
    FROM
        level_8 AS lvl_8
    INNER JOIN
        filtered_managers_history AS mgr_history
        ON lvl_8.manager_assignment_number_8 = mgr_history.assignment_number
    WHERE
        lvl_8.dt_valid_to >= mgr_history.dt_effective_started
        AND mgr_history.dt_effective_ended >= lvl_8.dt_valid_from
),
level_10 AS (
    SELECT DISTINCT
        lvl_9.assignment_number,
        lvl_9.manager_assignment_number_1,
        lvl_9.manager_assignment_number_2,
        lvl_9.manager_assignment_number_3,
        lvl_9.manager_assignment_number_4,
        lvl_9.manager_assignment_number_5,
        lvl_9.manager_assignment_number_6,
        lvl_9.manager_assignment_number_7,
        lvl_9.manager_assignment_number_8,
        lvl_9.manager_assignment_number_9,
        mgr_history.manager_assignment_number AS manager_assignment_number_10,
        GREATEST(lvl_9.dt_valid_from, mgr_history.dt_effective_started) AS dt_valid_from,
        LEAST(lvl_9.dt_valid_to, mgr_history.dt_effective_ended) AS dt_valid_to
    FROM
        level_9 AS lvl_9
    INNER JOIN
        filtered_managers_history AS mgr_history
        ON lvl_9.manager_assignment_number_9 = mgr_history.assignment_number
    WHERE
        lvl_9.dt_valid_to >= mgr_history.dt_effective_started
        AND mgr_history.dt_effective_ended >= lvl_9.dt_valid_from
),
hierarchy_union AS (
    SELECT
        assignment_number,
        manager_assignment_number_1,
        NULL AS manager_assignment_number_2,
        NULL AS manager_assignment_number_3,
        NULL AS manager_assignment_number_4,
        NULL AS manager_assignment_number_5,
        NULL AS manager_assignment_number_6,
        NULL AS manager_assignment_number_7,
        NULL AS manager_assignment_number_8,
        NULL AS manager_assignment_number_9,
        NULL AS manager_assignment_number_10,
        dt_valid_from,
        dt_valid_to
    FROM
        level_1
    UNION ALL
    SELECT
        assignment_number,
        manager_assignment_number_1,
        manager_assignment_number_2,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        dt_valid_from,
        dt_valid_to
    FROM
        level_2
    UNION ALL
    SELECT
        assignment_number,
        manager_assignment_number_1,
        manager_assignment_number_2,
        manager_assignment_number_3,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        dt_valid_from,
        dt_valid_to
    FROM
        level_3
    UNION ALL
    SELECT
        assignment_number,
        manager_assignment_number_1,
        manager_assignment_number_2,
        manager_assignment_number_3,
        manager_assignment_number_4,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        dt_valid_from,
        dt_valid_to
    FROM
        level_4
    UNION ALL
    SELECT
        assignment_number,
        manager_assignment_number_1,
        manager_assignment_number_2,
        manager_assignment_number_3,
        manager_assignment_number_4,
        manager_assignment_number_5,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        dt_valid_from,
        dt_valid_to
    FROM
        level_5
    UNION ALL
    SELECT
        assignment_number,
        manager_assignment_number_1,
        manager_assignment_number_2,
        manager_assignment_number_3,
        manager_assignment_number_4,
        manager_assignment_number_5,
        manager_assignment_number_6,
        NULL,
        NULL,
        NULL,
        NULL,
        dt_valid_from,
        dt_valid_to
    FROM
        level_6
    UNION ALL
    SELECT
        assignment_number,
        manager_assignment_number_1,
        manager_assignment_number_2,
        manager_assignment_number_3,
        manager_assignment_number_4,
        manager_assignment_number_5,
        manager_assignment_number_6,
        manager_assignment_number_7,
        NULL,
        NULL,
        NULL,
        dt_valid_from,
        dt_valid_to
    FROM
        level_7
    UNION ALL
    SELECT
        assignment_number,
        manager_assignment_number_1,
        manager_assignment_number_2,
        manager_assignment_number_3,
        manager_assignment_number_4,
        manager_assignment_number_5,
        manager_assignment_number_6,
        manager_assignment_number_7,
        manager_assignment_number_8,
        NULL,
        NULL,
        dt_valid_from,
        dt_valid_to
    FROM
        level_8
    UNION ALL
    SELECT
        assignment_number,
        manager_assignment_number_1,
        manager_assignment_number_2,
        manager_assignment_number_3,
        manager_assignment_number_4,
        manager_assignment_number_5,
        manager_assignment_number_6,
        manager_assignment_number_7,
        manager_assignment_number_8,
        manager_assignment_number_9,
        NULL,
        dt_valid_from,
        dt_valid_to
    FROM
        level_9
    UNION ALL
    SELECT
        assignment_number,
        manager_assignment_number_1,
        manager_assignment_number_2,
        manager_assignment_number_3,
        manager_assignment_number_4,
        manager_assignment_number_5,
        manager_assignment_number_6,
        manager_assignment_number_7,
        manager_assignment_number_8,
        manager_assignment_number_9,
        manager_assignment_number_10,
        dt_valid_from,
        dt_valid_to
    FROM
        level_10
),
hierarchy_reordered AS (
    SELECT
        hu.assignment_number,
        hu.dt_valid_from,
        hu.dt_valid_to,
        CONCAT(
            REVERSE(
                FILTER(
                    ARRAY(
                        NAMED_STRUCT('assignment_number', hu.manager_assignment_number_1),
                        NAMED_STRUCT('assignment_number', hu.manager_assignment_number_2),
                        NAMED_STRUCT('assignment_number', hu.manager_assignment_number_3),
                        NAMED_STRUCT('assignment_number', hu.manager_assignment_number_4),
                        NAMED_STRUCT('assignment_number', hu.manager_assignment_number_5),
                        NAMED_STRUCT('assignment_number', hu.manager_assignment_number_6),
                        NAMED_STRUCT('assignment_number', hu.manager_assignment_number_7),
                        NAMED_STRUCT('assignment_number', hu.manager_assignment_number_8),
                        NAMED_STRUCT('assignment_number', hu.manager_assignment_number_9),
                        NAMED_STRUCT('assignment_number', hu.manager_assignment_number_10)
                    ),
                    s -> NOT s.assignment_number IS NULL
                )
            ),
            ARRAY(NAMED_STRUCT('assignment_number', hu.assignment_number))
        ) AS manager_struct_path
    FROM
        hierarchy_union AS hu
),
hierarchy_filtered AS (
    SELECT
        hr.assignment_number,
        hr.manager_struct_path,
        hr.dt_valid_from,
        hr.dt_valid_to,
        CASE
            WHEN CURRENT_DATE BETWEEN hr.dt_valid_from AND hr.dt_valid_to
            THEN TRUE
            ELSE FALSE
        END AS is_current
    FROM
        hierarchy_reordered AS hr
    INNER JOIN
        ceo_history AS ceo
        ON ceo.assignment_number = hr.manager_struct_path[0].assignment_number
        AND hr.dt_valid_from <= COALESCE(ceo.dt_to, DATE('9999-12-31'))
        AND COALESCE(hr.dt_valid_to, DATE('9999-12-31')) >= ceo.dt_from
    WHERE
        SIZE(hr.manager_struct_path) > 0
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY hr.assignment_number,
                hr.dt_valid_from,
                hr.dt_valid_to
            ORDER BY SIZE(hr.manager_struct_path) DESC
        ) = 1
),
hierarchy_with_sig AS (
    SELECT
        assignment_number,
        manager_struct_path,
        dt_valid_from,
        dt_valid_to,
        CASE
            WHEN CURRENT_DATE BETWEEN dt_valid_from AND dt_valid_to
            THEN TRUE
            ELSE FALSE
        END AS is_current,
        MD5(
            CONCAT_WS(
                '|',
                TRANSFORM(
                    manager_struct_path,
                    s -> COALESCE(CAST(s.assignment_number AS STRING), '')
                )
            )
        ) AS hierarchy_sig
    FROM
        hierarchy_filtered
),
hierarchy_with_island AS (
    SELECT
        *,
        SUM(
            CASE
                WHEN LAG(dt_valid_to) OVER (
                    PARTITION BY assignment_number,
                        hierarchy_sig
                    ORDER BY dt_valid_from,
                        dt_valid_to
                ) IS NULL
                OR dt_valid_from > DATE_ADD(
                    LAG(dt_valid_to) OVER (
                        PARTITION BY assignment_number,
                            hierarchy_sig
                        ORDER BY dt_valid_from,
                            dt_valid_to
                    ),
                    1
                )
                THEN 1
                ELSE 0
            END
        ) OVER (
            PARTITION BY assignment_number,
                hierarchy_sig
            ORDER BY dt_valid_from,
                dt_valid_to
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS island_id
    FROM
        hierarchy_with_sig
),
hierarchy_consolidated AS (
    SELECT
        assignment_number,
        MIN_BY(manager_struct_path, dt_valid_from) AS manager_struct_path,
        MIN(dt_valid_from) AS dt_valid_from,
        MAX(dt_valid_to) AS dt_valid_to,
        CASE
            WHEN CURRENT_DATE BETWEEN MIN(dt_valid_from) AND MAX(dt_valid_to)
            THEN TRUE
            ELSE FALSE
        END AS is_current
    FROM
        hierarchy_with_island
    GROUP BY
        assignment_number,
        hierarchy_sig,
        island_id
),
hierarchy_versioned AS (
    SELECT
        *,
        DENSE_RANK() OVER (
            PARTITION BY assignment_number
            ORDER BY dt_valid_from NULLS LAST,
                dt_valid_to NULLS LAST
        ) AS hierarchy_version_seq,
        MD5(
            CONCAT_WS(
                '|',
                assignment_number,
                DATE_FORMAT(dt_valid_from, 'yyyy-MM-dd'),
                COALESCE(DATE_FORMAT(dt_valid_to, 'yyyy-MM-dd'), '9999-12-31')
            )
        ) AS sk_hierarchy_version
    FROM
        hierarchy_consolidated
),
assignment_lookup AS (
    SELECT
        assignment_number,
        person_number,
        COALESCE(display_name, full_name) AS name,
        work_email AS email
    FROM
        datalake_people.identifier_mapping
    WHERE
        NOT is_user_test
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY assignment_number ORDER BY assignment_number) = 1
)
SELECT
    hv.sk_hierarchy_version,
    COALESCE(CAST(hv.assignment_number AS STRING), '') AS assignment_number,
    COALESCE(im_self.person_number, '') AS person_number,
    COALESCE(CAST(hv.manager_struct_path[0].assignment_number AS STRING), '') AS assignment_number_l0,
    COALESCE(im_l0.person_number, '') AS person_number_l0,
    COALESCE(im_l0.name, '') AS name_l0,
    COALESCE(im_l0.email, '') AS email_l0,
    COALESCE(CAST(hv.manager_struct_path[1].assignment_number AS STRING), '') AS assignment_number_l1,
    COALESCE(im_l1.person_number, '') AS person_number_l1,
    COALESCE(im_l1.name, '') AS name_l1,
    COALESCE(im_l1.email, '') AS email_l1,
    COALESCE(CAST(hv.manager_struct_path[2].assignment_number AS STRING), '') AS assignment_number_l2,
    COALESCE(im_l2.person_number, '') AS person_number_l2,
    COALESCE(im_l2.name, '') AS name_l2,
    COALESCE(im_l2.email, '') AS email_l2,
    COALESCE(CAST(hv.manager_struct_path[3].assignment_number AS STRING), '') AS assignment_number_l3,
    COALESCE(im_l3.person_number, '') AS person_number_l3,
    COALESCE(im_l3.name, '') AS name_l3,
    COALESCE(im_l3.email, '') AS email_l3,
    COALESCE(CAST(hv.manager_struct_path[4].assignment_number AS STRING), '') AS assignment_number_l4,
    COALESCE(im_l4.person_number, '') AS person_number_l4,
    COALESCE(im_l4.name, '') AS name_l4,
    COALESCE(im_l4.email, '') AS email_l4,
    COALESCE(CAST(hv.manager_struct_path[5].assignment_number AS STRING), '') AS assignment_number_l5,
    COALESCE(im_l5.person_number, '') AS person_number_l5,
    COALESCE(im_l5.name, '') AS name_l5,
    COALESCE(im_l5.email, '') AS email_l5,
    COALESCE(CAST(hv.manager_struct_path[6].assignment_number AS STRING), '') AS assignment_number_l6,
    COALESCE(im_l6.person_number, '') AS person_number_l6,
    COALESCE(im_l6.name, '') AS name_l6,
    COALESCE(im_l6.email, '') AS email_l6,
    COALESCE(CAST(hv.manager_struct_path[7].assignment_number AS STRING), '') AS assignment_number_l7,
    COALESCE(im_l7.person_number, '') AS person_number_l7,
    COALESCE(im_l7.name, '') AS name_l7,
    COALESCE(im_l7.email, '') AS email_l7,
    COALESCE(CAST(hv.manager_struct_path[8].assignment_number AS STRING), '') AS assignment_number_l8,
    COALESCE(im_l8.person_number, '') AS person_number_l8,
    COALESCE(im_l8.name, '') AS name_l8,
    COALESCE(im_l8.email, '') AS email_l8,
    COALESCE(CAST(hv.manager_struct_path[9].assignment_number AS STRING), '') AS assignment_number_l9,
    COALESCE(im_l9.person_number, '') AS person_number_l9,
    COALESCE(im_l9.name, '') AS name_l9,
    COALESCE(im_l9.email, '') AS email_l9,
    hv.hierarchy_version_seq AS version,
    hv.is_current,
    hv.dt_valid_from,
    hv.dt_valid_to,
    CURRENT_TIMESTAMP() AS ts_load
FROM
    hierarchy_versioned AS hv
LEFT JOIN
    assignment_lookup AS im_self
    ON im_self.assignment_number = hv.assignment_number
LEFT JOIN
    assignment_lookup AS im_l0
    ON im_l0.assignment_number = hv.manager_struct_path[0].assignment_number
LEFT JOIN
    assignment_lookup AS im_l1
    ON im_l1.assignment_number = hv.manager_struct_path[1].assignment_number
LEFT JOIN
    assignment_lookup AS im_l2
    ON im_l2.assignment_number = hv.manager_struct_path[2].assignment_number
LEFT JOIN
    assignment_lookup AS im_l3
    ON im_l3.assignment_number = hv.manager_struct_path[3].assignment_number
LEFT JOIN
    assignment_lookup AS im_l4
    ON im_l4.assignment_number = hv.manager_struct_path[4].assignment_number
LEFT JOIN
    assignment_lookup AS im_l5
    ON im_l5.assignment_number = hv.manager_struct_path[5].assignment_number
LEFT JOIN
    assignment_lookup AS im_l6
    ON im_l6.assignment_number = hv.manager_struct_path[6].assignment_number
LEFT JOIN
    assignment_lookup AS im_l7
    ON im_l7.assignment_number = hv.manager_struct_path[7].assignment_number
LEFT JOIN
    assignment_lookup AS im_l8
    ON im_l8.assignment_number = hv.manager_struct_path[8].assignment_number
LEFT JOIN
    assignment_lookup AS im_l9
    ON im_l9.assignment_number = hv.manager_struct_path[9].assignment_number
