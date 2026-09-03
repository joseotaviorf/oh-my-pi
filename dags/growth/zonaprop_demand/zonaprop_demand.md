# Zonaprop Demand — MySQL CDC (Navent, RD-3334)

CDC ingestion of Zonaprop buyer contact actions (lead events) from the Navent MySQL portal. Feeds demand-funnel and conversion analytics for the migration POC.

Schemas: `datalake_zonaprop_raw` (raw) / `datalake_zonaprop_clean` (clean).

## Tables

| Raw table | Clean table | PK | Z-order |
|---|---|---|---|
| `contactosacciones` | `contact_actions` | id_contact_action | id_contact |

## Sibling DAGs

The Zonaprop CDC surface is split into five DAGs: `zonaprop_listing`, `zonaprop_company`, `zonaprop_commerce`, `zonaprop_catalog`, `zonaprop_demand`.

## Notes

- Shared column mapping across Navent portals; validated on Zonaprop.
- Depends on RD-3294 (Debezium + S3 sink) before first Forno run.
- `usuariosempresas.password` is excluded from clean (no credentials in clean layer).
