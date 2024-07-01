WITH
    ranked_managers AS (
        SELECT
            id_assignment,
            id_manager_assignment,
            separation_degree,
            ROW_NUMBER() OVER (
                PARTITION BY
                    id_assignment
                ORDER BY
                    separation_degree DESC
            ) as rn
        FROM
            datalake_hr_system.management_hierarchy
    )
SELECT
    id_assignment,
    MAX(
        CASE
            WHEN rn = 1 THEN id_manager_assignment
        END
    ) AS id_assignment_leadership_order_0,
    MAX(
        CASE
            WHEN rn = 2 THEN id_manager_assignment
        END
    ) AS id_assignment_leadership_order_1,
    MAX(
        CASE
            WHEN rn = 3 THEN id_manager_assignment
        END
    ) AS id_assignment_leadership_order_2,
    MAX(
        CASE
            WHEN rn = 4 THEN id_manager_assignment
        END
    ) AS id_assignment_leadership_order_3,
    MAX(
        CASE
            WHEN rn = 5 THEN id_manager_assignment
        END
    ) AS id_assignment_leadership_order_4,
    MAX(
        CASE
            WHEN rn = 6 THEN id_manager_assignment
        END
    ) AS id_assignment_leadership_order_5,
    MAX(
        CASE
            WHEN rn = 7 THEN id_manager_assignment
        END
    ) AS id_assignment_leadership_order_6,
    MAX(
        CASE
            WHEN rn = 8 THEN id_manager_assignment
        END
    ) AS id_assignment_leadership_order_7,
    MAX(
        CASE
            WHEN rn = 9 THEN id_manager_assignment
        END
    ) AS id_assignment_leadership_order_8,
    MAX(
        CASE
            WHEN rn = 10 THEN id_manager_assignment
        END
    ) AS id_assignment_leadership_order_9
FROM
    ranked_managers
GROUP BY
    id_assignment
