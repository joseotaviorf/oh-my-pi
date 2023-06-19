SELECT
    '1-2' AS sk_cohort_type,
    'VISIT_BOOKED_TO_VISIT_COMPLETED' AS cohort_name,
    'VB2VC' AS abbreviation
UNION ALL
SELECT
    '1-3' AS sk_cohort_type,
    'VISIT_BOOKED_TO_OFFER_SUBMITTED' AS cohort_name,
    'VB2OS' AS abbreviation
UNION ALL
SELECT
    '1-4' AS sk_cohort_type,
    'VISIT_BOOKED_TO_OFFER_APPROVED' AS cohort_name,
    'VB2OA' AS abbreviation
UNION ALL
SELECT
    '1-5' AS sk_cohort_type,
    'VISIT_BOOKED_TO_EVALUATION_STARTED' AS cohort_name,
    'VB2ES' AS abbreviation
UNION ALL
SELECT
    '1-6' AS sk_cohort_type,
    'VISIT_BOOKED_TO_EVALUATION_POSITIVE' AS cohort_name,
    'VB2EP' AS abbreviation
UNION ALL
SELECT
    '1-7' AS sk_cohort_type,
    'VISIT_BOOKED_TO_DOC_SENT' AS cohort_name,
    'VB2DS' AS abbreviation
UNION ALL
SELECT
    '1-8' AS sk_cohort_type,
    'VISIT_BOOKED_TO_CREDIT_APPROVED' AS cohort_name,
    'VB2CA' AS abbreviation
UNION ALL
SELECT
    '1-9' AS sk_cohort_type,
    'VISIT_BOOKED_TO_CONTRACT_SIGNED' AS cohort_name,
    'VB2CS' AS abbreviation
UNION ALL
SELECT
    '2-3' AS sk_cohort_type,
    'VISIT_COMPLETED_TO_OFFER_SUBMITTED' AS cohort_name,
    'VC2OS' AS abbreviation
UNION ALL
SELECT
    '2-4' AS sk_cohort_type,
    'VISIT_COMPLETED_TO_OFFER_APPROVED' AS cohort_name,
    'VB2OA' AS abbreviation
UNION ALL
SELECT
    '2-5' AS sk_cohort_type,
    'VISIT_COMPLETED_TO_EVALUATION_STARTED' AS cohort_name,
    'VB2ES' AS abbreviation
UNION ALL
SELECT
    '2-6' AS sk_cohort_type,
    'VISIT_COMPLETED_TO_EVALUATION_POSITIVE' AS cohort_name,
    'VB2EP' AS abbreviation
UNION ALL
SELECT
    '2-7' AS sk_cohort_type,
    'VISIT_COMPLETED_TO_DOC_SENT' AS cohort_name,
    'VB2DS' AS abbreviation
UNION ALL
SELECT
    '2-8' AS sk_cohort_type,
    'VISIT_COMPLETED_TO_CREDIT_APPROVED' AS cohort_name,
    'VC2CA' AS abbreviation
UNION ALL
SELECT
    '2-9' AS sk_cohort_type,
    'VISIT_COMPLETED_TO_CONTRACT_SIGNED' AS cohort_name,
    'VC2CS' AS abbreviation
UNION ALL
SELECT
    '3-4' AS sk_cohort_type,
    'OFFER_SUBMITTED_TO_OFFER_APPROVED' AS cohort_name,
    'OS2OA' AS abbreviation
UNION ALL
SELECT
    '3-5' AS sk_cohort_type,
    'OFFER_SUBMITTED_TO_EVALUATION_STARTED' AS cohort_name,
    'OS2ES' AS abbreviation
UNION ALL
SELECT
    '3-6' AS sk_cohort_type,
    'OFFER_SUBMITTED_TO_EVALUATION_POSITIVE' AS cohort_name,
    'OS2EP' AS abbreviation
UNION ALL
SELECT
    '3-7' AS sk_cohort_type,
    'OFFER_SUBMITTED_TO_DOC_SENT' AS cohort_name,
    'OS2DS' AS abbreviation
UNION ALL
SELECT
    '3-8' AS sk_cohort_type,
    'OFFER_SUBMITTED_TO_CREDIT_APPROVED' AS cohort_name,
    'OS2CA' AS abbreviation
UNION ALL
SELECT
    '3-9' AS sk_cohort_type,
    'OFFER_SUBMITTED_TO_CONTRACT_SIGNED' AS cohort_name,
    'OS2CS' AS abbreviation
UNION ALL
SELECT
    '4-5' AS sk_cohort_type,
    'OFFER_APPROVED_TO_EVALUATION_STARTED' AS cohort_name,
    'OA2ES' AS abbreviation
UNION ALL
SELECT
    '4-6' AS sk_cohort_type,
    'OFFER_APPROVED_TO_EVALUATION_POSITIVE' AS cohort_name,
    'OA2EP' AS abbreviation
UNION ALL
SELECT
    '4-7' AS sk_cohort_type,
    'OFFER_APPROVED_TO_DOC_SENT' AS cohort_name,
    'OA2DS' AS abbreviation
UNION ALL
SELECT
    '4-8' AS sk_cohort_type,
    'OFFER_APPROVED_TO_CREDIT_APPROVED' AS cohort_name,
    'OA2CA' AS abbreviation
UNION ALL
SELECT
    '4-9' AS sk_cohort_type,
    'OFFER_APPROVED_TO_CONTRACT_SIGNED' AS cohort_name,
    'OA2CS' AS abbreviation
UNION ALL
SELECT
    '5-6' AS sk_cohort_type,
    'EVALUATION_STARTED_TO_EVALUATION_POSITIVE' AS cohort_name,
    'ES2EP' AS abbreviation
UNION ALL
SELECT
    '5-7' AS sk_cohort_type,
    'EVALUATION_STARTED_TO_DOC_SENT' AS cohort_name,
    'ES2DS' AS abbreviation
UNION ALL
SELECT
    '5-8' AS sk_cohort_type,
    'EVALUATION_STARTED_TO_CREDIT_APPROVED' AS cohort_name,
    'ES2CA' AS abbreviation
UNION ALL
SELECT
    '5-9' AS sk_cohort_type,
    'EVALUATION_STARTED_TO_CONTRACT_SIGNED' AS cohort_name,
    'ES2CS' AS abbreviation
UNION ALL
SELECT
    '6-7' AS sk_cohort_type,
    'EVALUATION_POSITIVE_TO_DOC_SENT' AS cohort_name,
    'EP2DS' AS abbreviation
UNION ALL
SELECT
    '6-8' AS sk_cohort_type,
    'EVALUATION_POSITIVE_TO_CREDIT_APPROVED' AS cohort_name,
    'EP2CA' AS abbreviation
UNION ALL
SELECT
    '6-9' AS sk_cohort_type,
    'EVALUATION_POSITIVE_TO_CONTRACT_SIGNED' AS cohort_name,
    'EP2CS' AS abbreviation
UNION ALL
SELECT
    '7-8' AS sk_cohort_type,
    'DOC_SENT_TO_CREDIT_APPROVED' AS cohort_name,
    'DS2CA' AS abbreviation
UNION ALL
SELECT
    '7-9' AS sk_cohort_type,
    'DOC_SENT_TO_CONTRACT_SIGNED' AS cohort_name,
    'DS2CS' AS abbreviation
UNION ALL
SELECT
    '8-9' AS sk_cohort_type,
    'CREDIT_APPROVED_TO_CONTRACT_SIGNED' AS cohort_name,
    'CA2CS' AS abbreviation