/*This query projects the updated number of rented apartments in 2019 and estimates the share of 5A ongoing listings, ongoing contracts and total 5A presence in each sk_region.*/
/*Selects all CNPJ apartments and joins them to get 5A subregions and cities*/
WITH cnpj_condos AS (
SELECT
  substr(c.dt_inicio_atividade, 1, 4) as ano_inicio_atividade,
  ST_Point(CAST(a.lng AS DOUBLE),CAST(a.lat AS DOUBLE)) AS the_geom
FROM datalake_raw.cnpj_br_condos c
  INNER JOIN datalake_raw.cnpj_br_condos_geocoded_addresses a ON c.hash = a.hash
  WHERE
    NULLIF(a.lat, '') IS NOT NULL
    AND COALESCE(dt_inicio_atividade, '') != ''
    and comercial <> 'True'
)
/*5A subregions*/
,qa_subregions AS (
SELECT
  r.name
  ,r.sk_region
  ,r.city_name
  ,ST_Polygon(p.polygon) AS the_geom
FROM datalake_clean.ods_dim_region r
LEFT JOIN datalake_ebdb_clean_prod.polygon_region p ON cast(r.sk_region as bigint) = p.id_region
WHERE level = 'SubRegiao'
)
/*Census 2010 data grouped in 250m hexagons*/
,census_stats_250m_hex_grid AS (
  SELECT h.*,
         ST_Polygon(h.geometry) AS the_geom
  FROM datalake_raw.census_stats_250m_hex_grid AS h
)
/*hex_join_region and regions_census_stats aggregate the number of rented apartment households in each hexagon based on the subregion its centroid is in*/
,hex_join_region AS (
  SELECT h.*,
         r.sk_region
  FROM census_stats_250m_hex_grid AS h
  JOIN qa_subregions AS r ON ST_Within(ST_Centroid(h.the_geom), r.the_geom)
  WHERE CAST(h.households_ct AS REAL) > 0
)
,regions_census_stats as (
SELECT hr.sk_region AS sk_region,
         SUM(CAST(hr.rented_apts_sum AS REAL)) AS rented_apartment_households
  FROM hex_join_region AS hr
  GROUP BY 1
)
/*current number of 5A ongoing listings of apartment type houses*/
,ongoing_listings as(
SELECT
         r.sk_region as sk_region,
         r.name AS subregion,
         r.city_name as city_name,
        COUNT(distinct dhl.id_house) AS n_ongoing_listings
FROM datalake_clean.ods_dim_house_listing AS dhl
JOIN datalake_clean.ods_fact_house_listings f ON dhl.sk_house_listing = f.sk_house_listing
JOIN qa_subregions r ON r.sk_region = CAST(f.sk_region AS BIGINT)
LEFT JOIN datalake_ebdb_clean_prod.polygon_region p ON cast(r.sk_region as bigint) = p.id_region
WHERE house_status = 'publicado'
AND substring(cast(dhl.sk_house_listing as varchar),10,12) <> '000' AND r.sk_region is not null AND (dhl.house_type='Apartamento' OR dhl.house_type='StudioOuKitchenette') AND dhl.is_for_rent=True
GROUP BY 1,2,3
)
/*current number of 5A ongoing contracts of apartment type houses*/
,ongoing_contracts AS (
  SELECT
        r.sk_region as sk_region
        , r.name AS subregion
        , r.city_name as city_name
        , COUNT(distinct dhl.id_house) AS n_ongoing_contracts
  FROM datalake_clean.ods_dim_house_listing AS dhl
  JOIN datalake_clean.ods_fact_house_listings f ON dhl.sk_house_listing = f.sk_house_listing
  JOIN qa_subregions r ON r.sk_region = CAST(f.sk_region AS BIGINT)
  WHERE house_status = 'alugado' AND (dhl.house_type='Apartamento' OR dhl.house_type='StudioOuKitchenette') AND dhl.is_for_rent=True
  AND r.sk_region is not NULL
  GROUP BY 1,2,3
)
,cnpj_condos_by_sk_region as (
/*counts the number of CNPJ condos in 2010 and in 2017 per sk_region, and then gets the percentage of condos growth between 2010 and 2017*/
select
	r.sk_region
    ,r.name
    ,r.city_name
	,SUM(CASE WHEN CAST(c.ano_inicio_atividade AS INTEGER) <= 2010 THEN 1 ELSE 0 end) AS CNPJ_condos_in_2010
	,SUM(CASE WHEN CAST(c.ano_inicio_atividade AS INTEGER) <= 2017 THEN 1 ELSE 0 end) AS CNPJ_condos_in_2017
	,CASE
		WHEN
		SUM(CASE WHEN cast(c.ano_inicio_atividade as INTEGER) <= 2010 THEN 1 ELSE 0 END) = 0
		THEN SUM(CASE WHEN CAST(c.ano_inicio_atividade AS INTEGER) <= 2017 THEN 1 ELSE 0 end)/1
		ELSE
		SUM(CASE WHEN CAST(c.ano_inicio_atividade AS INTEGER) <= 2017 THEN 1 ELSE 0 end)/CAST(SUM(CASE when CAST(c.ano_inicio_atividade as INTEGER) <= 2010 THEN 1 ELSE 0 END) AS REAL) end AS pct_condos_growth_2010_2017
FROM qa_subregions AS r
left JOIN cnpj_condos AS c
ON ST_Contains(r.the_geom, c.the_geom)
group by 1,2,3
)
/*To get the updated rented apartments in 2019, this query selects the number of rented apartments in 2010, according to Census 2010 data and updates it based on: (1) the percent of condos growth between 2010 and 2017 according to CNPJ data,
 * and (2) the percent of growth between 2018 and 2019, based on the apartments growth in this period according to SECOVI/Embraesp data*/
,updated_rented_apartment_households as (
select
		r.sk_region
		,CASE
  	    	WHEN cs.rented_apartment_households = 0
    	  	THEN cast(1 * cc.pct_condos_growth_2010_2017 * 1.084 as integer)
     	 ELSE
    	  cast(cs.rented_apartment_households * cc.pct_condos_growth_2010_2017 * 1.084 as integer) END as updated_rented_apartment_households
FROM qa_subregions AS r
left join regions_census_stats as cs
on r.sk_region = cs.sk_region
left join cnpj_condos_by_sk_region cc
on r.sk_region = cc.sk_region
)
SELECT cast(r.sk_region as INTEGER) as sk_region
	  	,r.name
	  	,r.city_name
		,up.updated_rented_apartment_households as updated_rented_apartment_households
		,coalesce(ol.n_ongoing_listings,0) as ongoing_listings
		,coalesce(oc.n_ongoing_contracts,0) as ongoing_contracts
		,coalesce((coalesce(ol.n_ongoing_listings,0) + coalesce(oc.n_ongoing_contracts,0)),0) as total_5A_presence
		,ROUND(coalesce((ol.n_ongoing_listings/nullif(cast(up.updated_rented_apartment_households as real),0)),0)*100,2) as ol_share
		,ROUND(coalesce((oc.n_ongoing_contracts/nullif(cast(up.updated_rented_apartment_households as real),0)),0)*100,2) as oc_share
		,ROUND(COALESCE((coalesce((coalesce(ol.n_ongoing_listings,0) + coalesce(oc.n_ongoing_contracts,0)),0)/nullif(cast(up.updated_rented_apartment_households as real),0)),0)*100,2) as total_5A_share
FROM qa_subregions AS r
left join updated_rented_apartment_households as up
ON r.sk_region=up.sk_region
LEFT JOIN ongoing_listings as ol
ON r.sk_region=ol.sk_region
LEFT JOIN ongoing_contracts as oc
ON r.sk_region=oc.sk_region
