WITH
rent_flows AS (
-- adpating rent_flows output
	SELECT
	    rf.sk_client,
	    rf.sk_booking_created_date,
	    rf.sk_visit_date,
	    db.ts_scheduling_local,
	    db.ts_created_local,
	    rf.sk_offer_submitted_date,
	    rf.sk_offer_approved_date,
	    rf.sk_first_credit_evaluation_init AS sk_credit_evaluation_init,
	    rf.sk_last_credit_evaluation_positive,
	    rf.sk_tenant_first_doc_sent_date,
	    rf.sk_last_doc_analysis_approved,
	    rf.sk_contract_signed_date,
	    rf.flg_visit_completed,
	    fdf.funnel_first_touchpoint,
	    min(CASE WHEN flg_visit_completed = 1 THEN rf.sk_visit_date END) OVER(PARTITION BY rf.sk_client, date_trunc('week',date(NULLIF(rf.sk_booking_created_date,-1))), funnel_first_touchpoint) AS sk_first_visit_date,
	    min(rf.sk_offer_submitted_date) OVER(PARTITION BY rf.sk_client, date_trunc('week',date(NULLIF(rf.sk_visit_date,-1))), funnel_first_touchpoint) AS sk_first_offer_submitted_date,
	    min(rf.sk_offer_approved_date) OVER(PARTITION BY rf.sk_client, date_trunc('week',date(NULLIF(rf.sk_offer_submitted_date,-1))), funnel_first_touchpoint) AS sk_first_offer_approved_date,
	    min(rf.sk_first_credit_evaluation_init) OVER(PARTITION BY rf.sk_client, date_trunc('week',date(NULLIF(rf.sk_offer_approved_date,-1))), funnel_first_touchpoint) AS sk_first_credit_evaluation_init,
	    min(rf.sk_last_credit_evaluation_positive) OVER(PARTITION BY rf.sk_client, date_trunc('week',date(NULLIF(rf.sk_first_credit_evaluation_init,-1))), funnel_first_touchpoint) AS sk_first_credit_evaluation_positive,
	    min(rf.sk_tenant_first_doc_sent_date) OVER(PARTITION BY rf.sk_client, date_trunc('week',date(NULLIF(rf.sk_last_credit_evaluation_positive,-1))), funnel_first_touchpoint) AS sk_first_doc_sent_date,
	    min(rf.sk_last_doc_analysis_approved) OVER(PARTITION BY rf.sk_client, date_trunc('week',date(NULLIF(rf.sk_tenant_first_doc_sent_date,-1))), funnel_first_touchpoint) AS sk_first_doc_approved_date,
	    min(rf.sk_contract_signed_date) OVER(PARTITION BY rf.sk_client, date_trunc('week',date(NULLIF(rf.sk_last_doc_analysis_approved,-1))), funnel_first_touchpoint) AS sk_first_contract_signed_date
	FROM fact_listing_rent_flows rf
	LEFT JOIN datamarts.funnel_demand_flows fdf
	  on rf.sk_rent_flow = fdf.sk_rent_floW
	LEFT JOIN dim_booking db
	  ON db.sk_booking = rf.sk_booking
),
vb2vc AS (
	SELECT
		date_trunc('week',date(sk_booking_created_date)) AS "week",
		funnel_first_touchpoint,
		CASE WHEN datediff('week',date_trunc('week',date(sk_booking_created_date)),DATE_TRUNC('week',date(NULLIF(sk_first_visit_date,-1)))) <= 0
				THEN 'W0'
			 WHEN (datediff('week',date_trunc('week',date(sk_booking_created_date)),DATE_TRUNC('week',date(NULLIF(sk_first_visit_date,-1)))) > 0
			 		AND datediff('week',date_trunc('week',date(sk_booking_created_date)),DATE_TRUNC('week',date(NULLIF(sk_first_visit_date,-1)))) < 5)
				THEN 'W'||datediff('week',date_trunc('week',date(sk_booking_created_date)),DATE_TRUNC('week',date(NULLIF(sk_first_visit_date,-1))))
	     	 WHEN datediff('week',date_trunc('week',date(sk_booking_created_date)),DATE_TRUNC('week',date(NULLIF(sk_first_visit_date,-1)))) >= 5
	     	 	THEN 'W5+'
	    END AS weeks_conversion,
		COUNT(DISTINCT sk_client) AS users_w_visit_completed,
		NULL::BIGINT AS users_w_offer_submitted,
		NULL::BIGINT AS users_w_offer_approved,
		NULL::BIGINT AS users_w_credit_evaluation_init,
		NULL::BIGINT AS users_w_credit_evaluation_positive,
		NULL::BIGINT AS users_w_doc_sent,
		NULL::BIGINT AS users_w_doc_approved,
		NULL::BIGINT AS users_w_contract_signed
	FROM rent_flows
	WHERE sk_booking_created_date > 0 AND (ts_scheduling_local > ts_created_local OR ts_scheduling_local IS null)
	GROUP BY 1, 2, 3
),
vc2os AS (
	SELECT
		DATE_TRUNC('week',date(sk_visit_date)) AS "week",
		funnel_first_touchpoint,
		CASE WHEN datediff('week',DATE_TRUNC('week',date(sk_visit_date)),DATE_TRUNC('week',date(NULLIF(sk_offer_submitted_date,-1)))) <= 0
				THEN 'W0'
			 WHEN (datediff('week',DATE_TRUNC('week',date(sk_visit_date)),DATE_TRUNC('week',date(NULLIF(sk_offer_submitted_date,-1)))) > 0
			 	  AND datediff('week',DATE_TRUNC('week',date(sk_visit_date)),DATE_TRUNC('week',date(NULLIF(sk_offer_submitted_date,-1)))) < 5)
				THEN 'W'||datediff('week',DATE_TRUNC('week',date(sk_visit_date)),DATE_TRUNC('week',date(NULLIF(sk_offer_submitted_date,-1))))
	     	 WHEN datediff('week',DATE_TRUNC('week',date(sk_visit_date)),DATE_TRUNC('week',date(NULLIF(sk_offer_submitted_date,-1)))) >= 5
	     	 	THEN 'W5+'
	    END AS weeks_conversion,
		NULL::BIGINT AS users_w_visit_completed,
		COUNT(DISTINCT sk_client) AS users_w_offer_submitted,
		NULL::BIGINT AS users_w_offer_approved,
		NULL::BIGINT AS users_w_credit_evaluation_init,
		NULL::BIGINT AS users_w_credit_evaluation_positive,
		NULL::BIGINT AS users_w_doc_sent,
		NULL::BIGINT AS users_w_doc_approved,
		NULL::BIGINT AS users_w_contract_signed
	FROM rent_flows
	WHERE sk_visit_date > 0 AND flg_visit_completed = 1 AND (sk_offer_submitted_date >= sk_visit_date OR sk_offer_submitted_date = -1)
	GROUP BY 1, 2, 3
),
os2oa AS (
	SELECT
		DATE_TRUNC('week',date(sk_offer_submitted_date)) AS "week",
		funnel_first_touchpoint,
		CASE WHEN datediff('week',DATE_TRUNC('week',date(sk_offer_submitted_date)),DATE_TRUNC('week',date(NULLIF(sk_offer_approved_date,-1)))) <= 0
				THEN 'W0'
			 WHEN (datediff('week',DATE_TRUNC('week',date(sk_offer_submitted_date)),DATE_TRUNC('week',date(NULLIF(sk_offer_approved_date,-1)))) > 0
			 		AND datediff('week',DATE_TRUNC('week',date(sk_offer_submitted_date)),DATE_TRUNC('week',date(NULLIF(sk_offer_approved_date,-1)))) < 5)
				THEN 'W'||datediff('week',DATE_TRUNC('week',date(sk_offer_submitted_date)),DATE_TRUNC('week',date(NULLIF(sk_offer_approved_date,-1))))
	     	 WHEN datediff('week',DATE_TRUNC('week',date(sk_offer_submitted_date)),DATE_TRUNC('week',date(NULLIF(sk_offer_approved_date,-1)))) >= 5
	     	 	THEN 'W5+'
	    END AS weeks_conversion,
		NULL::BIGINT AS users_w_visit_completed,
		NULL::BIGINT AS users_w_offer_submitted,
		COUNT(DISTINCT sk_client) AS users_w_offer_approved,
		NULL::BIGINT AS users_w_credit_evaluation_init,
		NULL::BIGINT AS users_w_credit_evaluation_positive,
		NULL::BIGINT AS users_w_doc_sent,
		NULL::BIGINT AS users_w_doc_approved,
		NULL::BIGINT AS users_w_contract_signed
	FROM rent_flows
	WHERE sk_offer_submitted_date > 0 AND (sk_offer_approved_date >= sk_offer_submitted_date OR sk_offer_approved_date = -1)
	GROUP BY 1, 2, 3
),
oa2ces AS (
	SELECT
		DATE_TRUNC('week',date(sk_offer_approved_date)) AS "week",
		funnel_first_touchpoint,
		CASE WHEN datediff('week',date(sk_offer_approved_date),DATE_TRUNC('week',date(NULLIF(sk_first_credit_evaluation_init,-1)))) <= 0
				THEN 'W0'
			 WHEN (datediff('week',date(sk_offer_approved_date),DATE_TRUNC('week',date(NULLIF(sk_first_credit_evaluation_init,-1)))) > 0
			 		AND datediff('week',date(sk_offer_approved_date),DATE_TRUNC('week',date(NULLIF(sk_first_credit_evaluation_init,-1)))) < 5)
				THEN 'W'||datediff('week',date(sk_offer_approved_date),DATE_TRUNC('week',date(NULLIF(sk_first_credit_evaluation_init,-1))))
	     	 WHEN datediff('week',date(sk_offer_approved_date),DATE_TRUNC('week',date(NULLIF(sk_first_credit_evaluation_init,-1)))) >= 5
	     	 	THEN 'W5+'
	    END AS weeks_conversion,
		NULL::BIGINT AS users_w_visit_completed,
		NULL::BIGINT AS users_w_offer_submitted,
		NULL::BIGINT AS users_w_offer_approved,
		COUNT(DISTINCT sk_client) AS users_w_credit_evaluation_init,
		NULL::BIGINT AS users_w_credit_evaluation_positive,
		NULL::BIGINT AS users_w_doc_sent,
		NULL::BIGINT AS users_w_doc_approved,
		NULL::BIGINT AS users_w_contract_signed
	FROM rent_flows
	WHERE sk_offer_approved_date > 0 AND (sk_first_credit_evaluation_init >= sk_offer_approved_date OR sk_first_credit_evaluation_init = -1)
	GROUP BY 1, 2, 3
),
ces2cep AS (
	SELECT
		DATE_TRUNC('week',date(sk_first_credit_evaluation_init)) AS "week",
		funnel_first_touchpoint,
		CASE WHEN datediff('week',date(sk_first_credit_evaluation_init),DATE_TRUNC('week',date(NULLIF(sk_first_credit_evaluation_positive,-1)))) <= 0
				THEN 'W0'
			 WHEN (datediff('week',date(sk_first_credit_evaluation_init),DATE_TRUNC('week',date(NULLIF(sk_first_credit_evaluation_positive,-1)))) > 0
			 		AND datediff('week',date(sk_first_credit_evaluation_init),DATE_TRUNC('week',date(NULLIF(sk_first_credit_evaluation_positive,-1)))) < 5)
				THEN 'W'||datediff('week',date(sk_first_credit_evaluation_init),DATE_TRUNC('week',date(NULLIF(sk_first_credit_evaluation_positive,-1))))
	     	 WHEN datediff('week',date(sk_first_credit_evaluation_init),DATE_TRUNC('week',date(NULLIF(sk_first_credit_evaluation_positive,-1)))) >= 5
	     	 	THEN 'W5+'
	    END AS weeks_conversion,
		NULL::BIGINT AS users_w_visit_completed,
		NULL::BIGINT AS users_w_offer_submitted,
		NULL::BIGINT AS users_w_offer_approved,
		NULL::BIGINT AS users_w_credit_evaluation_init,
		COUNT(DISTINCT sk_client) AS users_w_credit_evaluation_positive,
		NULL::BIGINT AS users_w_doc_sent,
		NULL::BIGINT AS users_w_doc_approved,
		NULL::BIGINT AS users_w_contract_signed
	FROM rent_flows
	WHERE sk_first_credit_evaluation_init > 0 AND (sk_first_credit_evaluation_positive >= sk_first_credit_evaluation_init OR sk_first_credit_evaluation_positive = -1)
	GROUP BY 1, 2, 3
),
cep2ds AS (
	SELECT
		DATE_TRUNC('week',date(sk_first_credit_evaluation_positive)) AS "week",
		funnel_first_touchpoint,
		CASE WHEN datediff('week',date(sk_first_credit_evaluation_positive),DATE_TRUNC('week',date(NULLIF(sk_first_doc_sent_date,-1)))) <= 0
				THEN 'W0'
			 WHEN (datediff('week',date(sk_first_credit_evaluation_positive),DATE_TRUNC('week',date(NULLIF(sk_first_doc_sent_date,-1)))) > 0
			 		AND datediff('week',date(sk_first_credit_evaluation_positive),DATE_TRUNC('week',date(NULLIF(sk_first_doc_sent_date,-1)))) < 5)
				THEN 'W'||datediff('week',date(sk_first_credit_evaluation_positive),DATE_TRUNC('week',date(NULLIF(sk_first_doc_sent_date,-1))))
	     	 WHEN datediff('week',date(sk_first_credit_evaluation_positive),DATE_TRUNC('week',date(NULLIF(sk_first_doc_sent_date,-1)))) >= 5
	     	 	THEN 'W5+'
	    END AS weeks_conversion,
		NULL::BIGINT AS users_w_visit_completed,
		NULL::BIGINT AS users_w_offer_submitted,
		NULL::BIGINT AS users_w_offer_approved,
		NULL::BIGINT AS users_w_credit_evaluation_init,
		NULL::BIGINT AS users_w_credit_evaluation_positive,
		COUNT(DISTINCT sk_client) AS users_w_doc_sent,
		NULL::BIGINT AS users_w_doc_approved,
		NULL::BIGINT AS users_w_contract_signed
	FROM rent_flows
	WHERE sk_first_credit_evaluation_positive > 0 AND (sk_first_doc_sent_date >= sk_first_credit_evaluation_positive OR sk_first_doc_sent_date = -1)
	GROUP BY 1, 2, 3
),
ds2da AS (
	SELECT
		DATE_TRUNC('week',date(sk_first_doc_sent_date)) AS "week",
		funnel_first_touchpoint,
		CASE WHEN datediff('week',date(sk_first_doc_sent_date),DATE_TRUNC('week',date(NULLIF(sk_first_doc_approved_date,-1)))) <= 0
				THEN 'W0'
			 WHEN (datediff('week',date(sk_first_doc_sent_date),DATE_TRUNC('week',date(NULLIF(sk_first_doc_approved_date,-1)))) > 0
			 		AND datediff('week',date(sk_first_doc_sent_date),DATE_TRUNC('week',date(NULLIF(sk_first_doc_approved_date,-1)))) < 5)
				THEN 'W'||datediff('week',date(sk_first_doc_sent_date),DATE_TRUNC('week',date(NULLIF(sk_first_doc_approved_date,-1))))
	     	 WHEN datediff('week',date(sk_first_doc_sent_date),DATE_TRUNC('week',date(NULLIF(sk_first_doc_approved_date,-1)))) >= 5
	     	 		THEN 'W5+'
	    END AS weeks_conversion,
		NULL::BIGINT AS users_w_visit_completed,
		NULL::BIGINT AS users_w_offer_submitted,
		NULL::BIGINT AS users_w_offer_approved,
		NULL::BIGINT AS users_w_credit_evaluation_init,
		NULL::BIGINT AS users_w_credit_evaluation_positive,
		NULL::BIGINT AS users_w_doc_sent,
		COUNT(DISTINCT sk_client) AS users_w_doc_approved,
		NULL::BIGINT AS users_w_contract_signed
	FROM rent_flows
	WHERE sk_first_doc_sent_date > 0 AND (sk_first_doc_approved_date >= sk_first_doc_sent_date OR sk_first_doc_approved_date = -1)
	GROUP BY 1, 2, 3
),
da2cs AS (
	SELECT
		DATE_TRUNC('week',date(sk_first_doc_approved_date)) AS "week",
		funnel_first_touchpoint,
		CASE WHEN datediff('week',date(sk_first_doc_approved_date),DATE_TRUNC('week',date(NULLIF(sk_first_contract_signed_date,-1)))) <= 0
				THEN 'W0'
			 WHEN (datediff('week',date(sk_first_doc_approved_date),DATE_TRUNC('week',date(NULLIF(sk_first_contract_signed_date,-1)))) > 0
			 		AND datediff('week',date(sk_first_doc_approved_date),DATE_TRUNC('week',date(NULLIF(sk_first_contract_signed_date,-1)))) < 5)
				THEN 'W'||datediff('week',date(sk_first_doc_approved_date),DATE_TRUNC('week',date(NULLIF(sk_first_contract_signed_date,-1))))
	     	 WHEN datediff('week',date(sk_first_doc_approved_date),DATE_TRUNC('week',date(NULLIF(sk_first_contract_signed_date,-1)))) >= 5
	     	 	THEN 'W5+'
	    END AS weeks_conversion,
		NULL::BIGINT AS users_w_visit_completed,
		NULL::BIGINT AS users_w_offer_submitted,
		NULL::BIGINT AS users_w_offer_approved,
		NULL::BIGINT AS users_w_credit_evaluation_init,
		NULL::BIGINT AS users_w_credit_evaluation_positive,
		NULL::BIGINT AS users_w_doc_sent,
		NULL::BIGINT AS users_w_doc_approved,
		COUNT(DISTINCT sk_client) AS users_w_contract_signed
	FROM rent_flows
	WHERE sk_first_doc_approved_date > 0 AND (sk_first_contract_signed_date >= sk_first_doc_approved_date OR sk_first_contract_signed_date = -1)
	GROUP BY 1, 2, 3
),
union_all AS (
	SELECT * FROM vb2vc
	UNION ALL
	SELECT * FROM vc2os
	UNION ALL
	SELECT * FROM os2oa
	UNION ALL
	SELECT * FROM oa2ces
	UNION ALL
	SELECT * FROM ces2cep
	UNION ALL
	SELECT * FROM cep2ds
	UNION ALL
	SELECT * FROM ds2da
	UNION ALL
	SELECT * FROM da2cs
),
union_all_date AS (
SELECT
	dd.week_start,
	date(date_trunc('month',dd.date)) AS month,
	dd.quarter,
	funnel_first_touchpoint,
	ua.weeks_conversion,
	ua.users_w_visit_completed,
	ua.users_w_offer_submitted,
	ua.users_w_offer_approved,
	ua.users_w_credit_evaluation_init,
	ua.users_w_credit_evaluation_positive,
	ua.users_w_doc_sent,
	ua.users_w_doc_approved,
	ua.users_w_contract_signed
FROM dim_date dd
RIGHT JOIN union_all ua
  ON ua.week = dd.week_start
WHERE dd."date" between DATE_TRUNC('year',CURRENT_DATE) - INTERVAL '4 year' AND CURRENT_DATE AND dd.weekday_name = 'Sunday'
)
SELECT
	week_start,
	month,
	quarter,
	funnel_first_touchpoint,
	weeks_conversion,
	sum(users_w_visit_completed) AS users_w_visit_completed,
	sum(users_w_offer_submitted) AS users_w_offer_submitted,
	sum(users_w_offer_approved) AS users_w_offer_approved,
	sum(users_w_credit_evaluation_init) AS users_w_credit_evaluation_init,
	sum(users_w_credit_evaluation_positive) AS users_w_credit_evaluation_positive,
	sum(users_w_doc_sent) AS users_w_doc_sent,
	sum(users_w_doc_approved) AS users_w_doc_approved,
	sum(users_w_contract_signed) AS users_w_contract_signed
FROM union_all_date
WHERE week_start >= '2020-01-01'
GROUP BY 1, 2, 3, 4, 5