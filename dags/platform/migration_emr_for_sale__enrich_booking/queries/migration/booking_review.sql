SELECT
  b.id AS id_booking,
  MIN(review.status) AS review_status,
  MAX(review.type) AS review_type,
  MAX(
    CASE
      WHEN array_contains(review.labels, '') THEN NULL
      ELSE review.labels[1]
    END
  ) AS visit_not_happened_reason,
  MAX(
    CASE
      WHEN ftr.name = 'wronglistinginfo' THEN array_join(rf.rating_selected, ',')
      ELSE NULL
    END
  ) AS wrong_listing_info,
  MAX(
    CASE
      WHEN ftr.name = 'noofferintentreason' THEN array_join(rf.rating_selected, ',')
      ELSE NULL
    END
  ) AS no_offer_intent_reason,
  CAST(
    MAX(
      CASE
        WHEN ftr.name = 'painting' THEN array_join(rf.rating_selected, ',')
        ELSE NULL
      END
    ) AS SMALLINT
  ) AS painting,
  CAST(
    MAX(
      CASE
        WHEN ftr.name = 'costbenefit' THEN array_join(rf.rating_selected, ',')
        ELSE NULL
      END
    ) AS SMALLINT
  ) AS cost_benefit,
  CAST(
    MAX(
      CASE
        WHEN ftr.name = 'conservation' THEN array_join(rf.rating_selected, ',')
        ELSE NULL
      END
    ) AS SMALLINT
  ) AS conservation,
  CAST(
    MAX(
      CASE
        WHEN ftr.name = 'cleaning' THEN array_join(rf.rating_selected, ',')
        ELSE NULL
      END
    ) AS SMALLINT
  ) AS cleaning,
  CAST(
    MAX(
      CASE
        WHEN ftr.name = 'furniture' THEN array_join(rf.rating_selected, ',')
        ELSE NULL
      END
    ) AS SMALLINT
  ) AS furniture,
  CAST(
    MAX(
      CASE
        WHEN ftr.name = 'naturallight' THEN array_join(rf.rating_selected, ',')
        ELSE NULL
      END
    ) AS SMALLINT
  ) AS natural_light,
  CAST(
    MAX(
      CASE
        WHEN ftr.name = 'indoorsilence' THEN array_join(rf.rating_selected, ',')
        ELSE NULL
      END
    ) AS SMALLINT
  ) AS indoor_silence,
  CAST(
    MAX(
      CASE
        WHEN ftr.name = 'agentperformance' THEN array_join(rf.rating_selected, ',')
        ELSE NULL
      END
    ) AS SMALLINT
  ) AS agent_performance,
  CAST(
    MAX(
      CASE
        WHEN ftr.name = 'wantsameagent' THEN array_join(rf.rating_selected, ',')
        ELSE NULL
      END
    ) AS BOOLEAN
  ) AS does_want_same_agent,
  MAX(
    CASE
      WHEN ftr.name = 'visittype' THEN array_join(rf.rating_selected, ',')
      ELSE NULL
    END
  ) AS visit_type,
  MAX(review.comment) AS comment,
  CAST(
    MAX(
      CASE
        WHEN ftr.name = 'listingfidelity_v2' THEN array_join(rf.rating_selected, ',')
        ELSE NULL
      END
    ) AS BOOLEAN
  ) AS is_listing_accurate,
  CAST(
    MAX(
      CASE
        WHEN ftr.name = 'offerintent' THEN array_join(rf.rating_selected, ',')
        ELSE NULL
      END
    ) AS BOOLEAN
  ) AS is_offer_intent
FROM
  datalake_insider_clean.review AS review
  JOIN
    datalake_ebdb_clean.visit AS v
      ON review.id_reviewed = v.code
  JOIN
    datalake_ebdb_clean.booking AS b
      ON b.id_visit = v.id
  LEFT JOIN
    datalake_insider_clean.review_feature AS rf
      ON review.id = rf.id_review
  LEFT JOIN
    datalake_insider_clean.feature AS ftr
      ON rf.id_feature = ftr.id
GROUP BY 1