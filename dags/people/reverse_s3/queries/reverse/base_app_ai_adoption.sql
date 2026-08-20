-- Active-employee AI adoption roster, exported as S3 CSV.
-- Consumer: AI Governance team (Base44 office bucket, aiadoption/vertical_information.csv).
-- One row per active employee assignment: work email, assignment number, and the
-- work email of the layer-1 leader (one level below the CEO) in the reporting chain.
SELECT
    LOWER(es.work_email) AS email,
    LOWER(es.assignment_number) AS assignment_number,
    NULLIF(LOWER(es.email_l1), '-1') AS email_l1
FROM
    metric_people.employee_snapshots AS es
WHERE
    es.is_current_for_employee = TRUE
    AND es.is_active = TRUE
