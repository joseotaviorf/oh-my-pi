#!/usr/bin/env python3
"""
generate_lineage_diagram.py

Generates a self-contained interactive HTML column-level lineage diagram
for the dw_devlake pipeline.

Features:
    - Barycenter table ordering (Sugiyama heuristic) to minimize edge crossings
    - Dim-by-default edges with hover highlighting
    - Color-coded edges by source table
    - Edge bundling (table-pair cable convergence)
    - Transformation classification (passthrough, rename, SHA2→SK, derive, etc.)
    - Self-validation quality metrics panel

Reads YAML metadata files from clean and dw layers; JavaScript draws
bundled bezier arrows after the browser lays out the table cards.

Outputs:
    lineage_diagram.html  — open in any browser
    lineage_diagram.png   — screenshot for markdown embedding
                            (requires: pip install playwright && playwright install chromium)

Usage:
    python dags/tech_platform/dw_devlake/tools/generate_lineage_diagram.py
"""

from __future__ import annotations

import json
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

import yaml

SCRIPT_DIR = Path(__file__).parent.resolve()
DAG_DIR = SCRIPT_DIR.parent
CLEAN_META = DAG_DIR.parent / "devlake/metadata/clean"
DW_META = DAG_DIR / "metadata/dw"
OUTPUT_HTML = DAG_DIR / "lineage_diagram.html"
OUTPUT_PNG = DAG_DIR / "lineage_diagram.png"

LAYER_RAW = "raw"
LAYER_CLEAN = "clean"
LAYER_DW = "dw"

LAYER_COLOR = {LAYER_RAW: "#6b7280", LAYER_CLEAN: "#3b82f6", LAYER_DW: "#f97316"}
LAYER_TITLE = {
    LAYER_RAW: ("datalake_devlake_raw", "MySQL CDC snapshot"),
    LAYER_CLEAN: ("datalake_devlake_clean", "renamed + derived columns"),
    LAYER_DW: ("dw_devlake", "Kimball star schema · 06:00 UTC"),
}

TABLE_EDGE_COLORS = [
    "#0891b2",
    "#2563eb",
    "#7c3aed",
    "#059669",
    "#d97706",
    "#dc2626",
    "#be185d",
    "#4f46e5",
    "#0d9488",
    "#ca8a04",
]


@dataclass
class ColumnMeta:
    name: str
    description: str
    lineage: list[str] = field(default_factory=list)

    @property
    def is_generated(self) -> bool:
        return not self.lineage


@dataclass
class TableNode:
    db: str
    table: str
    layer: str
    columns: list[ColumnMeta] = field(default_factory=list)

    @property
    def key(self) -> str:
        return f"{self.db}.{self.table}"

    @property
    def node_id(self) -> str:
        return f"{self.db}__{self.table}"


@dataclass
class LineageEdge:
    src_db: str
    src_table: str
    src_col: str
    dst_db: str
    dst_table: str
    dst_col: str


def db_to_layer(db_name: str) -> str:
    if db_name.endswith("_raw"):
        return LAYER_RAW
    if db_name.endswith("_clean"):
        return LAYER_CLEAN
    return LAYER_DW


def load_tables_from_dir(meta_dir: Path) -> list[TableNode]:
    tables = []
    for path in sorted(meta_dir.glob("*.yml")):
        with open(path, encoding="utf-8") as f:
            data = yaml.safe_load(f)
        if not data:
            continue
        db = data["database_name"]
        cols = []
        for col_name, col_data in (data.get("columns") or {}).items():
            if col_data is None:
                col_data = {}
            cols.append(
                ColumnMeta(
                    name=col_name,
                    description=col_data.get("description", ""),
                    lineage=col_data.get("lineage") or [],
                )
            )
        tables.append(
            TableNode(
                db=db,
                table=data["table_name"],
                layer=db_to_layer(db),
                columns=cols,
            )
        )
    return tables


def build_graph(
    all_tables: list[TableNode],
) -> tuple[dict[str, TableNode], list[LineageEdge]]:
    nodes: dict[str, TableNode] = {t.key: t for t in all_tables}
    edges: list[LineageEdge] = []

    for table in all_tables:
        for col in table.columns:
            for ref in col.lineage:
                parts = ref.split(".")
                if len(parts) != 3:
                    continue
                src_db, src_table, src_col = parts
                src_key = f"{src_db}.{src_table}"

                if src_key not in nodes:
                    nodes[src_key] = TableNode(
                        db=src_db,
                        table=src_table,
                        layer=db_to_layer(src_db),
                        columns=[],
                    )
                src_node = nodes[src_key]
                if not any(c.name == src_col for c in src_node.columns):
                    src_node.columns.append(
                        ColumnMeta(name=src_col, description="", lineage=[])
                    )

                edges.append(
                    LineageEdge(
                        src_db=src_db,
                        src_table=src_table,
                        src_col=src_col,
                        dst_db=table.db,
                        dst_table=table.table,
                        dst_col=col.name,
                    )
                )

    return nodes, edges


# ---------------------------------------------------------------------------
# Barycenter ordering (Sugiyama crossing minimization heuristic)
# ---------------------------------------------------------------------------
def barycenter_order(
    nodes: dict[str, TableNode],
    edges: list[LineageEdge],
    iterations: int = 4,
) -> dict[str, list[TableNode]]:
    """Order tables within each layer to minimize edge crossings."""
    layers: dict[str, list[TableNode]] = defaultdict(list)
    for n in nodes.values():
        layers[n.layer].append(n)

    for layer_list in layers.values():
        layer_list.sort(key=lambda n: n.table)

    layer_order = [LAYER_RAW, LAYER_CLEAN, LAYER_DW]

    edge_pairs = [
        (e.src_db + "." + e.src_table, e.dst_db + "." + e.dst_table) for e in edges
    ]

    for _ in range(iterations):
        for i in range(1, len(layer_order)):
            prev_layer = layer_order[i - 1]
            curr_layer = layer_order[i]
            prev_pos = {n.key: idx for idx, n in enumerate(layers[prev_layer])}

            edge_counts: dict[str, list[int]] = defaultdict(list)
            for src_key, dst_key in edge_pairs:
                if src_key in prev_pos and any(
                    n.key == dst_key for n in layers[curr_layer]
                ):
                    edge_counts[dst_key].append(prev_pos[src_key])

            barycenters = {}
            for n in layers[curr_layer]:
                positions = edge_counts.get(n.key, [])
                barycenters[n.key] = (
                    sum(positions) / len(positions) if positions else 999
                )

            layers[curr_layer].sort(key=lambda n: barycenters[n.key])

        for i in range(len(layer_order) - 2, -1, -1):
            next_layer = layer_order[i + 1]
            curr_layer = layer_order[i]
            next_pos = {n.key: idx for idx, n in enumerate(layers[next_layer])}

            edge_counts: dict[str, list[int]] = defaultdict(list)
            for src_key, dst_key in edge_pairs:
                if dst_key in next_pos and any(
                    n.key == src_key for n in layers[curr_layer]
                ):
                    edge_counts[src_key].append(next_pos[dst_key])

            barycenters = {}
            for n in layers[curr_layer]:
                positions = edge_counts.get(n.key, [])
                barycenters[n.key] = (
                    sum(positions) / len(positions) if positions else 999
                )

            layers[curr_layer].sort(key=lambda n: barycenters[n.key])

    return dict(layers)


# ---------------------------------------------------------------------------
# HTML generation
# ---------------------------------------------------------------------------
def _col_rows_html(columns: list[ColumnMeta]) -> str:
    rows = []
    for col in columns:
        cls = " generated" if col.is_generated else ""
        title = f' title="{col.description}"' if col.description else ""
        rows.append(
            f'    <div class="col-row{cls}" data-col="{col.name}"{title}>'
            f"{col.name}</div>"
        )
    return "\n".join(rows)


def _table_card_html(node: TableNode) -> str:
    n_cols = len(node.columns)
    cols_html = _col_rows_html(node.columns)
    return (
        f'<div class="table-card" data-table="{node.node_id}">\n'
        f'  <div class="table-header">\n'
        f'    <div class="table-header-left">\n'
        f'      <span class="table-name">{node.table}</span>\n'
        f'      <span class="table-db">{node.db}</span>\n'
        f"    </div>\n"
        f'    <span class="col-count-badge">{n_cols} cols</span>\n'
        f"  </div>\n"
        f'  <div class="col-list">\n'
        f"{cols_html}\n"
        f"  </div>\n"
        f"</div>"
    )


def _layer_html(layer: str, layer_nodes: list[TableNode]) -> str:
    label, sublabel = LAYER_TITLE[layer]
    cards = "\n".join(_table_card_html(n) for n in layer_nodes)
    return (
        f'<div class="layer layer-{layer}">\n'
        f'  <div class="layer-hd">\n'
        f'    <div class="layer-name">{label}</div>\n'
        f'    <div class="layer-sub">{sublabel}</div>\n'
        f"  </div>\n"
        f"{cards}\n"
        f"</div>"
    )


def _build_table_colors(
    ordered_layers: dict[str, list[TableNode]],
) -> dict[str, str]:
    """Assign a unique color to each clean-layer table (raw mirrors clean)."""
    colors: dict[str, str] = {}
    clean_tables = ordered_layers.get(LAYER_CLEAN, [])
    for i, node in enumerate(clean_tables):
        c = TABLE_EDGE_COLORS[i % len(TABLE_EDGE_COLORS)]
        colors[node.node_id] = c
        raw_id = node.node_id.replace("_clean__", "_raw__")
        colors[raw_id] = c
    return colors


def build_html(
    nodes: dict[str, TableNode],
    edges: list[LineageEdge],
    ordered_layers: dict[str, list[TableNode]],
) -> str:
    edges_data = [
        {
            "st": e.src_db + "__" + e.src_table,
            "sc": e.src_col,
            "sl": nodes[f"{e.src_db}.{e.src_table}"].layer,
            "dt": e.dst_db + "__" + e.dst_table,
            "dc": e.dst_col,
            "dl": nodes[f"{e.dst_db}.{e.dst_table}"].layer,
        }
        for e in edges
    ]
    edges_json = json.dumps(edges_data, indent=2)

    layers_html = []
    for layer in [LAYER_RAW, LAYER_CLEAN, LAYER_DW]:
        layer_nodes = ordered_layers.get(layer, [])
        if layer_nodes:
            layers_html.append(_layer_html(layer, layer_nodes))
    layers_block = "\n".join(layers_html)

    table_colors = _build_table_colors(ordered_layers)
    table_colors_json = json.dumps(table_colors, indent=2)

    short_names = {}
    for node in ordered_layers.get(LAYER_CLEAN, []):
        short_names[node.node_id] = node.table
    short_names_json = json.dumps(short_names, indent=2)

    raw_c = LAYER_COLOR[LAYER_RAW]
    clean_c = LAYER_COLOR[LAYER_CLEAN]
    dw_c = LAYER_COLOR[LAYER_DW]

    return _HTML_TEMPLATE.format(
        raw_c=raw_c,
        clean_c=clean_c,
        dw_c=dw_c,
        layers_block=layers_block,
        edges_json=edges_json,
        table_colors_json=table_colors_json,
        short_names_json=short_names_json,
    )


_HTML_TEMPLATE = """\
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>dw_devlake — Column-Level Lineage</title>
<style>
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Inter', sans-serif;
    background: #f1f5f9; padding: 32px 40px 48px; min-width: 1200px;
  }}
  .page-header {{ margin-bottom: 12px; }}
  .page-header h1 {{ font-size: 17px; font-weight: 700; color: #0f172a; margin-bottom: 4px; }}
  .page-header p {{ font-size: 12.5px; color: #64748b; }}
  .controls {{ display: flex; gap: 8px; margin-top: 10px; align-items: center; }}
  .controls button {{
    font-size: 11.5px; padding: 5px 12px; border-radius: 6px;
    border: 1px solid #cbd5e1; background: #fff; color: #475569;
    cursor: pointer; transition: all .15s; font-weight: 500;
  }}
  .controls button:hover {{ background: #f8fafc; border-color: #94a3b8; }}
  .controls button.active {{ background: #0f172a; color: #fff; border-color: #0f172a; }}
  #diagram {{
    position: relative; display: flex; flex-direction: row;
    gap: 140px; align-items: flex-start; margin-top: 20px;
  }}
  #arrows {{ position: absolute; top: 0; left: 0; pointer-events: none; z-index: 0; overflow: visible; }}
  .layer {{ display: flex; flex-direction: column; gap: 14px; position: relative; z-index: 1; min-width: 210px; }}
  .layer-hd {{ margin-bottom: 4px; }}
  .layer-name {{ font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.07em; }}
  .layer-sub {{ font-size: 11px; color: #94a3b8; margin-top: 2px; }}
  .layer-raw   .layer-name {{ color: {raw_c}; }}
  .layer-clean .layer-name {{ color: {clean_c}; }}
  .layer-dw    .layer-name {{ color: {dw_c}; }}
  .table-card {{
    background: #fff; border-radius: 8px; overflow: hidden;
    box-shadow: 0 1px 3px rgba(0,0,0,.09), 0 1px 2px rgba(0,0,0,.05);
    border: 1px solid #e2e8f0; transition: box-shadow .2s, border-color .2s;
  }}
  .table-card.highlight {{ box-shadow: 0 2px 12px rgba(0,0,0,.15); border-color: #94a3b8; }}
  .table-card.dimmed {{ opacity: 0.4; }}
  .table-header {{
    display: flex; flex-direction: row; align-items: center; justify-content: space-between;
    padding: 10px 14px 9px; color: white; cursor: pointer;
  }}
  .layer-raw   .table-header {{ background: {raw_c}; }}
  .layer-clean .table-header {{ background: {clean_c}; }}
  .layer-dw    .table-header {{ background: {dw_c}; }}
  .table-header-left {{ display: flex; flex-direction: column; }}
  .table-name {{ font-size: 13px; font-weight: 700; letter-spacing: -.01em; }}
  .table-db {{ font-size: 10px; color: rgba(255,255,255,.72); margin-top: 2px; }}
  .col-count-badge {{
    font-size: 9.5px; background: rgba(255,255,255,.22); padding: 2px 7px;
    border-radius: 10px; color: rgba(255,255,255,.85); font-weight: 600; white-space: nowrap;
  }}
  .col-list {{ padding: 3px 0; }}
  .col-row {{
    padding: 4px 14px; font-size: 12px; color: #374151;
    border-bottom: 1px solid #f8fafc; white-space: nowrap;
    position: relative; cursor: default; transition: background .12s, opacity .12s;
  }}
  .col-row:last-child {{ border-bottom: none; }}
  .col-row:hover {{ background: #f0f9ff; }}
  .col-row.generated {{ color: #9ca3af; font-style: italic; font-size: 11.5px; }}
  .col-row.linked:hover {{ background: #eff6ff; }}
  .col-row.highlight {{ background: #dbeafe; font-weight: 600; }}
  .col-row.dimmed {{ opacity: 0.3; }}
  .port {{
    position: absolute; width: 8px; height: 8px;
    border-radius: 50%; top: 50%; transform: translateY(-50%); border: 2px solid #fff;
  }}
  .port-r {{ right: -5px; }}
  .port-l {{ left: -5px; }}
  .layer-raw   .port {{ background: {raw_c}; }}
  .layer-clean .port {{ background: {clean_c}; }}
  .layer-dw    .port {{ background: {dw_c}; }}
  .legend {{ display: flex; gap: 20px; margin-top: 28px; flex-wrap: wrap; align-items: center; }}
  .legend-item {{ display: flex; align-items: center; gap: 6px; font-size: 12px; color: #64748b; }}
  .legend-dot {{ width: 10px; height: 10px; border-radius: 50%; flex-shrink: 0; }}
  .edge-legend {{ display: flex; gap: 14px; margin-top: 14px; flex-wrap: wrap; align-items: center; }}
  .edge-legend-title {{ font-size: 11px; font-weight: 600; color: #64748b; margin-right: 4px; }}
  .edge-legend-item {{
    display: flex; align-items: center; gap: 5px; font-size: 11px; color: #64748b;
    cursor: pointer; padding: 2px 6px; border-radius: 4px; transition: background .12s;
  }}
  .edge-legend-item:hover {{ background: #e2e8f0; }}
  .edge-legend-swatch {{ width: 18px; height: 3px; border-radius: 2px; flex-shrink: 0; }}
  #tooltip {{
    position: absolute; background: rgba(15,23,42,0.94); color: #e2e8f0;
    padding: 10px 14px; border-radius: 8px; font-size: 11.5px; max-width: 340px;
    pointer-events: none; z-index: 200; display: none; line-height: 1.5;
    box-shadow: 0 4px 16px rgba(0,0,0,.25);
  }}
  #tooltip .tt-title {{ font-weight: 700; font-size: 12px; color: #fff; margin-bottom: 4px; }}
  #tooltip .tt-badge {{
    display: inline-block; font-size: 10px; padding: 1px 6px;
    border-radius: 4px; font-weight: 600; margin-left: 6px;
  }}
  #tooltip .tt-row {{ display: flex; align-items: center; gap: 6px; margin-top: 3px; }}
  #tooltip .tt-arrow {{ color: #94a3b8; font-size: 10px; }}
  #tooltip .tt-desc {{ color: #94a3b8; font-size: 10.5px; margin-top: 4px; }}
  #metrics-panel {{
    position: fixed; bottom: 16px; right: 16px;
    background: #fff; border-radius: 10px;
    box-shadow: 0 4px 20px rgba(0,0,0,.12); border: 1px solid #e2e8f0;
    padding: 14px 18px; z-index: 100; min-width: 280px;
    display: none; font-size: 12px;
  }}
  #metrics-panel.visible {{ display: block; }}
  #metrics-panel h3 {{ font-size: 12px; font-weight: 700; color: #0f172a; margin-bottom: 8px; }}
  .metric-row {{ display: flex; justify-content: space-between; padding: 3px 0; border-bottom: 1px solid #f8fafc; }}
  .metric-row:last-child {{ border-bottom: none; }}
  .metric-label {{ color: #64748b; }}
  .metric-value {{ font-weight: 600; color: #0f172a; }}
  .metric-value.good {{ color: #059669; }}
  .metric-value.warn {{ color: #d97706; }}
  .metric-value.bad {{ color: #dc2626; }}
  .metric-section-title {{
    font-size: 10.5px; font-weight: 600; color: #94a3b8;
    text-transform: uppercase; letter-spacing: 0.05em; margin-top: 10px; margin-bottom: 4px;
  }}
  .badge-passthrough {{ background: #d1fae5; color: #065f46; }}
  .badge-rename {{ background: #dbeafe; color: #1e40af; }}
  .badge-sk {{ background: #fce7f3; color: #9d174d; }}
  .badge-datekey {{ background: #fef3c7; color: #92400e; }}
  .badge-cast {{ background: #e0e7ff; color: #3730a3; }}
  .badge-derive {{ background: #fde68a; color: #78350f; }}
  .badge-convert {{ background: #ccfbf1; color: #134e4a; }}
</style>
</head>
<body>
<div class="page-header">
  <h1>dw_devlake &mdash; Column-Level Data Lineage</h1>
  <p>DevLake MySQL RDS &rarr; datalake_devlake_raw &rarr; datalake_devlake_clean &rarr; dw_devlake (Kimball star schema)</p>
  <div class="controls">
    <button id="btn-show-all">Show All Edges</button>
    <button id="btn-metrics">Quality Metrics</button>
  </div>
</div>
<div id="diagram">
  <svg id="arrows"></svg>
{layers_block}
</div>
<div class="legend">
  <div class="legend-item"><div class="legend-dot" style="background:{raw_c}"></div>datalake_devlake_raw</div>
  <div class="legend-item"><div class="legend-dot" style="background:{clean_c}"></div>datalake_devlake_clean</div>
  <div class="legend-item"><div class="legend-dot" style="background:{dw_c}"></div>dw_devlake</div>
</div>
<div class="edge-legend" id="edge-legend">
  <span class="edge-legend-title">Edge colors (by source table):</span>
</div>
<div id="tooltip"></div>
<div id="metrics-panel"><h3>Self-Validation Quality Metrics</h3><div id="metrics-content"></div></div>
<script>
const EDGES = {edges_json};
const TABLE_COLORS = {table_colors_json};
const TABLE_SHORT_NAMES = {short_names_json};
const NS = 'http://www.w3.org/2000/svg';

function classifyEdge(e) {{
  const s = e.sc, d = e.dc;
  if (s === d) return {{ type:'passthrough', label:'=', css:'badge-passthrough', desc:'Passed through unchanged' }};
  if (e.sl === 'raw' && e.dl === 'clean') {{
    if (s === 'created_at' && d === 'ts_created') return {{ type:'rename', label:'rename', css:'badge-rename', desc:'Renamed to ts_ convention' }};
    if (s.endsWith('_date') && d.startsWith('ts_')) return {{ type:'cast', label:'cast→ts', css:'badge-cast', desc:'Cast to timestamp' }};
    if (s.endsWith('_time') && d.endsWith('_seconds')) return {{ type:'convert', label:'→seconds', css:'badge-convert', desc:'Converted to seconds' }};
    if (s === 'deleted' && d === 'is_deleted') return {{ type:'rename', label:'rename', css:'badge-rename', desc:'Renamed to is_ convention' }};
    if (s === 'status' && d === 'is_merged') return {{ type:'derive', label:'derive', css:'badge-derive', desc:"Derived: TRUE when status=MERGED" }};
    return {{ type:'rename', label:'rename', css:'badge-rename', desc:'Renamed: '+s+' → '+d }};
  }}
  if (e.sl === 'clean' && e.dl === 'dw') {{
    if (d.startsWith('sk_') && d.endsWith('_date') && s.startsWith('ts_')) return {{ type:'datekey', label:'→date_key', css:'badge-datekey', desc:'Date key: YYYYMMDD from '+s }};
    if (d.startsWith('sk_') && s.startsWith('id_')) return {{ type:'sk', label:'SHA2→SK', css:'badge-sk', desc:'Surrogate key via SHA2('+s+')' }};
    if (d.startsWith('dt_') && s.startsWith('ts_')) return {{ type:'cast', label:'ts→dt', css:'badge-cast', desc:'Cast timestamp to date' }};
    if (d === 'is_merged' && s === 'pr_status') return {{ type:'derive', label:'derive', css:'badge-derive', desc:"Derived: TRUE when MERGED" }};
    return {{ type:'passthrough', label:'=', css:'badge-passthrough', desc:'Passed through unchanged' }};
  }}
  return {{ type:'rename', label:'?', css:'badge-rename', desc:'' }};
}}

function getEl(t,c) {{ return document.querySelector('[data-table="'+t+'"] [data-col="'+c+'"]'); }}
function addPort(el,side) {{
  if (!el || el.querySelector('.port-'+side)) return;
  const d = document.createElement('span'); d.className = 'port port-'+side;
  el.appendChild(d); el.classList.add('linked');
}}
function midY(r,w) {{ return (r.top+r.bottom)/2 - w.top; }}

function drawEdges() {{
  const svg = document.getElementById('arrows'), wrap = document.getElementById('diagram');
  const wR = wrap.getBoundingClientRect(), frag = document.createDocumentFragment();
  svg.innerHTML = '';
  for (const e of EDGES) {{ addPort(getEl(e.st,e.sc),'r'); addPort(getEl(e.dt,e.dc),'l'); }}
  const pairs = new Map();
  for (const e of EDGES) {{ const k=e.st+'→'+e.dt; if(!pairs.has(k))pairs.set(k,[]); pairs.get(k).push(e); }}
  const gapKeys = {{'raw→clean':[],'clean→dw':[]}};
  for (const [k] of pairs) {{ const s=pairs.get(k)[0]; const g=s.sl+'→'+s.dl; if(gapKeys[g])gapKeys[g].push(k); }}
  const pairLane = new Map();
  for (const [,keys] of Object.entries(gapKeys)) {{
    keys.forEach((k,i) => {{ pairLane.set(k, 0.25+(keys.length>1?(i/(keys.length-1))*0.4:0.2)); }});
  }}
  const pairCentroids = new Map();
  for (const [pk,edges] of pairs) {{
    let sy=0,dy=0,c=0;
    for (const e of edges) {{ const se=getEl(e.st,e.sc),de=getEl(e.dt,e.dc); if(!se||!de)continue; sy+=midY(se.getBoundingClientRect(),wR); dy+=midY(de.getBoundingClientRect(),wR); c++; }}
    if(c>0) pairCentroids.set(pk,{{srcCentroid:sy/c,dstCentroid:dy/c,count:c}});
  }}
  const edgeEls = [];
  for (const e of EDGES) {{
    const se=getEl(e.st,e.sc),de=getEl(e.dt,e.dc); if(!se||!de) continue;
    const sr=se.getBoundingClientRect(),dr=de.getBoundingClientRect();
    const x1=sr.right-wR.left, y1=midY(sr,wR), x2=dr.left-wR.left, y2=midY(dr,wR);
    const pk=e.st+'→'+e.dt, lane=pairLane.get(pk)||0.45, color=TABLE_COLORS[e.st]||'#9ca3af';
    const cen=pairCentroids.get(pk), bs=cen&&cen.count>2?0.65:0.3;
    const mcy=cen?(cen.srcCentroid+cen.dstCentroid)/2:(y1+y2)/2;
    const cy1=y1+(mcy-y1)*bs, cy2=y2+(mcy-y2)*bs;
    const cx1=x1+(x2-x1)*lane, cx2=x2-(x2-x1)*(1-lane);
    const p=document.createElementNS(NS,'path');
    p.setAttribute('d','M'+x1+','+y1+' C'+cx1+','+cy1+' '+cx2+','+cy2+' '+x2+','+y2);
    p.setAttribute('stroke',color); p.setAttribute('fill','none');
    p.setAttribute('stroke-width','1.5'); p.setAttribute('stroke-opacity','0.07');
    p.setAttribute('data-src-table',e.st); p.setAttribute('data-dst-table',e.dt);
    p.setAttribute('data-src-col',e.sc); p.setAttribute('data-dst-col',e.dc);
    p.classList.add('edge-path');
    frag.appendChild(p); edgeEls.push({{path:p, edge:e, x1:x1, y1:y1, x2:x2, y2:y2}});
  }}
  svg.appendChild(frag);
  const r=wrap.getBoundingClientRect(); svg.setAttribute('width',r.width); svg.setAttribute('height',r.height);
  return edgeEls;
}}

let showAllMode = false;
function setupInteraction(edgeEls) {{
  const allPaths=document.querySelectorAll('.edge-path'), allCards=document.querySelectorAll('.table-card'), allCols=document.querySelectorAll('.col-row');
  const tooltip=document.getElementById('tooltip');
  function highlightColumn(tid,cn) {{
    const ct=new Set(), cc=new Set();
    for (const {{path,edge}} of edgeEls) {{
      if((edge.st===tid&&edge.sc===cn)||(edge.dt===tid&&edge.dc===cn)) {{
        path.setAttribute('stroke-opacity','0.85'); path.setAttribute('stroke-width','2.5');
        ct.add(edge.st); ct.add(edge.dt); cc.add(edge.st+'::'+edge.sc); cc.add(edge.dt+'::'+edge.dc);
      }}
    }}
    if(!cc.size) return;
    allCards.forEach(c=>{{ c.classList.toggle('highlight',ct.has(c.dataset.table)); c.classList.toggle('dimmed',!ct.has(c.dataset.table)); }});
    allCols.forEach(c=>{{ const card=c.closest('.table-card'); if(!card)return; const cid=card.dataset.table+'::'+c.dataset.col;
      c.classList.toggle('highlight',cc.has(cid)); c.classList.toggle('dimmed',!cc.has(cid)&&ct.has(card.dataset.table));
    }});
    for (const {{path}} of edgeEls) {{
      const sk=path.getAttribute('data-src-table')+'::'+path.getAttribute('data-src-col');
      const dk=path.getAttribute('data-dst-table')+'::'+path.getAttribute('data-dst-col');
      if(!cc.has(sk)&&!cc.has(dk)) path.setAttribute('stroke-opacity','0.03');
    }}
  }}
  function highlightTable(tid) {{
    const ct=new Set([tid]), cc=new Set();
    for (const {{path,edge}} of edgeEls) {{
      if(edge.st===tid||edge.dt===tid) {{
        path.setAttribute('stroke-opacity','0.65'); path.setAttribute('stroke-width','2');
        ct.add(edge.st); ct.add(edge.dt); cc.add(edge.st+'::'+edge.sc); cc.add(edge.dt+'::'+edge.dc);
      }}
    }}
    allCards.forEach(c=>{{ c.classList.toggle('highlight',ct.has(c.dataset.table)); c.classList.toggle('dimmed',!ct.has(c.dataset.table)); }});
    allCols.forEach(c=>{{ const card=c.closest('.table-card'); if(!card)return;
      if(ct.has(card.dataset.table)) {{ const cid=card.dataset.table+'::'+c.dataset.col; c.classList.toggle('highlight',cc.has(cid)); c.classList.toggle('dimmed',!cc.has(cid)); }}
    }});
    for (const {{path}} of edgeEls) {{
      const st=path.getAttribute('data-src-table'), dt=path.getAttribute('data-dst-table');
      if(st!==tid&&dt!==tid) path.setAttribute('stroke-opacity','0.03');
    }}
  }}
  function clearHighlight() {{
    if(showAllMode) return;
    allCards.forEach(c=>c.classList.remove('highlight','dimmed'));
    allCols.forEach(c=>c.classList.remove('highlight','dimmed'));
    allPaths.forEach(p=>{{ p.setAttribute('stroke-opacity','0.07'); p.setAttribute('stroke-width','1.5'); }});
    tooltip.style.display='none';
  }}
  allCols.forEach(col=>{{
    col.addEventListener('mouseenter',(evt)=>{{
      if(showAllMode) return;
      const card=col.closest('.table-card'); if(!card) return;
      clearHighlight(); highlightColumn(card.dataset.table,col.dataset.col);
      const edges=edgeEls.filter(({{edge}})=>(edge.st===card.dataset.table&&edge.sc===col.dataset.col)||(edge.dt===card.dataset.table&&edge.dc===col.dataset.col));
      if(edges.length>0) {{
        let html=''; for (const {{edge}} of edges) {{ const ei=classifyEdge(edge); html+='<div class="tt-row"><span>'+edge.sc+'</span><span class="tt-arrow">→</span><span>'+edge.dc+'</span><span class="tt-badge '+ei.css+'">'+ei.label+'</span></div>'; }}
        tooltip.innerHTML='<div class="tt-title">'+col.dataset.col+' lineage</div>'+html;
        tooltip.style.display='block';
        const dR=document.getElementById('diagram').getBoundingClientRect();
        tooltip.style.left=(evt.clientX-dR.left+16)+'px'; tooltip.style.top=(evt.clientY-dR.top-10)+'px';
      }}
    }});
    col.addEventListener('mouseleave',clearHighlight);
  }});
  document.querySelectorAll('.table-header').forEach(hdr=>{{
    hdr.addEventListener('mouseenter',()=>{{ if(showAllMode)return; const c=hdr.closest('.table-card'); if(!c)return; clearHighlight(); highlightTable(c.dataset.table); }});
    hdr.addEventListener('mouseleave',clearHighlight);
  }});
  const btnAll=document.getElementById('btn-show-all');
  btnAll.addEventListener('click',()=>{{
    showAllMode=!showAllMode; btnAll.classList.toggle('active',showAllMode);
    if(showAllMode) {{ allCards.forEach(c=>c.classList.remove('highlight','dimmed')); allCols.forEach(c=>c.classList.remove('highlight','dimmed')); allPaths.forEach(p=>{{ p.setAttribute('stroke-opacity','0.45'); p.setAttribute('stroke-width','1.5'); }}); }}
    else clearHighlight();
  }});
  document.querySelectorAll('.edge-legend-item').forEach(item=>{{
    item.addEventListener('click',()=>{{ const t=item.dataset.table; if(!t)return; showAllMode=false; btnAll.classList.remove('active'); clearHighlight(); highlightTable(t); }});
  }});
}}

function computeMetrics(edgeEls) {{
  const gE={{'raw-clean':[],'clean-dw':[]}};
  for (const {{edge,y1,y2}} of edgeEls) {{ const g=edge.sl+'-'+edge.dl; if(gE[g])gE[g].push({{y1,y2}}); }}
  function cx(edges) {{ let c=0; for(let i=0;i<edges.length;i++) for(let j=i+1;j<edges.length;j++) {{ const a=edges[i],b=edges[j]; if((a.y1<b.y1&&a.y2>b.y2)||(a.y1>b.y1&&a.y2<b.y2))c++; }} return c; }}
  const rc=cx(gE['raw-clean']),cd=cx(gE['clean-dw']);
  const lens=edgeEls.map(({{y1,y2}})=>Math.abs(y2-y1));
  const txTypes={{}};
  for (const e of EDGES) {{ const i=classifyEdge(e); txTypes[i.type]=(txTypes[i.type]||0)+1; }}
  return {{ crossings:rc+cd, rawCleanCrossings:rc, cleanDwCrossings:cd, totalEdges:EDGES.length,
    tablePairs:new Set(EDGES.map(e=>e.st+'→'+e.dt)).size,
    avgEdgeLength:lens.reduce((a,b)=>a+b,0)/lens.length, maxEdgeLength:Math.max(...lens), transformTypes:txTypes }};
}}

function showMetrics(m) {{
  const p=document.getElementById('metrics-panel'),c=document.getElementById('metrics-content');
  const cc=m.crossings===0?'good':m.crossings<50?'warn':'bad';
  const txR=Object.entries(m.transformTypes).sort((a,b)=>b[1]-a[1]).map(([t,c])=>'<div class="metric-row"><span class="metric-label">'+t+'</span><span class="metric-value">'+c+'</span></div>').join('');
  c.innerHTML='<div class="metric-section-title">Edge Crossings</div>'
    +'<div class="metric-row"><span class="metric-label">Total crossings</span><span class="metric-value '+cc+'">'+m.crossings+'</span></div>'
    +'<div class="metric-row"><span class="metric-label">Raw → Clean</span><span class="metric-value">'+m.rawCleanCrossings+'</span></div>'
    +'<div class="metric-row"><span class="metric-label">Clean → DW</span><span class="metric-value">'+m.cleanDwCrossings+'</span></div>'
    +'<div class="metric-section-title">Edge Statistics</div>'
    +'<div class="metric-row"><span class="metric-label">Total edges</span><span class="metric-value">'+m.totalEdges+'</span></div>'
    +'<div class="metric-row"><span class="metric-label">Table pairs</span><span class="metric-value">'+m.tablePairs+'</span></div>'
    +'<div class="metric-row"><span class="metric-label">Avg edge length</span><span class="metric-value">'+m.avgEdgeLength.toFixed(0)+'px</span></div>'
    +'<div class="metric-row"><span class="metric-label">Max edge length</span><span class="metric-value">'+m.maxEdgeLength.toFixed(0)+'px</span></div>'
    +'<div class="metric-section-title">Transformations</div>'+txR;
}}

window.addEventListener('load',()=>{{
  const el=document.getElementById('edge-legend');
  for (const [tid,sn] of Object.entries(TABLE_SHORT_NAMES)) {{
    const c=TABLE_COLORS[tid], d=document.createElement('div');
    d.className='edge-legend-item'; d.dataset.table=tid;
    d.innerHTML='<div class="edge-legend-swatch" style="background:'+c+'"></div>'+sn;
    el.appendChild(d);
  }}
  const edgeEls=drawEdges(); setupInteraction(edgeEls);
  const m=computeMetrics(edgeEls); showMetrics(m);
  document.getElementById('btn-metrics').addEventListener('click',()=>{{
    document.getElementById('metrics-panel').classList.toggle('visible');
    document.getElementById('btn-metrics').classList.toggle('active');
  }});
  window.qualityReport=()=>{{ console.table({{'Total crossings':m.crossings,'Raw→Clean':m.rawCleanCrossings,'Clean→DW':m.cleanDwCrossings,'Edges':m.totalEdges,'Pairs':m.tablePairs,'Avg length':Math.round(m.avgEdgeLength),'Max length':Math.round(m.maxEdgeLength)}}); return m; }};
  console.log('[lineage] '+m.totalEdges+' edges, '+m.crossings+' crossings, '+m.tablePairs+' pairs');
}});
</script>
</body>
</html>
"""


def try_screenshot(html_path: Path, png_path: Path) -> bool:
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        return False

    with sync_playwright() as pw:
        browser = pw.chromium.launch()
        page = browser.new_page(viewport={"width": 1800, "height": 900})
        page.goto(f"file://{html_path.resolve()}")
        page.wait_for_load_state("load")
        page.wait_for_timeout(500)
        page.click("#btn-show-all")
        page.wait_for_timeout(200)
        page.screenshot(path=str(png_path), full_page=True)
        browser.close()

    print(f"PNG written to {png_path}")
    return True


def main() -> None:
    print(f"Loading clean-layer metadata from {CLEAN_META}")
    clean_tables = load_tables_from_dir(CLEAN_META)
    print(f"Loading DW metadata from {DW_META}")
    dw_tables = load_tables_from_dir(DW_META)

    all_tables = clean_tables + dw_tables
    print(f"Loaded {len(all_tables)} table(s)")

    nodes, edges = build_graph(all_tables)
    print(f"Graph: {len(nodes)} node(s), {len(edges)} edge(s)")

    ordered_layers = barycenter_order(nodes, edges)
    for layer_name, layer_nodes in ordered_layers.items():
        order_str = ", ".join(n.table for n in layer_nodes)
        print(f"  {layer_name}: {order_str}")

    html = build_html(nodes, edges, ordered_layers)
    OUTPUT_HTML.write_text(html, encoding="utf-8")
    print(f"HTML written to {OUTPUT_HTML}")

    if not try_screenshot(OUTPUT_HTML, OUTPUT_PNG):
        print(
            "PNG skipped — Playwright not installed.\n"
            "To generate a PNG for markdown embedding:\n"
            "  pip install playwright && playwright install chromium\n"
            "  python dags/tech_platform/dw_devlake/generate_lineage_diagram.py"
        )


if __name__ == "__main__":
    main()
