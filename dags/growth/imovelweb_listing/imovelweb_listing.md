# Imovelweb Listing — Imovelweb CDC

CDC ingestion slice for **listing inventory, features, geolocation, online status, rankings, operation types, deliveries, phones, and interface sync** from Imovelweb's Navent MySQL database ([RD-3333](https://quintoandar.atlassian.net/browse/RD-3333), parent [RD-3332](https://quintoandar.atlassian.net/browse/RD-3332)).

Schemas: `datalake_imovelweb_raw` (raw) and `datalake_imovelweb_clean` (clean). Column mapping is shared across Navent portals (Zonaprop/Imovelweb/RealEstate); validate against Imovelweb live schema before the first Forno run.

## Tables

| Clean table | Raw table | Grain / PK | Z-ORDER |
|---|---|---|---|
| `listings` | `avisos` | one row per listing (PK `id_listing`) | id_listing |
| `listing_features` | `avisoscaracteristicas` | one row per listing feature assignment (PK `id_listing_feature`) | id_listing |
| `listing_geolocation_data` | `avisosgeolocationdata` | one row per listing (PK `id_listing`) | id_listing |
| `listings_online` | `avisosonline` | one row per listing (PK `id_listing`) | id_listing |
| `listing_rankings` | `avisosrealestateranking` | one row per listing within country, publication plan, publication area, and ranking type (logical composite key; declaration PK is `id_listing` pending source validation) | id_listing |
| `listing_operation_types` | `avisostiposdeoperaciones` | one row per listing-operation assignment (PK `id_listing_operation_type`) | id_listing |
| `listing_deliveries` | `entregasavisos` | one row per listing delivery record (PK `id_listing_delivery`) | id_listing |
| `listing_phones` | `telefonosaviso` | one row per listing phone (PK `id_listing_phone`) | id_listing |
| `interface_listing_data` | `interfaceavisodata` | one row per listing and interface integration (PK `id_listing`, `id_interface`) | id_listing, id_interface |

## Notes

- Depends on [RD-3294](https://quintoandar.atlassian.net/browse/RD-3294) (Debezium + S3 sink) for Forno/prod runs.
- `company_users.password` is excluded from clean; other PII columns remain without `table_privileges` in this POC.
- `empresas.falta` → `dt_missing` and `usuariosempresas.falta` → `ts_missing`: Spanish column semantics not yet confirmed with domain owner.
- `listing_rankings`: declaration PK is `id_listing`; logical grain may be composite — validate against source before tightening DQ.
