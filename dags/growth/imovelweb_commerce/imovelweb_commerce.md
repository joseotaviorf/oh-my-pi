# Imovelweb Commerce — Imovelweb CDC

CDC ingestion slice for **commercial orders, order line items, products, product lines, and publication-plan pricing** from Imovelweb's Navent MySQL database ([RD-3333](https://quintoandar.atlassian.net/browse/RD-3333), parent [RD-3332](https://quintoandar.atlassian.net/browse/RD-3332)).

Schemas: `datalake_imovelweb_raw` (raw) and `datalake_imovelweb_clean` (clean). Column mapping is shared across Navent portals (Zonaprop/Imovelweb/RealEstate); validate against Imovelweb live schema before the first Forno run.

## Tables

| Clean table | Raw table | Grain / PK | Z-ORDER |
|---|---|---|---|
| `orders` | `pedidos` | one row per order (PK `id_order`) | id_order |
| `order_items` | `itemspedido` | one row per order line (PK `id_order_item`) | id_order |
| `products` | `productos` | one row per product (PK `id_product`) | id_product |
| `product_lines` | `lineasdeproducto` | one row per product line (PK `id_product_line`) | id_product_line |
| `publication_plans` | `planesdepublicacion` | one row per publication plan (PK `id_publication_plan`) | id_publication_plan |
| `plans_by_product_by_country` | `planesporproductoporpais` | one row per publication plan, product, and country (PK `id_publication_plan`, `id_product`, `id_country`) | id_publication_plan, id_product, id_country |

## Notes

- Depends on [RD-3294](https://quintoandar.atlassian.net/browse/RD-3294) (Debezium + S3 sink) for Forno/prod runs.
- `company_users.password` is excluded from clean; other PII columns remain without `table_privileges` in this POC.
- `empresas.falta` → `dt_missing` and `usuariosempresas.falta` → `ts_missing`: Spanish column semantics not yet confirmed with domain owner.
- `listing_rankings`: declaration PK is `id_listing`; logical grain may be composite — validate against source before tightening DQ.
