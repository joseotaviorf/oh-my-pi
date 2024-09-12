WITH
ranked_managers AS (
    SELECT
        mh.id_period_of_service,
        ei.id_period_of_service AS id_period_of_service_manager,
        ROW_NUMBER() OVER (
            PARTITION BY
                mh.id_assignment
            ORDER BY
                mh.separation_degree DESC
        ) AS rn
    FROM
        datalake_hr_system.management_hierarchy AS mh
    INNER JOIN
        datalake_hr_system.employee_ids AS ei
            ON ei.id_assignment = mh.id_manager_assignment
),
managers_long AS (
    SELECT
        id_period_of_service,
        MAX(
            CASE
                WHEN rn = 1 THEN id_period_of_service_manager
            END
        ) AS sk_assignment_leadership_order_0,
        MAX(
            CASE
                WHEN rn = 2 THEN id_period_of_service_manager
            END
        ) AS sk_assignment_leadership_order_1,
        MAX(
            CASE
                WHEN rn = 3 THEN id_period_of_service_manager
            END
        ) AS sk_assignment_leadership_order_2,
        MAX(
            CASE
                WHEN rn = 4 THEN id_period_of_service_manager
            END
        ) AS sk_assignment_leadership_order_3,
        MAX(
            CASE
                WHEN rn = 5 THEN id_period_of_service_manager
            END
        ) AS sk_assignment_leadership_order_4,
        MAX(
            CASE
                WHEN rn = 6 THEN id_period_of_service_manager
            END
        ) AS sk_assignment_leadership_order_5,
        MAX(
            CASE
                WHEN rn = 7 THEN id_period_of_service_manager
            END
        ) AS sk_assignment_leadership_order_6,
        MAX(
            CASE
                WHEN rn = 8 THEN id_period_of_service_manager
            END
        ) AS sk_assignment_leadership_order_7,
        MAX(
            CASE
                WHEN rn = 9 THEN id_period_of_service_manager
            END
        ) AS sk_assignment_leadership_order_8,
        MAX(
            CASE
                WHEN rn = 10 THEN id_period_of_service_manager
            END
        ) AS sk_assignment_leadership_order_9
    FROM
        ranked_managers
    GROUP BY
        id_period_of_service
)

SELECT
    id_period_of_service AS sk_assignment,
    MD5(
        CONCAT(
        COALESCE(sk_assignment_leadership_order_0, -1),
        COALESCE(sk_assignment_leadership_order_1, -1),
        COALESCE(sk_assignment_leadership_order_2, -1),
        COALESCE(sk_assignment_leadership_order_3, -1),
        COALESCE(sk_assignment_leadership_order_4, -1),
        COALESCE(sk_assignment_leadership_order_5, -1),
        COALESCE(sk_assignment_leadership_order_6, -1),
        COALESCE(sk_assignment_leadership_order_7, -1),
        COALESCE(sk_assignment_leadership_order_8, -1),
        COALESCE(sk_assignment_leadership_order_9, -1)
        )
    ) AS sk_hierarchy,
    sk_assignment_leadership_order_0,
    sk_assignment_leadership_order_1,
    sk_assignment_leadership_order_2,
    sk_assignment_leadership_order_3,
    sk_assignment_leadership_order_4,
    sk_assignment_leadership_order_5,
    sk_assignment_leadership_order_6,
    sk_assignment_leadership_order_7,
    sk_assignment_leadership_order_8,
    sk_assignment_leadership_order_9
FROM managers_long
