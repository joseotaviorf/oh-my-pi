WITH customer_conversions AS (
  SELECT
    cc.uuid_person,
    cc.id_user,
    cc.id_customer,
    cc.id_dispatch,
    cc.id_dispatch_user,
    cc.id_answer,
    cc.customer_type,
    cc.status,
    a.score_category,
    a.nps_answer,
    a.nps_comment,
    a.ts_answer_sent_utc,
    ROUND(a.seconds_spent_answering/60.0,2) AS minutes_spent_answering,
    cc.ts_dispatch_created AS ts_created
  FROM
    datalake_tracksale.customer_conversions AS cc
  LEFT JOIN datalake_tracksale.answer AS a
    ON cc.id_answer = a.id
  WHERE
    cc.id_customer != '-1' -- filter out dispatches FROM unidentified customers
),
customer_metrics AS (
  SELECT
    id_user,
    uuid_person,
    id_customer,
    MAX(id_answer) AS id_last_answer,
    COUNT(id_dispatch) AS total_dispatches,
    COUNT(id_answer) AS total_answers,
    COUNT(CASE
      WHEN customer_type IN ('seller','buyer') THEN id_answer
        END)
      AS total_answers_forsale,
    COUNT(CASE
        WHEN customer_type IN ('IQ','PP') THEN id_answer
      END
    ) AS total_answers_forrent,
    COUNT(CASE
        WHEN score_category = 'promoter' THEN id_answer
      END
    ) AS promoters,
    COUNT(CASE
        WHEN score_category = 'passive' THEN id_answer
      END
    ) AS passives,
    COUNT(CASE
        WHEN score_category = 'detractor' THEN id_answer
      END) AS detractors,
    COUNT(CASE
        WHEN score_category = 'promoter' AND customer_type IN ('seller','buyer') THEN id_answer
      END
    ) AS promoters_forsale,
    COUNT(CASE
        WHEN score_category = 'detractor' AND customer_type IN ('seller','buyer') THEN id_answer
      END
    ) AS detractors_forsale,
    COUNT(CASE
        WHEN score_category = 'promoter' AND customer_type IN ('IQ','PP') THEN id_answer
      END
    ) AS promoters_forrent,
    COUNT(CASE
        WHEN score_category = 'detractor' AND customer_type IN ('IQ','PP') THEN id_answer
      END
    ) AS detractors_forrent,
    COUNT(CASE
        WHEN nps_comment IS NOT NULL THEN id_answer
      END
    ) AS total_comments,
    AVG(minutes_spent_answering) AS avg_minutes_response_time,
    AVG(nps_answer) AS avg_score,
    AVG(CASE
            WHEN customer_type IN ('seller','buyer') THEN nps_answer
        END
    ) AS avg_score_forsale,
    AVG(CASE
            WHEN customer_type IN ('IQ','PP') THEN nps_answer
        END
    ) AS avg_score_forrent,
    COUNT(CASE WHEN status != 'Finalizado' THEN id_dispatch END) > 0 AS has_pending_survey,
    CAST(MAX(ts_created) AS date) AS dt_last_dispatched,
    MIN(ts_created) AS ts_first_dispatched,
    CAST(MAX(ts_answer_sent_utc) AS DATE) AS dt_last_answer,
    CAST(MIN(ts_answer_sent_utc) AS DATE) AS dt_first_answer
  FROM
      customer_conversions
  GROUP BY 1, 2, 3
),
conversion_metrics AS (
  SELECT
    uuid_person,
    id_user,
    id_customer,
    id_last_answer,
    total_dispatches,
    total_answers,
    total_answers_forsale,
    total_answers_forrent,
    promoters AS answers_as_promoter,
    detractors AS answers_as_detractor,
    avg_minutes_response_time,
    avg_score,
    avg_score_forsale,
    avg_score_forrent,
    CASE
      WHEN total_answers > 0 THEN ROUND(100.0*(promoters - detractors)/total_answers,0)
    END AS overall_nps,
    CASE
      WHEN total_answers_forsale > 0 THEN ROUND(100.0*(promoters_forsale - detractors_forsale)/total_answers_forsale,0)
    END AS overall_nps_forsale,
    CASE
      WHEN total_answers_forrent > 0 THEN ROUND(100.0*(promoters_forrent - detractors_forrent)/total_answers_forrent,0)
    END AS overall_nps_forrent,
    CASE
      WHEN total_dispatches > 0 THEN ROUND(1.0*total_answers/total_dispatches,3)
    END AS answer_rate,
    CASE
      WHEN total_answers > 0 THEN ROUND(1.0*total_comments/total_answers,3)
    END AS comment_rate,
    has_pending_survey,
    dt_last_dispatched,
    ts_first_dispatched,
    dt_last_answer,
    dt_first_answer
  FROM
    customer_metrics
),
last_category AS (
  SELECT
    cc.uuid_person,
    cc.id_customer,
    cc.nps_answer AS last_score,
    cc.score_category AS last_category
  FROM 
    customer_conversions cc
  INNER JOIN
    customer_metrics cm
      ON cm.id_last_answer = cc.id_answer
),
second_last_answer AS (
  SELECT
    cc.uuid_person,
    cc.id_customer,
    max(cc.id_answer) AS id_second_last_answer
  FROM
    customer_conversions cc
  LEFT JOIN
    customer_metrics cm
      ON cm.id_customer = cc.id_customer
  WHERE
    cc.id_answer < cm.id_last_answer
  GROUP BY 1, 2
),
second_last_category AS (
  SELECT
    cc.id_customer,
    cc.score_category AS second_last_category
  FROM
    customer_conversions cc
  INNER JOIN
    second_last_answer sla
      ON sla.id_second_last_answer = cc.id_answer
),
last_shift AS (
  SELECT
    lc.id_customer,
    lc.last_score,
    CONCAT(slc.second_last_category,CONCAT(':',lc.last_category)) AS last_shift_type
  FROM
    last_category lc
  INNER JOIN
    second_last_category slc
      ON slc.id_customer = lc.id_customer
  WHERE
    lc.last_category != slc.second_last_category
)
SELECT
  COALESCE(cm.id_user, -1) AS sk_user,
  COALESCE(cm.uuid_person, -1) as sk_uuid_person,
  COALESCE(cm.id_customer,-1) AS sk_nps_customer,
  ls.last_shift_type,
  cm.total_dispatches,
  cm.total_answers,
  cm.total_answers_forsale,
  cm.total_answers_forrent,
  cm.answers_as_promoter,
  cm.answers_as_detractor,
  cm.answer_rate,
  cm.comment_rate,
  cm.avg_score,
  cm.avg_score_forsale,
  cm.avg_score_forrent,
  ls.last_score,
  cm.overall_nps,
  cm.overall_nps_forsale,
  cm.overall_nps_forrent,
  cm.avg_minutes_response_time,
  cm.has_pending_survey,
  cm.dt_last_dispatched,
  cm.dt_last_answer,
  cm.dt_first_answer,
  current_timestamp AS ts_load
FROM
  conversion_metrics cm
LEFT JOIN
  last_shift ls
    ON ls.id_customer = cm.id_customer