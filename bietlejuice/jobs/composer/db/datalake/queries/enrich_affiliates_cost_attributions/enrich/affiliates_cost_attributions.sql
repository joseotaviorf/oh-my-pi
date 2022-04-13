WITH affiliates_engagement_cost AS (
	SELECT
		aec.year,
		aec.month,
		aec.day,
		DATE(aec.ts_commission_cost) AS dt_commission_cost,
		rg.city_group,
		CASE
			WHEN aec.affiliate_type = 'Standard'
				THEN 'Indica Aí - General'
			WHEN aec.affiliate_type = 'Agent'
				THEN 'Indica Aí - Agents'
			WHEN aec.affiliate_type = 'Doorman'
				THEN 'Doorman'
			ELSE 'Not Mapped'
		END AS mkt_origin,
		SUM(IF(aec.commission_type = 'valorFixoPorIndicacaoDeImovel', aec.commission_cost, 0)) AS commission_listing_cost,
		SUM(IF(aec.commission_type = 'porcentagemPorIndicacaoDeImovel', aec.commission_cost, 0)) AS commission_rent_cost,
		SUM(IF(aec.commission_type IN ('comissaoSobreAfiliadoIndicado', 'comissaoUnicaSobreAfiliadoIndicado'), aec.commission_cost, 0)) AS commission_mgm_cost
	FROM
		datalake_ebdb_affiliates_cost.affiliates_engagement_cost aec
	LEFT JOIN
		datalake_region.region rg
		ON aec.id_region = rg.id
	GROUP BY
		1,2,3,4,5,6
)
------- STATIC HISTORY COST -------
SELECT
	amch.dt_cost AS id_date,
    COALESCE(amch.city_group, 'Not Mapped') AS city_group,
    COALESCE(amch.mkt_origin, 'Not Mapped') AS mkt_origin,
	SUM(amch.commission_listing_cost) AS commission_listing_cost,
	SUM(amch.commission_rent_cost) AS commission_rent_cost,
	SUM(amch.commission_mgm_cost) AS commission_mgm_cost,
	SUM(amch.promotional_bonus_cost) AS promotional_bonus_cost,
	SUM(amch.notification_cost) AS notification_cost,
	SUM(amch.other_cost) AS other_cost,
	SUM(amch.commission_listing_cost * COALESCE(tcm.commission_rate, 0)
		+ amch.commission_rent_cost * COALESCE(tcm.commission_rate, 0)
		+ amch.commission_mgm_cost * COALESCE(tcm.commission_rate, 0)
		+ amch.promotional_bonus_cost * COALESCE(tcm.commission_rate, 0)) AS commission_tradecom
FROM
    datalake_gsheets_clean.affiliates_manual_cost_engagement_history amch
LEFT JOIN
    datalake_gsheets_clean.affiliates_cost_tradecom_configuration tcm
	    ON amch.dt_cost BETWEEN dt_from AND dt_until
GROUP BY
    1,2,3
UNION
------- DYNAMIC DAILY COST -------
SELECT
	COALESCE(aec.dt_commission_cost, amce.dt_cost) AS id_date,
	COALESCE(aec.city_group, amce.city_group, 'Not Mapped') AS city_group,
	COALESCE(aec.mkt_origin, amce.mkt_origin, 'Not Mapped') AS mkt_origin,
	SUM(COALESCE(aec.commission_listing_cost, 0)) AS commission_listing_cost,
	SUM(COALESCE(aec.commission_rent_cost, 0)) AS commission_rent_cost,
	SUM(COALESCE(aec.commission_mgm_cost, 0)) AS commission_mgm_cost,
	SUM(COALESCE(amce.promotional_bonus_cost, 0)) AS promotional_bonus_cost,
	SUM(COALESCE(amce.notification_cost, 0)) AS notification_cost,
	SUM(COALESCE(amce.other_cost, 0)) AS other_cost,
	SUM(COALESCE(aec.commission_listing_cost, 0) * COALESCE(tcm.commission_rate, 0)
	  + COALESCE(aec.commission_rent_cost, 0) * COALESCE(tcm.commission_rate, 0)
	  + COALESCE(aec.commission_mgm_cost, 0) * COALESCE(tcm.commission_rate, 0)
	  + COALESCE(amce.promotional_bonus_cost, 0) * COALESCE(tcm.commission_rate, 0)) AS commission_tradecom
FROM
	affiliates_engagement_cost aec
FULL OUTER JOIN
	datalake_gsheets_clean.affiliates_manual_cost_engagement amce
        ON aec.mkt_origin = amce.mkt_origin
        AND aec.city_group = amce.city_group
        AND aec.year = YEAR(amce.dt_cost)
        AND aec.month = MONTH(amce.dt_cost)
        AND aec.day = DAY(amce.dt_cost)
LEFT JOIN
    datalake_gsheets_clean.affiliates_cost_tradecom_configuration tcm
	    ON COALESCE(aec.dt_commission_cost, amce.dt_cost) BETWEEN dt_from AND dt_until
GROUP BY
	1,2,3
