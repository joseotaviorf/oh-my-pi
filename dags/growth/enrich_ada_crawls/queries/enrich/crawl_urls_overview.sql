WITH 
issues_aggregated AS (
  SELECT 
    address, 
    ARRAY_AGG(issue_name) AS aggregated_issues,
    device,
    dt_report
  FROM
    datalake_ada_crawls_clean.issues
  WHERE
    dt_report BETWEEN '{load_start_date}' AND '{load_end_date}'
  GROUP BY
    address, device, dt_report
),
issues AS (
  SELECT 
    address,
    issue_name,
    device,
    dt_report
  FROM
    datalake_ada_crawls_clean.issues
  WHERE
    dt_report BETWEEN '{load_start_date}' AND '{load_end_date}'
),
internal_all AS (
  SELECT 
    *,
    CASE
      WHEN address LIKE '%www.quintoandar.com.br/' OR address LIKE '%www.quintoandar.com.br' THEN 'HOME'
      WHEN CONTAINS(address, 'br/alugar/imovel') THEN 'SEARCH RENT'
      WHEN CONTAINS(address, 'br/comprar/imovel') THEN 'SEARCH SALE'
      WHEN CONTAINS(address,'br/imovel/') THEN 'LISTING'
      WHEN CONTAINS(address, 'br/classificados/') THEN 'LISTING CLASSIFIEDS'
      WHEN CONTAINS(address, 'br/condominio/') THEN 'CONDO'
      WHEN CONTAINS(address, 'br/condominios') THEN 'CONDO REGION'
      WHEN CONTAINS(address, 'br/regioes-atendidas') THEN 'REGIONS'
      WHEN CONTAINS(address, 'br/guias') THEN 'GUIAS'
      WHEN CONTAINS(address, 'proprietarios.quintoandar') THEN 'PROPRIETÁRIOS'
      WHEN CONTAINS(address, 'mkt.quintoandar') THEN 'MARKETING'
      WHEN CONTAINS(address, 'newsroom.quintoandar') THEN 'NEWSROOM'
      WHEN CONTAINS(address, 'br/ajuda') THEN 'AJUDA'
      ELSE 'OTHER'
    END AS structure
  FROM
    datalake_ada_crawls_clean.internal_all
  WHERE
    dt_report BETWEEN '{load_start_date}' AND '{load_end_date}'
)
SELECT 
  ia.address, 
  is.issue_name,
  is_agg.aggregated_issues,
  ia.structure,
  ia.content_type,
  ia.status_code,
  ia.status,
  ia.indexability,
  ia.indexability_status,
  ia.title_content,
  ia.meta_description_content,
  ia.meta_keywords_content,
  ia.h1_content,
  ia.secondary_h1_content, 
  ia.h2_content,
  ia.secondary_h2_content,
  ia.meta_robots_content,
  ia.x_robots_tag_content,
  ia.meta_refresh_content,
  ia.canonical_link_element,
  ia.redirect_url,
  ia.redirect_type,
  ia.language,
  ia.http_version,
  ia.supply,
  ia.url_encoded_address,
  ia.title_pixel_width,
  ia.meta_description_pixel_width,
  ia.size_in_bytes,
  ia.transferred_bytes,
  ia.total_transferred_bytes,
  ia.carbon_emissions,
  ia.word_count,
  ia.sentence_count,
  ia.average_words_per_sentence,
  ia.flesch_reading_ease_score,
  ia.readability,
  ia.text_ratio,
  ia.crawl_depth,
  ia.folder_depth,
  ia.inlink_count,
  ia.unique_inlink_count,
  ia.percentage_of_total,
  ia.outlink_count,
  ia.unique_outlink_count,
  ia.response_time,
  ia.ts_last_modified,
  ia.ts_crawl,
  ia.dt_report,
  ia.device,
  ia.year,
  ia.month,
  ia.day
FROM
  internal_all AS ia
LEFT JOIN 
  issues AS is
    ON ia.address = is.address AND ia.device = is.device AND ia.dt_report = is.dt_report
LEFT JOIN
  issues_aggregated AS is_agg
    ON ia.address = is_agg.address AND ia.device = is_agg.device AND ia.dt_report = is_agg.dt_report