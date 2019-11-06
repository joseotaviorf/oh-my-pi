WITH qa_subregions AS (
  SELECT r.id as sk_region,
         r.nome as region,
         c.nome as city,
         ST_Polygon(pr.poligono) as the_geom
  FROM datalake_raw.ebdb_poligonoregiao AS pr
  JOIN datalake_raw.ebdb_regiao AS r ON r.id = pr.regiao_id
  JOIN datalake_raw.ebdb_regiao AS m ON m.id = r.regiaopai_id
  JOIN datalake_raw.ebdb_regiao AS c ON c.id = m.regiaopai_id
  WHERE r.nivel = 'SubRegiao'
),
census_stats_250m_hex_grid AS (
  SELECT h.*,
         ST_Polygon(h.geometry) AS the_geom
  FROM datalake_raw.census_stats_250m_hex_grid AS h
),
hex_join_region AS (
  SELECT h.*,
         r.sk_region
  FROM census_stats_250m_hex_grid AS h
  JOIN qa_subregions AS r ON ST_Within(ST_Centroid(h.the_geom), r.the_geom)
  WHERE CAST(h.households_ct AS REAL) > 0
),
region_census_stats AS (
  SELECT hr.sk_region AS sk_region,
         SUM(CAST(hr.households_ct AS REAL)) AS households,
         SUM(CAST(hr.rented_sum AS REAL)) AS rented_households,
         SUM(CAST(hr.apts_sum AS REAL)) AS apartment_households,
         SUM(CAST(hr.rented_apts_sum AS REAL)) AS rented_apartment_households,
         SUM(CAST(hr.inc_bt_2_3_mw_sum AS REAL)) AS income_between_2_and_3_minimum_wages_households,
         SUM(CAST(hr.inc_bt_3_5_mw_sum AS REAL)) AS income_between_3_and_5_minimum_wages_households,
         SUM(CAST(hr.inc_gt_5_mw_sum AS REAL)) AS income_greater_than_5_minimum_wages_households,
         ROUND(SUM(CAST(hr.inc_gt_5_mw_sum AS REAL) * (CAST(hr.rented_sum AS REAL) / CAST(hr.households_ct AS REAL)))) AS income_greater_than_5_minimum_wages_rented_households,
         ROUND(SUM(CAST(hr.inc_gt_5_mw_sum AS REAL) * (CAST(hr.rented_sum AS REAL) / CAST(hr.households_ct AS REAL)) * (CAST(hr.apts_sum AS REAL) / CAST(hr.households_ct AS REAL)))) AS income_greater_than_5_minimum_wages_rented_apartment_households
  FROM hex_join_region AS hr
  GROUP BY 1
)
SELECT * FROM region_census_stats
