# Zonaprop Commerce — MySQL CDC (Navent, RD-3334)

CDC ingestion of Zonaprop commercial orders, order line items, sellable products, product lines and publication-plan catalog from the Navent MySQL portal. Feeds revenue and subscription analytics for the migration POC.

Schemas: `datalake_zonaprop_raw` (raw) / `datalake_zonaprop_clean` (clean).

## Tables

| Raw table | Clean table | PK | Z-order |
|---|---|---|---|
| `pedidos` | `orders` | id_order | id_order |
| `itemspedido` | `order_items` | id_order_item | id_order |
| `productos` | `products` | id_product | id_product |
| `lineasdeproducto` | `product_lines` | id_product_line | id_product_line |
| `planesdepublicacion` | `publication_plans` | id_publication_plan | id_publication_plan |
| `planesporproductoporpais` | `plans_by_product_by_country` | id_publication_plan, id_product, id_country | id_publication_plan, id_product, id_country |

## Sibling DAGs

The Zonaprop CDC surface is split into five DAGs: `zonaprop_listing`, `zonaprop_company`, `zonaprop_commerce`, `zonaprop_catalog`, `zonaprop_demand`.

## Notes

- Shared column mapping across Navent portals; validated on Zonaprop.
- Depends on RD-3294 (Debezium + S3 sink) before first Forno run.
- `usuariosempresas.password` is excluded from clean (no credentials in clean layer).
