WITH
lesson_contents_base AS (
  SELECT
    id_pathway,
    id_section,
    id_lesson,
    id_content,
    is_required
  FROM
    datalake_learning.lesson_contents
),
pathway_content_required AS (
  SELECT
    id_pathway,
    id_content,
    MAX(is_required) AS is_required
  FROM
    lesson_contents_base
  GROUP BY
    id_pathway,
    id_content
),
pathway_totals AS (
  SELECT
    id_pathway,
    COUNT(*) AS total_pathway,
    COUNT(CASE WHEN is_required THEN 1 END) AS total_pathway_required,
    COUNT(CASE WHEN NOT is_required THEN 1 END) AS total_pathway_optional
  FROM
    pathway_content_required
  GROUP BY
    id_pathway
),
section_content_required AS (
  SELECT
    id_section,
    id_pathway,
    id_content,
    MAX(is_required) AS is_required
  FROM
    lesson_contents_base
  GROUP BY
    id_section,
    id_pathway,
    id_content
),
section_totals AS (
  SELECT
    id_section,
    id_pathway,
    COUNT(*) AS total_section,
    COUNT(CASE WHEN is_required THEN 1 END) AS total_section_required,
    COUNT(CASE WHEN NOT is_required THEN 1 END) AS total_section_optional
  FROM
    section_content_required
  GROUP BY
    id_section,
    id_pathway
),
lesson_content_required AS (
  SELECT
    id_lesson,
    id_section,
    id_pathway,
    id_content,
    MAX(is_required) AS is_required
  FROM
    lesson_contents_base
  GROUP BY
    id_lesson,
    id_section,
    id_pathway,
    id_content
),
lesson_totals AS (
  SELECT
    id_lesson,
    id_section,
    id_pathway,
    COUNT(*) AS total_lesson,
    COUNT(CASE WHEN is_required THEN 1 END) AS total_lesson_required,
    COUNT(CASE WHEN NOT is_required THEN 1 END) AS total_lesson_optional
  FROM
    lesson_content_required
  GROUP BY
    id_lesson,
    id_section,
    id_pathway
),
completions_with_placement AS (
  SELECT
    cc.id_user,
    cc.id_content,
    cc.dt_completed,
    lc.id_pathway,
    lc.id_section,
    lc.id_lesson,
    lc.is_required
  FROM
    datalake_learning.content_completions AS cc
  INNER JOIN
    lesson_contents_base AS lc
    ON lc.id_content = cc.id_content
),
pathway_completion_detail AS (
  SELECT
    id_user,
    id_pathway,
    id_content,
    MAX(dt_completed) AS dt_completion,
    MAX(is_required) AS is_required
  FROM
    completions_with_placement
  GROUP BY
    id_user,
    id_pathway,
    id_content
),
user_pathway_completions AS (
  SELECT
    id_user,
    id_pathway,
    COUNT(*) AS total_completions,
    COUNT(CASE WHEN is_required THEN 1 END) AS total_completions_required,
    COUNT(CASE WHEN NOT is_required THEN 1 END) AS total_completions_optional,
    MAX(dt_completion) AS dt_completion
  FROM
    pathway_completion_detail
  GROUP BY
    id_user,
    id_pathway
),
section_completion_detail AS (
  SELECT
    id_user,
    id_section,
    id_pathway,
    id_content,
    MAX(dt_completed) AS dt_completion,
    MAX(is_required) AS is_required
  FROM
    completions_with_placement
  GROUP BY
    id_user,
    id_section,
    id_pathway,
    id_content
),
user_section_completions AS (
  SELECT
    id_user,
    id_section,
    id_pathway,
    COUNT(*) AS total_completions,
    COUNT(CASE WHEN is_required THEN 1 END) AS total_completions_required,
    COUNT(CASE WHEN NOT is_required THEN 1 END) AS total_completions_optional,
    MAX(dt_completion) AS dt_completion
  FROM
    section_completion_detail
  GROUP BY
    id_user,
    id_section,
    id_pathway
),
lesson_completion_detail AS (
  SELECT
    id_user,
    id_lesson,
    id_section,
    id_pathway,
    id_content,
    MAX(dt_completed) AS dt_completion,
    MAX(is_required) AS is_required
  FROM
    completions_with_placement
  GROUP BY
    id_user,
    id_lesson,
    id_section,
    id_pathway,
    id_content
),
user_lesson_completions AS (
  SELECT
    id_user,
    id_lesson,
    id_section,
    id_pathway,
    COUNT(*) AS total_completions,
    COUNT(CASE WHEN is_required THEN 1 END) AS total_completions_required,
    COUNT(CASE WHEN NOT is_required THEN 1 END) AS total_completions_optional,
    MAX(dt_completion) AS dt_completion
  FROM
    lesson_completion_detail
  GROUP BY
    id_user,
    id_lesson,
    id_section,
    id_pathway
),
content_completion_dates AS (
  SELECT
    id_user,
    id_content,
    MAX(dt_completed) AS dt_completion
  FROM
    completions_with_placement
  GROUP BY
    id_user,
    id_content
),
content_is_required AS (
  SELECT
    id_content,
    MAX(is_required) AS is_required
  FROM
    lesson_contents_base
  GROUP BY
    id_content
),
content_placement AS (
  SELECT DISTINCT
    id_content,
    id_lesson,
    id_section,
    id_pathway
  FROM
    lesson_contents_base
),
all_users AS (
  SELECT
    id AS id_user
  FROM
    datalake_degreed_clean.users
),
combined_completions AS (
  SELECT
    au.id_user,
    pt.id_pathway AS id_learning_object,
    CAST(NULL AS STRING) AS id_lesson,
    CAST(NULL AS STRING) AS id_section,
    pt.id_pathway,
    'Pathway' AS learning_object_type,
    1 AS learning_object_order,
    pt.total_pathway_required AS content_required,
    pt.total_pathway_optional AS content_optional,
    pt.total_pathway AS content_total,
    COALESCE(upc.total_completions_required, 0) AS completed_required,
    COALESCE(upc.total_completions_optional, 0) AS completed_optional,
    COALESCE(upc.total_completions, 0) AS completed_total,
    upc.dt_completion
  FROM
    all_users AS au
  CROSS JOIN
    pathway_totals AS pt
  LEFT JOIN
    user_pathway_completions AS upc
    ON upc.id_user = au.id_user
    AND upc.id_pathway = pt.id_pathway
  UNION ALL
  SELECT
    au.id_user,
    st.id_section AS id_learning_object,
    CAST(NULL AS STRING) AS id_lesson,
    st.id_section,
    st.id_pathway,
    'Section' AS learning_object_type,
    2 AS learning_object_order,
    st.total_section_required AS content_required,
    st.total_section_optional AS content_optional,
    st.total_section AS content_total,
    COALESCE(usc.total_completions_required, 0) AS completed_required,
    COALESCE(usc.total_completions_optional, 0) AS completed_optional,
    COALESCE(usc.total_completions, 0) AS completed_total,
    usc.dt_completion
  FROM
    all_users AS au
  CROSS JOIN
    section_totals AS st
  LEFT JOIN
    user_section_completions AS usc
    ON usc.id_user = au.id_user
    AND usc.id_section = st.id_section
    AND usc.id_pathway = st.id_pathway
  UNION ALL
  SELECT
    au.id_user,
    lt.id_lesson AS id_learning_object,
    lt.id_lesson,
    lt.id_section,
    lt.id_pathway,
    'Lesson' AS learning_object_type,
    3 AS learning_object_order,
    lt.total_lesson_required AS content_required,
    lt.total_lesson_optional AS content_optional,
    lt.total_lesson AS content_total,
    COALESCE(ulc.total_completions_required, 0) AS completed_required,
    COALESCE(ulc.total_completions_optional, 0) AS completed_optional,
    COALESCE(ulc.total_completions, 0) AS completed_total,
    ulc.dt_completion
  FROM
    all_users AS au
  CROSS JOIN
    lesson_totals AS lt
  LEFT JOIN
    user_lesson_completions AS ulc
    ON ulc.id_user = au.id_user
    AND ulc.id_lesson = lt.id_lesson
    AND ulc.id_section = lt.id_section
    AND ulc.id_pathway = lt.id_pathway
  UNION ALL
  SELECT
    au.id_user,
    cp.id_content AS id_learning_object,
    cp.id_lesson,
    cp.id_section,
    cp.id_pathway,
    'Content' AS learning_object_type,
    4 AS learning_object_order,
    CASE WHEN COALESCE(cr.is_required, false) THEN 1 ELSE 0 END AS content_required,
    CASE WHEN NOT COALESCE(cr.is_required, false) THEN 1 ELSE 0 END AS content_optional,
    1 AS content_total,
    CASE WHEN COALESCE(cr.is_required, false) AND ccd.dt_completion IS NOT NULL THEN 1 ELSE 0 END AS completed_required,
    CASE WHEN NOT COALESCE(cr.is_required, false) AND ccd.dt_completion IS NOT NULL THEN 1 ELSE 0 END AS completed_optional,
    CASE WHEN ccd.dt_completion IS NOT NULL THEN 1 ELSE 0 END AS completed_total,
    ccd.dt_completion
  FROM
    all_users AS au
  CROSS JOIN
    content_placement AS cp
  LEFT JOIN
    content_is_required AS cr
    ON cr.id_content = cp.id_content
  LEFT JOIN
    content_completion_dates AS ccd
    ON ccd.id_user = au.id_user
    AND ccd.id_content = cp.id_content
)
SELECT
  id_user,
  id_learning_object,
  id_lesson,
  id_section,
  id_pathway,
  learning_object_type,
  learning_object_order,
  content_required,
  content_optional,
  content_total,
  completed_required,
  completed_optional,
  completed_total,
  CAST(100.0 * completed_required / NULLIF(content_required, 0) AS DECIMAL(10, 2)) AS pct_completed_required,
  CAST(100.0 * completed_optional / NULLIF(content_optional, 0) AS DECIMAL(10, 2)) AS pct_completed_optional,
  CAST(100.0 * completed_total / content_total AS DECIMAL(10, 2)) AS pct_completed_total,
  dt_completion,
  NOW() AS ts_load
FROM
  combined_completions