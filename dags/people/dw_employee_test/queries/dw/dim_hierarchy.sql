WITH filtered_managers_history /* Bring supervisor relationships and enrich them with manager identifiers */ /* Filters for active supervisor links and enriched with identifier data */ AS (
  SELECT DISTINCT
    im.assignment_number,
    eim.assignment_number AS manager_assignment_number,
    COALESCE(eim.full_name, pnm.display_name) AS manager_full_name,
    eim.work_email AS manager_work_email,
    s.dt_effective_started,
    s.dt_effective_ended,
    s.id_manager_assignment
  FROM datalake_employee_registration.identifier_mapping AS im
  INNER JOIN datalake_pin_core_clean.assignment_supervisor AS s
    ON im.id_assignment = s.id_assignment
  LEFT JOIN datalake_employee_registration.identifier_mapping AS eim
    ON eim.id_assignment = s.id_manager_assignment
  LEFT JOIN datalake_pin_core_clean.person_name AS pnm
    ON pnm.id_person = s.id_manager
    AND pnm.name_type = 'GLOBAL'
    AND pnm.dt_effective_ended = '4712-12-31' /* PIN's infinity date */
  WHERE
    s.is_primary
    AND s.manager_type = 'LINE_MANAGER'
    AND s.dt_effective_started <= DATE('{load_start_date}')
    AND NOT s.id_manager_assignment IS NULL
    AND NOT im.is_user_test
    AND NOT eim.is_user_test
), level_1 /* Anchor level: employee direct manager */ AS (
  SELECT
    assignment_number,
    manager_assignment_number AS manager_assignment_number_1,
    manager_full_name AS manager_name_1,
    manager_work_email AS manager_email_1,
    dt_effective_started AS dt_valid_from,
    dt_effective_ended AS dt_valid_to
  FROM filtered_managers_history
), level_2 /* Level 2..10: progressively walk up the hierarchy ensuring date overlaps */ /* GREATEST/LEAST keeps only the intersecting validity window between the manager and the employee */ AS (
  SELECT DISTINCT
    l1.assignment_number,
    l1.manager_assignment_number_1,
    l1.manager_name_1,
    l1.manager_email_1,
    mh.manager_assignment_number AS manager_assignment_number_2,
    mh.manager_full_name AS manager_name_2,
    mh.manager_work_email AS manager_email_2,
    GREATEST(l1.dt_valid_from, mh.dt_effective_started) AS dt_valid_from,
    LEAST(l1.dt_valid_to, mh.dt_effective_ended) AS dt_valid_to
  FROM level_1 AS l1
  INNER JOIN filtered_managers_history AS mh
    ON l1.manager_assignment_number_1 = mh.assignment_number
  WHERE
    l1.dt_valid_to >= mh.dt_effective_started
    AND mh.dt_effective_ended >= l1.dt_valid_from
), level_3 AS (
  SELECT DISTINCT
    l2.assignment_number,
    l2.manager_assignment_number_1,
    l2.manager_name_1,
    l2.manager_email_1,
    l2.manager_assignment_number_2,
    l2.manager_name_2,
    l2.manager_email_2,
    mh.manager_assignment_number AS manager_assignment_number_3,
    mh.manager_full_name AS manager_name_3,
    mh.manager_work_email AS manager_email_3,
    GREATEST(l2.dt_valid_from, mh.dt_effective_started) AS dt_valid_from,
    LEAST(l2.dt_valid_to, mh.dt_effective_ended) AS dt_valid_to
  FROM level_2 AS l2
  INNER JOIN filtered_managers_history AS mh
    ON l2.manager_assignment_number_2 = mh.assignment_number
  WHERE
    l2.dt_valid_to >= mh.dt_effective_started
    AND mh.dt_effective_ended >= l2.dt_valid_from
), level_4 AS (
  SELECT DISTINCT
    l3.assignment_number,
    l3.manager_assignment_number_1,
    l3.manager_name_1,
    l3.manager_email_1,
    l3.manager_assignment_number_2,
    l3.manager_name_2,
    l3.manager_email_2,
    l3.manager_assignment_number_3,
    l3.manager_name_3,
    l3.manager_email_3,
    mh.manager_assignment_number AS manager_assignment_number_4,
    mh.manager_full_name AS manager_name_4,
    mh.manager_work_email AS manager_email_4,
    GREATEST(l3.dt_valid_from, mh.dt_effective_started) AS dt_valid_from,
    LEAST(l3.dt_valid_to, mh.dt_effective_ended) AS dt_valid_to
  FROM level_3 AS l3
  INNER JOIN filtered_managers_history AS mh
    ON l3.manager_assignment_number_3 = mh.assignment_number
  WHERE
    l3.dt_valid_to >= mh.dt_effective_started
    AND mh.dt_effective_ended >= l3.dt_valid_from
), level_5 AS (
  SELECT DISTINCT
    l4.assignment_number,
    l4.manager_assignment_number_1,
    l4.manager_name_1,
    l4.manager_email_1,
    l4.manager_assignment_number_2,
    l4.manager_name_2,
    l4.manager_email_2,
    l4.manager_assignment_number_3,
    l4.manager_name_3,
    l4.manager_email_3,
    l4.manager_assignment_number_4,
    l4.manager_name_4,
    l4.manager_email_4,
    mh.manager_assignment_number AS manager_assignment_number_5,
    mh.manager_full_name AS manager_name_5,
    mh.manager_work_email AS manager_email_5,
    GREATEST(l4.dt_valid_from, mh.dt_effective_started) AS dt_valid_from,
    LEAST(l4.dt_valid_to, mh.dt_effective_ended) AS dt_valid_to
  FROM level_4 AS l4
  INNER JOIN filtered_managers_history AS mh
    ON l4.manager_assignment_number_4 = mh.assignment_number
  WHERE
    l4.dt_valid_to >= mh.dt_effective_started
    AND mh.dt_effective_ended >= l4.dt_valid_from
), level_6 AS (
  SELECT DISTINCT
    l5.assignment_number,
    l5.manager_assignment_number_1,
    l5.manager_name_1,
    l5.manager_email_1,
    l5.manager_assignment_number_2,
    l5.manager_name_2,
    l5.manager_email_2,
    l5.manager_assignment_number_3,
    l5.manager_name_3,
    l5.manager_email_3,
    l5.manager_assignment_number_4,
    l5.manager_name_4,
    l5.manager_email_4,
    l5.manager_assignment_number_5,
    l5.manager_name_5,
    l5.manager_email_5,
    mh.manager_assignment_number AS manager_assignment_number_6,
    mh.manager_full_name AS manager_name_6,
    mh.manager_work_email AS manager_email_6,
    GREATEST(l5.dt_valid_from, mh.dt_effective_started) AS dt_valid_from,
    LEAST(l5.dt_valid_to, mh.dt_effective_ended) AS dt_valid_to
  FROM level_5 AS l5
  INNER JOIN filtered_managers_history AS mh
    ON l5.manager_assignment_number_5 = mh.assignment_number
  WHERE
    l5.dt_valid_to >= mh.dt_effective_started
    AND mh.dt_effective_ended >= l5.dt_valid_from
), level_7 AS (
  SELECT DISTINCT
    l6.assignment_number,
    l6.manager_assignment_number_1,
    l6.manager_name_1,
    l6.manager_email_1,
    l6.manager_assignment_number_2,
    l6.manager_name_2,
    l6.manager_email_2,
    l6.manager_assignment_number_3,
    l6.manager_name_3,
    l6.manager_email_3,
    l6.manager_assignment_number_4,
    l6.manager_name_4,
    l6.manager_email_4,
    l6.manager_assignment_number_5,
    l6.manager_name_5,
    l6.manager_email_5,
    l6.manager_assignment_number_6,
    l6.manager_name_6,
    l6.manager_email_6,
    mh.manager_assignment_number AS manager_assignment_number_7,
    mh.manager_full_name AS manager_name_7,
    mh.manager_work_email AS manager_email_7,
    GREATEST(l6.dt_valid_from, mh.dt_effective_started) AS dt_valid_from,
    LEAST(l6.dt_valid_to, mh.dt_effective_ended) AS dt_valid_to
  FROM level_6 AS l6
  INNER JOIN filtered_managers_history AS mh
    ON l6.manager_assignment_number_6 = mh.assignment_number
  WHERE
    l6.dt_valid_to >= mh.dt_effective_started
    AND mh.dt_effective_ended >= l6.dt_valid_from
), level_8 AS (
  SELECT DISTINCT
    l7.assignment_number,
    l7.manager_assignment_number_1,
    l7.manager_name_1,
    l7.manager_email_1,
    l7.manager_assignment_number_2,
    l7.manager_name_2,
    l7.manager_email_2,
    l7.manager_assignment_number_3,
    l7.manager_name_3,
    l7.manager_email_3,
    l7.manager_assignment_number_4,
    l7.manager_name_4,
    l7.manager_email_4,
    l7.manager_assignment_number_5,
    l7.manager_name_5,
    l7.manager_email_5,
    l7.manager_assignment_number_6,
    l7.manager_name_6,
    l7.manager_email_6,
    l7.manager_assignment_number_7,
    l7.manager_name_7,
    l7.manager_email_7,
    mh.manager_assignment_number AS manager_assignment_number_8,
    mh.manager_full_name AS manager_name_8,
    mh.manager_work_email AS manager_email_8,
    GREATEST(l7.dt_valid_from, mh.dt_effective_started) AS dt_valid_from,
    LEAST(l7.dt_valid_to, mh.dt_effective_ended) AS dt_valid_to
  FROM level_7 AS l7
  INNER JOIN filtered_managers_history AS mh
    ON l7.manager_assignment_number_7 = mh.assignment_number
  WHERE
    l7.dt_valid_to >= mh.dt_effective_started
    AND mh.dt_effective_ended >= l7.dt_valid_from
), level_9 AS (
  SELECT DISTINCT
    l8.assignment_number,
    l8.manager_assignment_number_1,
    l8.manager_name_1,
    l8.manager_email_1,
    l8.manager_assignment_number_2,
    l8.manager_name_2,
    l8.manager_email_2,
    l8.manager_assignment_number_3,
    l8.manager_name_3,
    l8.manager_email_3,
    l8.manager_assignment_number_4,
    l8.manager_name_4,
    l8.manager_email_4,
    l8.manager_assignment_number_5,
    l8.manager_name_5,
    l8.manager_email_5,
    l8.manager_assignment_number_6,
    l8.manager_name_6,
    l8.manager_email_6,
    l8.manager_assignment_number_7,
    l8.manager_name_7,
    l8.manager_email_7,
    l8.manager_assignment_number_8,
    l8.manager_name_8,
    l8.manager_email_8,
    mh.manager_assignment_number AS manager_assignment_number_9,
    mh.manager_full_name AS manager_name_9,
    mh.manager_work_email AS manager_email_9,
    GREATEST(l8.dt_valid_from, mh.dt_effective_started) AS dt_valid_from,
    LEAST(l8.dt_valid_to, mh.dt_effective_ended) AS dt_valid_to
  FROM level_8 AS l8
  INNER JOIN filtered_managers_history AS mh
    ON l8.manager_assignment_number_8 = mh.assignment_number
  WHERE
    l8.dt_valid_to >= mh.dt_effective_started
    AND mh.dt_effective_ended >= l8.dt_valid_from
), level_10 AS (
  SELECT DISTINCT
    l9.assignment_number,
    l9.manager_assignment_number_1,
    l9.manager_name_1,
    l9.manager_email_1,
    l9.manager_assignment_number_2,
    l9.manager_name_2,
    l9.manager_email_2,
    l9.manager_assignment_number_3,
    l9.manager_name_3,
    l9.manager_email_3,
    l9.manager_assignment_number_4,
    l9.manager_name_4,
    l9.manager_email_4,
    l9.manager_assignment_number_5,
    l9.manager_name_5,
    l9.manager_email_5,
    l9.manager_assignment_number_6,
    l9.manager_name_6,
    l9.manager_email_6,
    l9.manager_assignment_number_7,
    l9.manager_name_7,
    l9.manager_email_7,
    l9.manager_assignment_number_8,
    l9.manager_name_8,
    l9.manager_email_8,
    l9.manager_assignment_number_9,
    l9.manager_name_9,
    l9.manager_email_9,
    mh.manager_assignment_number AS manager_assignment_number_10,
    mh.manager_full_name AS manager_name_10,
    mh.manager_work_email AS manager_email_10,
    GREATEST(l9.dt_valid_from, mh.dt_effective_started) AS dt_valid_from,
    LEAST(l9.dt_valid_to, mh.dt_effective_ended) AS dt_valid_to
  FROM level_9 AS l9
  INNER JOIN filtered_managers_history AS mh
    ON l9.manager_assignment_number_9 = mh.assignment_number
  WHERE
    l9.dt_valid_to >= mh.dt_effective_started
    AND mh.dt_effective_ended >= l9.dt_valid_from
), hierarchy_union /* Collapse all level-specific CTEs into a single flattened relation while keeping column positions aligned */ AS (
  SELECT
    assignment_number,
    manager_assignment_number_1,
    manager_name_1,
    manager_email_1,
    NULL AS manager_assignment_number_2,
    NULL AS manager_name_2,
    NULL AS manager_email_2,
    NULL AS manager_assignment_number_3,
    NULL AS manager_name_3,
    NULL AS manager_email_3,
    NULL AS manager_assignment_number_4,
    NULL AS manager_name_4,
    NULL AS manager_email_4,
    NULL AS manager_assignment_number_5,
    NULL AS manager_name_5,
    NULL AS manager_email_5,
    NULL AS manager_assignment_number_6,
    NULL AS manager_name_6,
    NULL AS manager_email_6,
    NULL AS manager_assignment_number_7,
    NULL AS manager_name_7,
    NULL AS manager_email_7,
    NULL AS manager_assignment_number_8,
    NULL AS manager_name_8,
    NULL AS manager_email_8,
    NULL AS manager_assignment_number_9,
    NULL AS manager_name_9,
    NULL AS manager_email_9,
    NULL AS manager_assignment_number_10,
    NULL AS manager_name_10,
    NULL AS manager_email_10,
    dt_valid_from,
    dt_valid_to
  FROM level_1
  UNION ALL
  SELECT
    assignment_number,
    manager_assignment_number_1,
    manager_name_1,
    manager_email_1,
    manager_assignment_number_2,
    manager_name_2,
    manager_email_2,
    NULL AS manager_assignment_number_3,
    NULL AS manager_name_3,
    NULL AS manager_email_3,
    NULL AS manager_assignment_number_4,
    NULL AS manager_name_4,
    NULL AS manager_email_4,
    NULL AS manager_assignment_number_5,
    NULL AS manager_name_5,
    NULL AS manager_email_5,
    NULL AS manager_assignment_number_6,
    NULL AS manager_name_6,
    NULL AS manager_email_6,
    NULL AS manager_assignment_number_7,
    NULL AS manager_name_7,
    NULL AS manager_email_7,
    NULL AS manager_assignment_number_8,
    NULL AS manager_name_8,
    NULL AS manager_email_8,
    NULL AS manager_assignment_number_9,
    NULL AS manager_name_9,
    NULL AS manager_email_9,
    NULL AS manager_assignment_number_10,
    NULL AS manager_name_10,
    NULL AS manager_email_10,
    dt_valid_from,
    dt_valid_to
  FROM level_2
  UNION ALL
  SELECT
    assignment_number,
    manager_assignment_number_1,
    manager_name_1,
    manager_email_1,
    manager_assignment_number_2,
    manager_name_2,
    manager_email_2,
    manager_assignment_number_3,
    manager_name_3,
    manager_email_3,
    NULL AS manager_assignment_number_4,
    NULL AS manager_name_4,
    NULL AS manager_email_4,
    NULL AS manager_assignment_number_5,
    NULL AS manager_name_5,
    NULL AS manager_email_5,
    NULL AS manager_assignment_number_6,
    NULL AS manager_name_6,
    NULL AS manager_email_6,
    NULL AS manager_assignment_number_7,
    NULL AS manager_name_7,
    NULL AS manager_email_7,
    NULL AS manager_assignment_number_8,
    NULL AS manager_name_8,
    NULL AS manager_email_8,
    NULL AS manager_assignment_number_9,
    NULL AS manager_name_9,
    NULL AS manager_email_9,
    NULL AS manager_assignment_number_10,
    NULL AS manager_name_10,
    NULL AS manager_email_10,
    dt_valid_from,
    dt_valid_to
  FROM level_3
  UNION ALL
  SELECT
    assignment_number,
    manager_assignment_number_1,
    manager_name_1,
    manager_email_1,
    manager_assignment_number_2,
    manager_name_2,
    manager_email_2,
    manager_assignment_number_3,
    manager_name_3,
    manager_email_3,
    manager_assignment_number_4,
    manager_name_4,
    manager_email_4,
    NULL AS manager_assignment_number_5,
    NULL AS manager_name_5,
    NULL AS manager_email_5,
    NULL AS manager_assignment_number_6,
    NULL AS manager_name_6,
    NULL AS manager_email_6,
    NULL AS manager_assignment_number_7,
    NULL AS manager_name_7,
    NULL AS manager_email_7,
    NULL AS manager_assignment_number_8,
    NULL AS manager_name_8,
    NULL AS manager_email_8,
    NULL AS manager_assignment_number_9,
    NULL AS manager_name_9,
    NULL AS manager_email_9,
    NULL AS manager_assignment_number_10,
    NULL AS manager_name_10,
    NULL AS manager_email_10,
    dt_valid_from,
    dt_valid_to
  FROM level_4
  UNION ALL
  SELECT
    assignment_number,
    manager_assignment_number_1,
    manager_name_1,
    manager_email_1,
    manager_assignment_number_2,
    manager_name_2,
    manager_email_2,
    manager_assignment_number_3,
    manager_name_3,
    manager_email_3,
    manager_assignment_number_4,
    manager_name_4,
    manager_email_4,
    manager_assignment_number_5,
    manager_name_5,
    manager_email_5,
    NULL AS manager_assignment_number_6,
    NULL AS manager_name_6,
    NULL AS manager_email_6,
    NULL AS manager_assignment_number_7,
    NULL AS manager_name_7,
    NULL AS manager_email_7,
    NULL AS manager_assignment_number_8,
    NULL AS manager_name_8,
    NULL AS manager_email_8,
    NULL AS manager_assignment_number_9,
    NULL AS manager_name_9,
    NULL AS manager_email_9,
    NULL AS manager_assignment_number_10,
    NULL AS manager_name_10,
    NULL AS manager_email_10,
    dt_valid_from,
    dt_valid_to
  FROM level_5
  UNION ALL
  SELECT
    assignment_number,
    manager_assignment_number_1,
    manager_name_1,
    manager_email_1,
    manager_assignment_number_2,
    manager_name_2,
    manager_email_2,
    manager_assignment_number_3,
    manager_name_3,
    manager_email_3,
    manager_assignment_number_4,
    manager_name_4,
    manager_email_4,
    manager_assignment_number_5,
    manager_name_5,
    manager_email_5,
    manager_assignment_number_6,
    manager_name_6,
    manager_email_6,
    NULL AS manager_assignment_number_7,
    NULL AS manager_name_7,
    NULL AS manager_email_7,
    NULL AS manager_assignment_number_8,
    NULL AS manager_name_8,
    NULL AS manager_email_8,
    NULL AS manager_assignment_number_9,
    NULL AS manager_name_9,
    NULL AS manager_email_9,
    NULL AS manager_assignment_number_10,
    NULL AS manager_name_10,
    NULL AS manager_email_10,
    dt_valid_from,
    dt_valid_to
  FROM level_6
  UNION ALL
  SELECT
    assignment_number,
    manager_assignment_number_1,
    manager_name_1,
    manager_email_1,
    manager_assignment_number_2,
    manager_name_2,
    manager_email_2,
    manager_assignment_number_3,
    manager_name_3,
    manager_email_3,
    manager_assignment_number_4,
    manager_name_4,
    manager_email_4,
    manager_assignment_number_5,
    manager_name_5,
    manager_email_5,
    manager_assignment_number_6,
    manager_name_6,
    manager_email_6,
    manager_assignment_number_7,
    manager_name_7,
    manager_email_7,
    NULL AS manager_assignment_number_8,
    NULL AS manager_name_8,
    NULL AS manager_email_8,
    NULL AS manager_assignment_number_9,
    NULL AS manager_name_9,
    NULL AS manager_email_9,
    NULL AS manager_assignment_number_10,
    NULL AS manager_name_10,
    NULL AS manager_email_10,
    dt_valid_from,
    dt_valid_to
  FROM level_7
  UNION ALL
  SELECT
    assignment_number,
    manager_assignment_number_1,
    manager_name_1,
    manager_email_1,
    manager_assignment_number_2,
    manager_name_2,
    manager_email_2,
    manager_assignment_number_3,
    manager_name_3,
    manager_email_3,
    manager_assignment_number_4,
    manager_name_4,
    manager_email_4,
    manager_assignment_number_5,
    manager_name_5,
    manager_email_5,
    manager_assignment_number_6,
    manager_name_6,
    manager_email_6,
    manager_assignment_number_7,
    manager_name_7,
    manager_email_7,
    manager_assignment_number_8,
    manager_name_8,
    manager_email_8,
    NULL AS manager_assignment_number_9,
    NULL AS manager_name_9,
    NULL AS manager_email_9,
    NULL AS manager_assignment_number_10,
    NULL AS manager_name_10,
    NULL AS manager_email_10,
    dt_valid_from,
    dt_valid_to
  FROM level_8
  UNION ALL
  SELECT
    assignment_number,
    manager_assignment_number_1,
    manager_name_1,
    manager_email_1,
    manager_assignment_number_2,
    manager_name_2,
    manager_email_2,
    manager_assignment_number_3,
    manager_name_3,
    manager_email_3,
    manager_assignment_number_4,
    manager_name_4,
    manager_email_4,
    manager_assignment_number_5,
    manager_name_5,
    manager_email_5,
    manager_assignment_number_6,
    manager_name_6,
    manager_email_6,
    manager_assignment_number_7,
    manager_name_7,
    manager_email_7,
    manager_assignment_number_8,
    manager_name_8,
    manager_email_8,
    manager_assignment_number_9,
    manager_name_9,
    manager_email_9,
    NULL AS manager_assignment_number_10,
    NULL AS manager_name_10,
    NULL AS manager_email_10,
    dt_valid_from,
    dt_valid_to
  FROM level_9
  UNION ALL
  SELECT
    assignment_number,
    manager_assignment_number_1,
    manager_name_1,
    manager_email_1,
    manager_assignment_number_2,
    manager_name_2,
    manager_email_2,
    manager_assignment_number_3,
    manager_name_3,
    manager_email_3,
    manager_assignment_number_4,
    manager_name_4,
    manager_email_4,
    manager_assignment_number_5,
    manager_name_5,
    manager_email_5,
    manager_assignment_number_6,
    manager_name_6,
    manager_email_6,
    manager_assignment_number_7,
    manager_name_7,
    manager_email_7,
    manager_assignment_number_8,
    manager_name_8,
    manager_email_8,
    manager_assignment_number_9,
    manager_name_9,
    manager_email_9,
    manager_assignment_number_10,
    manager_name_10,
    manager_email_10,
    dt_valid_from,
    dt_valid_to
  FROM level_10
), hierarchy_reordered /* Rebuild the manager path as an ordered array of structs (bottom manager to top) */ /* Filters empty hierarchy levels and reverses the order so it matches the manager_l0..manager_l9 aliases */ AS (
  SELECT
    assignment_number,
    dt_valid_from,
    dt_valid_to,
    REVERSE(
      FILTER(
        ARRAY(
          NAMED_STRUCT(
            'assignment_number',
            manager_assignment_number_1,
            'name',
            manager_name_1,
            'email',
            manager_email_1
          ),
          NAMED_STRUCT(
            'assignment_number',
            manager_assignment_number_2,
            'name',
            manager_name_2,
            'email',
            manager_email_2
          ),
          NAMED_STRUCT(
            'assignment_number',
            manager_assignment_number_3,
            'name',
            manager_name_3,
            'email',
            manager_email_3
          ),
          NAMED_STRUCT(
            'assignment_number',
            manager_assignment_number_4,
            'name',
            manager_name_4,
            'email',
            manager_email_4
          ),
          NAMED_STRUCT(
            'assignment_number',
            manager_assignment_number_5,
            'name',
            manager_name_5,
            'email',
            manager_email_5
          ),
          NAMED_STRUCT(
            'assignment_number',
            manager_assignment_number_6,
            'name',
            manager_name_6,
            'email',
            manager_email_6
          ),
          NAMED_STRUCT(
            'assignment_number',
            manager_assignment_number_7,
            'name',
            manager_name_7,
            'email',
            manager_email_7
          ),
          NAMED_STRUCT(
            'assignment_number',
            manager_assignment_number_8,
            'name',
            manager_name_8,
            'email',
            manager_email_8
          ),
          NAMED_STRUCT(
            'assignment_number',
            manager_assignment_number_9,
            'name',
            manager_name_9,
            'email',
            manager_email_9
          ),
          NAMED_STRUCT(
            'assignment_number',
            manager_assignment_number_10,
            'name',
            manager_name_10,
            'email',
            manager_email_10
          )
        ),
        manager_struct -> NOT manager_struct.assignment_number IS NULL
      )
    ) AS manager_struct_path
  FROM hierarchy_union
), hierarchy_filtered /* Keep only records where the CEO is in the chain and flag current validity */ AS (
  SELECT
    assignment_number,
    manager_struct_path,
    dt_valid_from,
    dt_valid_to,
    CASE
      WHEN DATE('{load_start_date}') BETWEEN dt_valid_from AND dt_valid_to
      THEN TRUE
      ELSE FALSE
    END AS is_current
  FROM hierarchy_reordered
  WHERE
    SIZE(
      FILTER(
        manager_struct_path,
        manager_struct -> manager_struct.name = 'GABRIEL BRAGA VIEIRA'
      )
    ) > 0
), hierarchy_versioned /* Version each (assignment_number, period) slice and generate a deterministic surrogate key */ AS (
  SELECT
    *,
    DENSE_RANK() OVER (PARTITION BY assignment_number ORDER BY dt_valid_from NULLS LAST) AS hierarchy_version_seq,
    UNHEX(
      MD5(
        CONCAT_WS(
          '|',
          assignment_number,
          DATE_FORMAT(dt_valid_from, 'yyyy-MM-dd'),
          COALESCE(DATE_FORMAT(dt_valid_to, 'yyyy-MM-dd'), '4712-12-31')
        )
      )
    ) AS sk_hierarchy_version
  FROM hierarchy_filtered
)
SELECT
  sk_hierarchy_version,
  assignment_number,
  manager_struct_path[-1].assignment_number AS assignment_number_l0,
  manager_struct_path[-1].name AS name_l0,
  manager_struct_path[-1].email AS email_l0,
  manager_struct_path[0].assignment_number AS assignment_number_l1,
  manager_struct_path[0].name AS name_l1,
  manager_struct_path[0].email AS email_l1,
  manager_struct_path[1].assignment_number AS assignment_number_l2,
  manager_struct_path[1].name AS name_l2,
  manager_struct_path[1].email AS email_l2,
  manager_struct_path[2].assignment_number AS assignment_number_l3,
  manager_struct_path[2].name AS name_l3,
  manager_struct_path[2].email AS email_l3,
  manager_struct_path[3].assignment_number AS assignment_number_l4,
  manager_struct_path[3].name AS name_l4,
  manager_struct_path[3].email AS email_l4,
  manager_struct_path[4].assignment_number AS assignment_number_l5,
  manager_struct_path[4].name AS name_l5,
  manager_struct_path[4].email AS email_l5,
  manager_struct_path[5].assignment_number AS assignment_number_l6,
  manager_struct_path[5].name AS name_l6,
  manager_struct_path[5].email AS email_l6,
  manager_struct_path[6].assignment_number AS assignment_number_l7,
  manager_struct_path[6].name AS name_l7,
  manager_struct_path[6].email AS email_l7,
  manager_struct_path[7].assignment_number AS assignment_number_l8,
  manager_struct_path[7].name AS name_l8,
  manager_struct_path[7].email AS email_l8,
  manager_struct_path[8].assignment_number AS assignment_number_l9,
  manager_struct_path[8].name AS name_l9,
  manager_struct_path[8].email AS email_l9,
  hierarchy_version_seq AS version,
  is_current,
  dt_valid_from,
  dt_valid_to,
  CURRENT_TIMESTAMP() AS ts_load
FROM hierarchy_versioned
