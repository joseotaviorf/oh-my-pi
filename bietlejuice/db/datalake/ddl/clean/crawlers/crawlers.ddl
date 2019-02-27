drop table datalake_clean.crawlers;
create external table datalake_clean.crawlers(
  id                 string,
  website            string,
  url                string,
  http_status        string,
  crawled_on         string,
  updated_on         string,
  business           string,
  `type`             string,
  advertiser_name    string,
  advertiser_type    string,
  advertiser_id      string,
  phones             string,
  price              string,
  rent               string,
  condominium        string,
  iptu               string,
  total_area         string,
  useful_area        string,
  bedrooms           string,
  suites             string,
  toilets            string,
  garages            string,
  photos             string,
  description        string,
  unit_features      string,
  common_features    string,
  complementary_info string,
  year_building      string,
  cep                string,
  lat                string,
  lng                string,
  street             string,
  nb_street          string,
  neighborhood       string,
  city               string,
  state              string,
  crawl_timestamp    string
)
partitioned by(
  ws         string,
  started_on date
)
stored as parquet location 's3://5a-datalake/clean/crawlers';

msck repair table datalake_clean.crawlers;