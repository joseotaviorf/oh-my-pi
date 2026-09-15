-- Product & Tech team-formation attributes (wide), mirroring the roster sheet.
-- Grain: one row per active employee currently listed in the team-formation sheet.
-- Teams stay wide (team_1 … team_10) like the source workbook — not long/unpivoted.
-- Join sheet assignment_number to identifier_mapping.
-- Active-only: matches dw_people.dim_employee / fact_employees (assignment_snapshots is_current_for_employee + is_active).
WITH team_formation_ranked AS (
    SELECT
        team_formation.assignment_number,
        team_formation.line,
        team_formation.chapter,
        team_formation.team_1,
        team_formation.team_2,
        team_formation.team_3,
        team_formation.team_4,
        team_formation.team_5,
        team_formation.team_6,
        team_formation.team_7,
        team_formation.team_8,
        team_formation.team_9,
        team_formation.team_10,
        team_formation.line_leader,
        team_formation.team_leader,
        team_formation.is_line_leader,
        team_formation.is_team_leader,
        team_formation.ts_load,
        ROW_NUMBER() OVER (
            PARTITION BY
                UPPER(TRIM(team_formation.assignment_number))
            ORDER BY
                team_formation.ts_load DESC NULLS LAST
        ) AS rn
    FROM
        datalake_gsheets_people_clean.team_formation_product_tech AS team_formation
    WHERE
        team_formation.assignment_number IS NOT NULL
        AND TRIM(team_formation.assignment_number) <> ''
),
employees_ranked AS (
    SELECT
        identifier_mapping.id_person,
        identifier_mapping.person_number,
        identifier_mapping.assignment_number,
        ROW_NUMBER() OVER (
            PARTITION BY
                UPPER(TRIM(identifier_mapping.assignment_number))
            ORDER BY
                identifier_mapping.ts_load DESC NULLS LAST
        ) AS rn
    FROM
        datalake_people.identifier_mapping AS identifier_mapping
    WHERE
        NOT identifier_mapping.is_user_test
        AND identifier_mapping.is_person_latest_assignment
        AND identifier_mapping.is_active
        AND identifier_mapping.assignment_number IS NOT NULL
),
joined AS (
    SELECT
        employees.id_person AS sk_employee,
        employees.person_number,
        employees.assignment_number,
        team_formation.line,
        team_formation.chapter,
        team_formation.line_leader,
        team_formation.team_leader,
        team_formation.team_1,
        team_formation.team_2,
        team_formation.team_3,
        team_formation.team_4,
        team_formation.team_5,
        team_formation.team_6,
        team_formation.team_7,
        team_formation.team_8,
        team_formation.team_9,
        team_formation.team_10,
        team_formation.is_line_leader,
        team_formation.is_team_leader,
        ROW_NUMBER() OVER (
            PARTITION BY
                employees.id_person
            ORDER BY
                team_formation.ts_load DESC NULLS LAST,
                employees.assignment_number
        ) AS rn_person
    FROM
        team_formation_ranked AS team_formation
    INNER JOIN
        employees_ranked AS employees
            ON UPPER(TRIM(team_formation.assignment_number))
                = UPPER(TRIM(employees.assignment_number))
            AND employees.rn = 1
    WHERE
        team_formation.rn = 1
)
SELECT
    joined.sk_employee,
    joined.person_number,
    joined.assignment_number,
    joined.line,
    joined.chapter,
    joined.line_leader,
    joined.team_leader,
    joined.team_1,
    joined.team_2,
    joined.team_3,
    joined.team_4,
    joined.team_5,
    joined.team_6,
    joined.team_7,
    joined.team_8,
    joined.team_9,
    joined.team_10,
    joined.is_line_leader,
    joined.is_team_leader,
    CURRENT_TIMESTAMP() AS ts_load
FROM
    joined
WHERE
    joined.rn_person = 1
