# Zonaprop Listings — MySQL CDC (Navent, RD-3334)

CDC ingestion of Zonaprop listing entities (classified ads, features, geolocation, online state, rankings, operation types, deliveries, phones and interface sync rows) from the Navent MySQL portal. Feeds listing analytics and the Navent migration POC.

Schemas: `datalake_zonaprop_raw` (raw) / `datalake_zonaprop_clean` (clean).

## Tables

| Raw table | Clean table | PK | Z-order |
|---|---|---|---|
| `avisos` | `listings` | id_listing | id_listing |
| `avisoscaracteristicas` | `listing_features` | id_listing_feature | id_listing |
| `avisosgeolocationdata` | `listing_geolocation_data` | id_listing | id_listing |
| `avisosonline` | `listings_online` | id_listing | id_listing |
| `avisosrealestateranking` | `listing_rankings` | id_listing | id_listing |
| `avisostiposdeoperaciones` | `listing_operation_types` | id_listing_operation_type | id_listing |
| `entregasavisos` | `listing_deliveries` | id_listing_delivery | id_listing |
| `telefonosaviso` | `listing_phones` | id_listing_phone | id_listing |
| `interfaceavisodata` | `interface_listing_data` | id_listing, id_interface | id_listing, id_interface |

## Sibling DAGs

The Zonaprop CDC surface is split into five DAGs: `zonaprop_listing`, `zonaprop_company`, `zonaprop_commerce`, `zonaprop_catalog`, `zonaprop_demand`.

## Notes

- Shared column mapping across Navent portals; validated on Zonaprop.
- Depends on RD-3294 (Debezium + S3 sink) before first Forno run.
- `usuariosempresas.password` is excluded from clean (no credentials in clean layer).
