# SEMRush

## Purpose

SEMRush DAG retrieves data about QuintoAndar and competitors search for classified unit.


## References
Extracted reports:

- [report_domain_organic_search_keywords](https://developer.semrush.com/api/v3/analytics/domain-reports/#domain-organic-search-keywords/): This report lists keywords that bring users to a domain via Google's top 100 organic search results.


​<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

## Execution Interval

Daily (retrieves D-1 data). More information about run time [here]({chart_url}{dag_id}).

## Outputs

This pipeline produces the following output tables in each layer:

raw:
- `datalake_semrush_classified_raw.imovelweb_organic_search_kw`
- `datalake_semrush_classified_raw.wimoveis_organic_search_kw`
- `datalake_semrush_classified_raw.casamineira_organic_search_kw`
- `datalake_semrush_classified_raw.zapimoveis_organic_search_kw`
- `datalake_semrush_classified_raw.vivareal_organic_search_kw`
- `datalake_semrush_classified_raw.chavesnamao_organic_search_kw`
- `datalake_semrush_classified_raw.quintoandar_organic_search_kw`
- `datalake_semrush_classified_raw.loft_organic_search_kw`
- `datalake_semrush_classified_raw.imoveismercadolivre_organic_search_kw`
- `datalake_semrush_classified_raw.inmuebles24_organic_search_kw`
- `datalake_semrush_classified_raw.vivanuncios_organic_search_kw`
- `datalake_semrush_classified_raw.lamudi_organic_search_kw`
- `datalake_semrush_classified_raw.propiedades_organic_search_kw`
- `datalake_semrush_classified_raw.inmuebles_organic_search_kw`
- `datalake_semrush_classified_raw.easyaviso_organic_search_kw`
- `datalake_semrush_classified_raw.zonaprop_organic_search_kw`
- `datalake_semrush_classified_raw.argenprop_organic_search_kw`
- `datalake_semrush_classified_raw.inmueblesmercadolibre_organic_search_kw`
- `datalake_semrush_classified_raw.remax_organic_search_kw`
- `datalake_semrush_classified_raw.properati_organic_search_kw`
- `datalake_semrush_classified_raw.mudafy_organic_search_kw`
- `datalake_semrush_classified_raw.urbania_organic_search_kw`
- `datalake_semrush_classified_raw.adondevivir_organic_search_kw`
- `datalake_semrush_classified_raw.properatipe_organic_search_kw`
- `datalake_semrush_classified_raw.infocasas_organic_search_kw`
- `datalake_semrush_classified_raw.nexoinmobiliario_organic_search_kw`
- `datalake_semrush_classified_raw.plusvalia_organic_search_kw`
- `datalake_semrush_classified_raw.properatiec_organic_search_kw`
- `datalake_semrush_classified_raw.icasas_organic_search_kw`
- `datalake_semrush_classified_raw.inmueblesmercadolibreec_organic_search_kw`
- `datalake_semrush_classified_raw.compreoalquile_organic_search_kw`
- `datalake_semrush_classified_raw.encuentra24_organic_search_kw`
- `datalake_semrush_classified_raw.panama-real-estate_organic_search_kw`
- `datalake_semrush_classified_raw.inmopanama_organic_search_kw`
- `datalake_semrush_classified_raw.panamaequity_organic_search_kw`

clean:
- `datalake_semrush_classified_clean.imovelweb_organic_search_kw`
- `datalake_semrush_classified_clean.wimoveis_organic_search_kw`
- `datalake_semrush_classified_clean.casamineira_organic_search_kw`
- `datalake_semrush_classified_clean.zapimoveis_organic_search_kw`
- `datalake_semrush_classified_clean.vivareal_organic_search_kw`
- `datalake_semrush_classified_clean.chavesnamao_organic_search_kw`
- `datalake_semrush_classified_clean.quintoandar_organic_search_kw`
- `datalake_semrush_classified_clean.loft_organic_search_kw`
- `datalake_semrush_classified_clean.imoveismercadolivre_organic_search_kw`
- `datalake_semrush_classified_clean.inmuebles24_organic_search_kw`
- `datalake_semrush_classified_clean.vivanuncios_organic_search_kw`
- `datalake_semrush_classified_clean.lamudi_organic_search_kw`
- `datalake_semrush_classified_clean.propiedades_organic_search_kw`
- `datalake_semrush_classified_clean.inmuebles_organic_search_kw`
- `datalake_semrush_classified_clean.easyaviso_organic_search_kw`
- `datalake_semrush_classified_clean.zonaprop_organic_search_kw`
- `datalake_semrush_classified_clean.argenprop_organic_search_kw`
- `datalake_semrush_classified_clean.inmueblesmercadolibre_organic_search_kw`
- `datalake_semrush_classified_clean.remax_organic_search_kw`
- `datalake_semrush_classified_clean.properati_organic_search_kw`
- `datalake_semrush_classified_clean.mudafy_organic_search_kw`
- `datalake_semrush_classified_clean.urbania_organic_search_kw`
- `datalake_semrush_classified_clean.adondevivir_organic_search_kw`
- `datalake_semrush_classified_clean.properatipe_organic_search_kw`
- `datalake_semrush_classified_clean.infocasas_organic_search_kw`
- `datalake_semrush_classified_clean.nexoinmobiliario_organic_search_kw`
- `datalake_semrush_classified_clean.plusvalia_organic_search_kw`
- `datalake_semrush_classified_clean.properatiec_organic_search_kw`
- `datalake_semrush_classified_clean.icasas_organic_search_kw`
- `datalake_semrush_classified_clean.inmueblesmercadolibreec_organic_search_kw`
- `datalake_semrush_classified_clean.compreoalquile_organic_search_kw`
- `datalake_semrush_classified_clean.encuentra24_organic_search_kw`
- `datalake_semrush_classified_clean.panama-real-estate_organic_search_kw`
- `datalake_semrush_classified_clean.inmopanama_organic_search_kw`
- `datalake_semrush_classified_clean.panamaequity_organic_search_kw`
