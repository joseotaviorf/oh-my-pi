SELECT
    102 AS sk_cohort_type,
    'VISIT_BOOKED_TO_VISIT_COMPLETED' AS cohort_name,
    'VB2VC' AS abbreviation
UNION ALL
SELECT
    103 AS sk_cohort_type,
    'VISIT_BOOKED_TO_OFFER_SUBMITTED' AS cohort_name,
    'VB2OS' AS abbreviation
UNION ALL
SELECT
    104 AS sk_cohort_type,
    'VISIT_BOOKED_TO_OFFER_APPROVED' AS cohort_name,
    'VB2OA' AS abbreviation
UNION ALL
SELECT
    105 AS sk_cohort_type,
    'VISIT_BOOKED_TO_EVALUATION_STARTED' AS cohort_name,
    'VB2ES' AS abbreviation
UNION ALL
SELECT
    106 AS sk_cohort_type,
    'VISIT_BOOKED_TO_EVALUATION_POSITIVE' AS cohort_name,
    'VB2EP' AS abbreviation
UNION ALL
SELECT
    107 AS sk_cohort_type,
    'VISIT_BOOKED_TO_DOC_SENT' AS cohort_name,
    'VB2DS' AS abbreviation
UNION ALL
SELECT
    108 AS sk_cohort_type,
    'VISIT_BOOKED_TO_CREDIT_APPROVED' AS cohort_name,
    'VB2CA' AS abbreviation
UNION ALL
SELECT
    109 AS sk_cohort_type,
    'VISIT_BOOKED_TO_CONTRACT_SIGNED' AS cohort_name,
    'VB2CS' AS abbreviation
UNION ALL
SELECT
    203 AS sk_cohort_type,
    'VISIT_COMPLETED_TO_OFFER_SUBMITTED' AS cohort_name,
    'VC2OS' AS abbreviation
UNION ALL
SELECT
    204 AS sk_cohort_type,
    'VISIT_COMPLETED_TO_OFFER_APPROVED' AS cohort_name,
    'VB2OA' AS abbreviation
UNION ALL
SELECT
    205 AS sk_cohort_type,
    'VISIT_COMPLETED_TO_EVALUATION_STARTED' AS cohort_name,
    'VB2ES' AS abbreviation
UNION ALL
SELECT
    206 AS sk_cohort_type,
    'VISIT_COMPLETED_TO_EVALUATION_POSITIVE' AS cohort_name,
    'VB2EP' AS abbreviation
UNION ALL
SELECT
    207 AS sk_cohort_type,
    'VISIT_COMPLETED_TO_DOC_SENT' AS cohort_name,
    'VB2DS' AS abbreviation
UNION ALL
SELECT
    208 AS sk_cohort_type,
    'VISIT_COMPLETED_TO_CREDIT_APPROVED' AS cohort_name,
    'VC2CA' AS abbreviation
UNION ALL
SELECT
    209 AS sk_cohort_type,
    'VISIT_COMPLETED_TO_CONTRACT_SIGNED' AS cohort_name,
    'VC2CS' AS abbreviation
UNION ALL
SELECT
    304 AS sk_cohort_type,
    'OFFER_SUBMITTED_TO_OFFER_APPROVED' AS cohort_name,
    'OS2OA' AS abbreviation
UNION ALL
SELECT
    305 AS sk_cohort_type,
    'OFFER_SUBMITTED_TO_EVALUATION_STARTED' AS cohort_name,
    'OS2ES' AS abbreviation
UNION ALL
SELECT
    306 AS sk_cohort_type,
    'OFFER_SUBMITTED_TO_EVALUATION_POSITIVE' AS cohort_name,
    'OS2EP' AS abbreviation
UNION ALL
SELECT
    307 AS sk_cohort_type,
    'OFFER_SUBMITTED_TO_DOC_SENT' AS cohort_name,
    'OS2DS' AS abbreviation
UNION ALL
SELECT
    308 AS sk_cohort_type,
    'OFFER_SUBMITTED_TO_CREDIT_APPROVED' AS cohort_name,
    'OS2CA' AS abbreviation
UNION ALL
SELECT
    309 AS sk_cohort_type,
    'OFFER_SUBMITTED_TO_CONTRACT_SIGNED' AS cohort_name,
    'OS2CS' AS abbreviation
UNION ALL
SELECT
    405 AS sk_cohort_type,
    'OFFER_APPROVED_TO_EVALUATION_STARTED' AS cohort_name,
    'OA2ES' AS abbreviation
UNION ALL
SELECT
    406 AS sk_cohort_type,
    'OFFER_APPROVED_TO_EVALUATION_POSITIVE' AS cohort_name,
    'OA2EP' AS abbreviation
UNION ALL
SELECT
    407 AS sk_cohort_type,
    'OFFER_APPROVED_TO_DOC_SENT' AS cohort_name,
    'OA2DS' AS abbreviation
UNION ALL
SELECT
    408 AS sk_cohort_type,
    'OFFER_APPROVED_TO_CREDIT_APPROVED' AS cohort_name,
    'OA2CA' AS abbreviation
UNION ALL
SELECT
    409 AS sk_cohort_type,
    'OFFER_APPROVED_TO_CONTRACT_SIGNED' AS cohort_name,
    'OA2CS' AS abbreviation
UNION ALL
SELECT
    506 AS sk_cohort_type,
    'EVALUATION_STARTED_TO_EVALUATION_POSITIVE' AS cohort_name,
    'ES2EP' AS abbreviation
UNION ALL
SELECT
    507 AS sk_cohort_type,
    'EVALUATION_STARTED_TO_DOC_SENT' AS cohort_name,
    'ES2DS' AS abbreviation
UNION ALL
SELECT
    508 AS sk_cohort_type,
    'EVALUATION_STARTED_TO_CREDIT_APPROVED' AS cohort_name,
    'ES2CA' AS abbreviation
UNION ALL
SELECT
    509 AS sk_cohort_type,
    'EVALUATION_STARTED_TO_CONTRACT_SIGNED' AS cohort_name,
    'ES2CS' AS abbreviation
UNION ALL
SELECT
    607 AS sk_cohort_type,
    'EVALUATION_POSITIVE_TO_DOC_SENT' AS cohort_name,
    'EP2DS' AS abbreviation
UNION ALL
SELECT
    608 AS sk_cohort_type,
    'EVALUATION_POSITIVE_TO_CREDIT_APPROVED' AS cohort_name,
    'EP2CA' AS abbreviation
UNION ALL
SELECT
    609 AS sk_cohort_type,
    'EVALUATION_POSITIVE_TO_CONTRACT_SIGNED' AS cohort_name,
    'EP2CS' AS abbreviation
UNION ALL
SELECT
    708 AS sk_cohort_type,
    'DOC_SENT_TO_CREDIT_APPROVED' AS cohort_name,
    'DS2CA' AS abbreviation
UNION ALL
SELECT
    709 AS sk_cohort_type,
    'DOC_SENT_TO_CONTRACT_SIGNED' AS cohort_name,
    'DS2CS' AS abbreviation
UNION ALL
SELECT
    809 AS sk_cohort_type,
    'CREDIT_APPROVED_TO_CONTRACT_SIGNED' AS cohort_name,
    'CA2CS' AS abbreviation