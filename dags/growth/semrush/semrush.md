# SEMRush

## Purpose

SEMRush DAG retrieves data about QuintoAndar and competitors search.


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
- `datalake_semrush_raw.quintoandar_organic_search_kw`
- `datalake_semrush_raw.imovelweb_organic_search_kw`
- `datalake_semrush_raw.zapimoveis_organic_search_kw`
- `datalake_semrush_raw.vivareal_organic_search_kw`
- `datalake_semrush_raw.casamineira_organic_search_kw`
- `datalake_semrush_raw.lopes_organic_search_kw`
- `datalake_semrush_raw.emcasa_organic_search_kw`
- `datalake_semrush_raw.chavesnamao_organic_search_kw`
- `datalake_semrush_raw.imoveisestadao_organic_search_kw`
- `datalake_semrush_raw.imoveismercadolivre_organic_search_kw`
- `datalake_semrush_raw.wimoveis_organic_search_kw`
- `datalake_semrush_raw.123i_organic_search_kw`
- `datalake_semrush_raw.trisul_organic_search_kw`
- `datalake_semrush_raw.ape11_organic_search_kw`
- `datalake_semrush_raw.arboimoveis_organic_search_kw`
- `datalake_semrush_raw.imovelguide_organic_search_kw`
- `datalake_semrush_raw.direcional_organic_search_kw`
- `datalake_semrush_raw.auxiliadorapredial_organic_search_kw`
- `datalake_semrush_raw.secovi_organic_search_kw`
- `datalake_semrush_raw.loft_organic_search_kw`
- `datalake_semrush_raw.olximoveis_organic_search_kw`
- `datalake_semrush_raw.dfimoveis_organic_search_kw`

clean:
- `datalake_semrush_clean.quintoandar_organic_search_kw`
- `datalake_semrush_clean.imovelweb_organic_search_kw`
- `datalake_semrush_clean.zapimoveis_organic_search_kw`
- `datalake_semrush_clean.vivareal_organic_search_kw`
- `datalake_semrush_clean.casamineira_organic_search_kw`
- `datalake_semrush_clean.lopes_organic_search_kw`
- `datalake_semrush_clean.emcasa_organic_search_kw`
- `datalake_semrush_clean.chavesnamao_organic_search_kw`
- `datalake_semrush_clean.imoveisestadao_organic_search_kw`
- `datalake_semrush_clean.imoveismercadolivre_organic_search_kw`
- `datalake_semrush_clean.wimoveis_organic_search_kw`
- `datalake_semrush_clean.123i_organic_search_kw`
- `datalake_semrush_clean.trisul_organic_search_kw`
- `datalake_semrush_clean.ape11_organic_search_kw`
- `datalake_semrush_clean.arboimoveis_organic_search_kw`
- `datalake_semrush_clean.imovelguide_organic_search_kw`
- `datalake_semrush_clean.direcional_organic_search_kw`
- `datalake_semrush_clean.auxiliadorapredial_organic_search_kw`
- `datalake_semrush_clean.secovi_organic_search_kw`
- `datalake_semrush_clean.loft_organic_search_kw`
- `datalake_semrush_clean.olximoveis_organic_search_kw`
- `datalake_semrush_clean.dfimoveis_organic_search_kw`
