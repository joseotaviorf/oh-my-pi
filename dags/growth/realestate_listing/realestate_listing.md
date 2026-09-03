# RealEstate Listing — MySQL CDC (Navent)

CDC slice of the RealEstate Navent MySQL database for the **listing** domain. Parent initiative: [RD-3335](https://quintoandar.atlassian.net/browse/RD-3335) (Navent → QuintoAndar migration POC, parent [RD-3332](https://quintoandar.atlassian.net/browse/RD-3332)).

**Schedule:** `0 8,12,21 * * *` (3× daily, minute 0 UTC).
**Schemas:** `datalake_realestate_raw` / `datalake_realestate_clean` (shared across all RealEstate CDC DAGs).
**Secret:** `REALESTATE_DB`

## Tables

| Raw table | Clean table | Grain / PK | Z-order |
|---|---|---|---|
| `avisos` | `listings` | id_listing | id_listing |
| `avisoscaracteristicas` | `listing_features` | id_listing_feature | id_listing |
| `avisosgeolocationdata` | `listing_geolocation_data` | id_listing | id_listing |
| `avisosonline` | `listings_online` | id_listing | id_listing |
| `avisosrealestateranking` | `listing_rankings` | id_listing, id_country, id_publication_plan, id_publication_area, ranking_type | id_listing |
| `avisostiposdeoperaciones` | `listing_operation_types` | id_listing_operation_type | id_listing |
| `entregasavisos` | `listing_deliveries` | id_listing_delivery | id_listing |
| `interfaceavisodata` | `interface_listing_data` | id_listing, id_interface | id_listing, id_interface |
| `telefonosaviso` | `listing_phones` | id_listing_phone | id_listing |

## Notes

- No date partitions on any table; rely on Z-order keys documented in metadata.
- Depends on [RD-3294](https://quintoandar.atlassian.net/browse/RD-3294) (Debezium + S3 sink) for raw data availability.
- Column mapping shared with Zonaprop/Imovelweb Navent portals; validated against Zonaprop mapping spreadsheet.
