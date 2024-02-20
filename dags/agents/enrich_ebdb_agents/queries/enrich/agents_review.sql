SELECT
    booking.id AS id_booking,
    rating.rating,
    rating.complementary_info AS tag_other,
    COALESCE(MAX(rating_label.is_label_punctuality), FALSE) AS is_punctual,
    COALESCE(MAX(rating_label.is_label_agent_well_informed), FALSE) AS is_agent_well_informed,
    COALESCE(MAX(rating_label.is_label_kindness), FALSE) AS is_kind,
    COALESCE(MAX(rating_label.is_label_no_kindness), FALSE) AS is_not_kind,
    COALESCE(MAX(rating_label.is_label_house_as_listing), FALSE) AS is_house_as_listing,
    COALESCE(MAX(rating_label.is_label_house_not_as_listing), FALSE) AS is_house_not_as_listing,
    COALESCE(MAX(rating_label.is_label_other_reason_positive AND rating_label.rating_reference >= 4), FALSE) AS is_other_positive_reason,
    COALESCE(MAX(rating_label.is_label_other_reason_negative AND rating_label.rating_reference <= 3), FALSE) AS is_other_negative_reason,
    COALESCE(MAX(rating_label.is_label_agent_late), FALSE) AS is_agent_late,
    COALESCE(MAX(rating_label.is_label_agent_with_no_info), FALSE) AS is_agent_without_info,
    rating.ts_created AS ts_rating_created
FROM
    datalake_ebdb_clean.visit
JOIN
    datalake_ebdb_clean.user
        ON user.id = visit.id_visitor
JOIN
    datalake_ebdb_clean.real_estate_agent_rating AS rating
        ON rating.id = visit.id_real_estate_agent_rating
JOIN
    datalake_ebdb_clean.device
        ON device.id_user = visit.id_visitor
JOIN
    datalake_ebdb_clean.booking
        ON booking.id_visit = visit.id
LEFT JOIN
    datalake_ebdb_clean.real_estate_agent_rating_rating_label AS label
        ON label.id_real_estate_agent_rating = visit.id_real_estate_agent_rating
LEFT JOIN
    datalake_ebdb_agents.rating_label
        ON rating_label.id = label.id_rating_label
WHERE
    visit.id_real_estate_agent_rating IS NOT NULL
    AND device.mobile_app = 'Inquilinos'
    AND booking.visit_fup IS NOT NULL
GROUP BY
    1, 2, 3, 14
