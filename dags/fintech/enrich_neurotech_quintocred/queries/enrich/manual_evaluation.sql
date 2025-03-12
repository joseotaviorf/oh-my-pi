SELECT
    m.proposal_number AS id_propose,
    CASE
        WHEN m.proposal_rating IS NULL THEN 'Missing'
        WHEN m.proposal_rating = 'NaN' THEN 'Missing'
        ELSE m.proposal_rating
    END AS rating,
    m.calc_status AS status,
    m.proposal_name AS main_proponent_name,
    CASE
      WHEN calc_status = 'R' AND calc_denied_reason_first_proponent <> 'NaN' THEN calc_denied_reason_first_proponent
      WHEN calc_status = 'R' AND calc_denied_reason_second_proponent <> 'NaN' THEN calc_denied_reason_second_proponent
      WHEN calc_status = 'R' AND calc_denied_reason_third_proponent <> 'NaN' THEN calc_denied_reason_third_proponent
      WHEN calc_status = 'R' AND calc_denied_reason_fourth_proponent <> 'NaN' THEN calc_denied_reason_fourth_proponent
      WHEN calc_status = 'R' AND calc_denied_reason_first_proponent = 'NaN' AND calc_denied_reason_second_proponent = 'NaN' AND calc_denied_reason_third_proponent = 'NaN' AND calc_denied_reason_fourth_proponent = 'NaN' THEN 'Analyst did not select the reason for rejection'
      ELSE 'Proposal was not rejected'
    END AS reason_rejection,
    IF(ROW_NUMBER() OVER (PARTITION BY m.proposal_number ORDER BY m.ts_operation DESC) = 1, TRUE, FALSE) AS is_last_register,
    min_date.ts_begin AS dt_propose,
    DATE_ADD(HOUR, -3, m.ts_proposal_dh_registration) AS ts_begin,
    m.ts_operation AS ts_end,
    m.ts_operation
FROM
    datalake_velo_neurotech_clean.logs_scoping_policy m
LEFT JOIN(
    SELECT
        proposal_number,
        MIN(DATE(DATE_ADD(HOUR, -3, ts_proposal_dh_registration))) AS ts_begin
        FROM datalake_velo_neurotech_clean.logs_scoping_policy
        GROUP BY 1
    ) AS min_date
    ON min_date.proposal_number = m.proposal_number
WHERE
    m.proposal_number IS NOT NULL
