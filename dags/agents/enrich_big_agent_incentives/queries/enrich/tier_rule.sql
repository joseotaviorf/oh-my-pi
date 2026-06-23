WITH tier AS (
    SELECT
        tier.id AS id_tier,
        IF(ie.external_condition_type = "HUB", ie.id_external_condition, NULL) AS id_business_unit,
        tier.id_classifier_score_rule,
        tier.id_qualifier_score_rule,
        ie.external_condition_type AS incentive_engine_external_condition_type,
        ie.incentive_system,
        tier.name AS tier_name,
        tier.priority AS tier_priority,
        IF(sr_classifier.min_score = '0E-18', 0, CAST(sr_classifier.min_score AS INTEGER)) AS classifier_min_score,
        IF(sr_qualifier.min_score = '0E-18', 0, CAST(sr_qualifier.min_score AS INTEGER)) AS qualifier_min_score,
        tier.ts_created
    FROM
        datalake_big_agent_clean.tier
    LEFT JOIN
        datalake_big_agent_clean.incentive_engine AS ie
            ON ie.id = tier.id_incentive_engine
    LEFT JOIN
        datalake_big_agent_clean.score_rule AS sr_classifier
            ON sr_classifier.id = tier.id_classifier_score_rule
    LEFT JOIN
        datalake_big_agent_clean.score_rule AS sr_qualifier
            ON sr_qualifier.id = tier.id_qualifier_score_rule
    WHERE
        DATE(tier.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
tier_classifier AS (
    SELECT
        tier.id_tier,
        CAST(MAX(pr_classifier.max_points) FILTER(WHERE pr_classifier.operation = 'CS') AS INTEGER) AS classifier_max_points_cs,
        CAST(MAX(pr_classifier.max_points) FILTER(WHERE pr_classifier.operation = 'FL_FR') AS INTEGER) AS classifier_max_points_fl_rent,
        CAST(MAX(pr_classifier.max_points) FILTER(WHERE pr_classifier.operation = 'CCV') AS INTEGER) AS classifier_max_points_ccv,
        CAST(MAX(pr_classifier.max_points) FILTER(WHERE pr_classifier.operation = 'FL_FS') AS INTEGER) AS classifier_max_points_fl_sale,
        CAST(MAX(pr_classifier.max_points) FILTER(WHERE pr_classifier.operation = 'TQC') AS INTEGER) AS classifier_max_points_tqc,
        CAST(MAX(pr_classifier.points) FILTER(WHERE pr_classifier.operation = 'CS') AS INTEGER) AS classifier_multiplier_cs,
        CAST(MAX(pr_classifier.points) FILTER(WHERE pr_classifier.operation = 'FL_FR') AS INTEGER) AS classifier_multiplier_fl_rent,
        CAST(MAX(pr_classifier.points) FILTER(WHERE pr_classifier.operation = 'CCV') AS INTEGER) AS classifier_multiplier_ccv,
        CAST(MAX(pr_classifier.points) FILTER(WHERE pr_classifier.operation = 'FL_FS') AS INTEGER) AS classifier_multiplier_fl_sale,
        CAST(MAX(pr_classifier.points) FILTER(WHERE pr_classifier.operation = 'TQC') AS INTEGER) AS classifier_multiplier_tqc,
        CAST(MAX(pr_classifier.trigger) FILTER(WHERE pr_classifier.operation = 'CS') AS INTEGER) AS classifier_min_points_cs,
        CAST(MAX(pr_classifier.trigger) FILTER(WHERE pr_classifier.operation = 'FL_FR') AS INTEGER) AS classifier_min_points_fl_rent,
        CAST(MAX(pr_classifier.trigger) FILTER(WHERE pr_classifier.operation = 'CCV') AS INTEGER) AS classifier_min_points_ccv,
        CAST(MAX(pr_classifier.trigger) FILTER(WHERE pr_classifier.operation = 'FL_FS') AS INTEGER) AS classifier_min_points_sale,
        CAST(MAX(pr_classifier.trigger) FILTER(WHERE pr_classifier.operation = 'TQC') AS INTEGER) AS classifier_min_points_tqc,
        IF(MAX(pr_classifier.id) IS NOT NULL,
            collect_list(struct(
                    pr_classifier.operation,
                    CAST(pr_classifier.max_points AS INTEGER) AS max_points,
                    CAST(pr_classifier.trigger AS INTEGER) AS min_points,
                    CAST(pr_classifier.points AS INTEGER) AS multiplier)),
            NULL) AS classifier_resume
    FROM
        tier
    LEFT JOIN
        datalake_big_agent_clean.new_points_rule AS pr_classifier
            ON pr_classifier.id_score_rule = tier.id_classifier_score_rule
    GROUP BY 1
),
tier_qualifier AS (
    SELECT
        tier.id_tier,
        CAST(MAX(pr_qualifier.max_points) FILTER(WHERE pr_qualifier.operation = 'CS') AS INTEGER) AS qualifier_max_points_cs,
        CAST(MAX(pr_qualifier.max_points) FILTER(WHERE pr_qualifier.operation = 'FL_FR') AS INTEGER) AS qualifier_max_points_fl_rent,
        CAST(MAX(pr_qualifier.max_points) FILTER(WHERE pr_qualifier.operation = 'CCV') AS INTEGER) AS qualifier_max_points_ccv,
        CAST(MAX(pr_qualifier.max_points) FILTER(WHERE pr_qualifier.operation = 'FL_FS') AS INTEGER) AS qualifier_max_points_fl_sale,
        CAST(MAX(pr_qualifier.max_points) FILTER(WHERE pr_qualifier.operation = 'TQC') AS INTEGER) AS qualifier_max_points_tqc,
        CAST(MAX(pr_qualifier.points) FILTER(WHERE pr_qualifier.operation = 'CS') AS INTEGER) AS qualifier_multiplier_cs,
        CAST(MAX(pr_qualifier.points) FILTER(WHERE pr_qualifier.operation = 'FL_FR') AS INTEGER) AS qualifier_multiplier_fl_rent,
        CAST(MAX(pr_qualifier.points) FILTER(WHERE pr_qualifier.operation = 'CCV') AS INTEGER) AS qualifier_multiplier_ccv,
        CAST(MAX(pr_qualifier.points) FILTER(WHERE pr_qualifier.operation = 'FL_FS') AS INTEGER) AS qualifier_multiplier_fl_sale,
        CAST(MAX(pr_qualifier.points) FILTER(WHERE pr_qualifier.operation = 'TQC') AS INTEGER) AS qualifier_multiplier_tqc,
        CAST(MAX(pr_qualifier.trigger) FILTER(WHERE pr_qualifier.operation = 'CS') AS INTEGER) AS qualifier_min_points_cs,
        CAST(MAX(pr_qualifier.trigger) FILTER(WHERE pr_qualifier.operation = 'FL_FR') AS INTEGER) AS qualifier_min_points_fl_rent,
        CAST(MAX(pr_qualifier.trigger) FILTER(WHERE pr_qualifier.operation = 'CCV') AS INTEGER) AS qualifier_min_points_ccv,
        CAST(MAX(pr_qualifier.trigger) FILTER(WHERE pr_qualifier.operation = 'FL_FS') AS INTEGER) AS qualifier_min_points_sale,
        CAST(MAX(pr_qualifier.trigger) FILTER(WHERE pr_qualifier.operation = 'TQC') AS INTEGER) AS qualifier_min_points_tqc,
        IF(MAX(pr_qualifier.id) IS NOT NULL,
            collect_list(struct(
                    pr_qualifier.operation,
                    CAST(pr_qualifier.max_points AS INTEGER) AS max_points,
                    CAST(pr_qualifier.trigger AS INTEGER) AS min_points,
                    CAST(pr_qualifier.points AS INTEGER) AS multiplier)),
            NULL) AS qualifier_resume
    FROM
        tier
    LEFT JOIN
        datalake_big_agent_clean.new_points_rule AS pr_qualifier
            ON pr_qualifier.id_score_rule = tier.id_qualifier_score_rule
    GROUP BY 1
)
SELECT
    tier.id_tier,
    tier.id_business_unit,
    tier.incentive_engine_external_condition_type,
    tier.incentive_system,
    tier.tier_name,
    tier.tier_priority,
    tier.classifier_min_score,
    tc.classifier_resume,
    tier.qualifier_min_score,
    tq.qualifier_resume,
    tc.classifier_max_points_cs,
    tc.classifier_max_points_fl_rent,
    tc.classifier_max_points_ccv,
    tc.classifier_max_points_fl_sale,
    tc.classifier_max_points_tqc,
    tc.classifier_min_points_cs,
    tc.classifier_min_points_fl_rent,
    tc.classifier_min_points_ccv,
    tc.classifier_min_points_sale,
    tc.classifier_min_points_tqc,
    tc.classifier_multiplier_cs,
    tc.classifier_multiplier_fl_rent,
    tc.classifier_multiplier_ccv,
    tc.classifier_multiplier_fl_sale,
    tc.classifier_multiplier_tqc,
    tq.qualifier_max_points_cs,
    tq.qualifier_max_points_fl_rent,
    tq.qualifier_max_points_ccv,
    tq.qualifier_max_points_fl_sale,
    tq.qualifier_max_points_tqc,
    tq.qualifier_min_points_cs,
    tq.qualifier_min_points_fl_rent,
    tq.qualifier_min_points_ccv,
    tq.qualifier_min_points_sale,
    tq.qualifier_min_points_tqc,
    tq.qualifier_multiplier_cs,
    tq.qualifier_multiplier_fl_rent,
    tq.qualifier_multiplier_ccv,
    tq.qualifier_multiplier_fl_sale,
    tq.qualifier_multiplier_tqc,
    tier.ts_created
FROM
    tier
LEFT JOIN
    tier_classifier AS tc
        ON tier.id_tier = tc.id_tier
LEFT JOIN
    tier_qualifier AS tq
        ON tier.id_tier = tq.id_tier
