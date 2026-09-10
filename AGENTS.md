# AGENTS.md

Project-level instructions and context for the Cursor agent working in this repo.

## Coalesce workflow

There are two tools in play, used for different things:

- **Coalesce Transform MCP** — use for **inspection / read-only** context: looking at
  workspaces, environments, projects, nodes, and runs, and for triggering/monitoring
  refresh runs. When I ask you to **inspect the workspace or environments** (or check
  config, nodes, runs, etc.), use the MCP.
  - **Default workspace:** use **workspace `17`** ("Scott's Workspace - OLD") for all
    Coalesce Transform MCP actions unless I explicitly say otherwise.
  - Project: **Logistics (NY Taxi)** (`ecccd014-e1ff-4bbc-9b91-0061ca7abfbc`), Snowflake.
  - When a tool needs a `workspaceID`, use `17`.

- **`coa` CLI** — use for **building**. Build node files locally, then apply them with the
  `coa` CLI. The Coalesce MCP guidance helps drive which `coa` CLI commands to run.
  - To discover what the CLI can do, run **`coa describe`** (and drill into topics, e.g.
    `coa describe sql-format`, `coa describe concepts`, `coa describe selectors`).
  - **Node file format:** files live in `nodes/` named `<LOC>-<NAME>.<ext>`
    (e.g. `SILVER-STG_VENDOR.sql`). Which format/node type to use depends on the node
    role — see "Node type preferences" below.
  - **Core build loop (one node at a time):**
    1. Define the node file in `nodes/`.
    2. `coa create --include "{ NODE_NAME }"` — DDL (creates table/view).
    3. `coa run --include "{ NODE_NAME }"` — DML (populates data).
    4. Iterate to the next downstream node.
  - Use `--dry-run` to preview and `--verbose` to see SQL before executing.
  - `coa validate` catches schema/config issues offline; `coa doctor` checks auth and
    warehouse access.

## Node type preferences

- **Stage nodes:** always use the **V2 SQL Stage** node type (`fileVersion: 2`, `.sql` file,
  `@nodeType("6")` — "SQL Stage v2", under `nodeTypes/SQLStagev2-6/`). Look up the node type id
  under `nodeTypes/` if unsure. Do NOT use node type `426` ("Copy of Stage") — that's a
  workspace-local duplicate, not the real SQL Stage v2. Column types resolve via a live
  warehouse `DESCRIBE` at create/run time, so upstream dependencies must exist before a
  dependent stage's types will resolve — build layers in order.
  - **Column-level `@tests(...)` annotations work** on SQL Stage v2 and are the recommended way
    to add data quality checks that stay in version control. Syntax:
    ```sql
    VENDOR_ID  @isBusinessKey @tests("SELECT * FROM {{ this }} WHERE VENDOR_ID IS NULL", "SELECT VENDOR_ID, COUNT(*) FROM {{ this }} GROUP BY VENDOR_ID HAVING COUNT(*) > 1"),
    ```
    Each parameter becomes a separate test stage in `coa run`. A test **fails** if the query
    returns any rows. Use `{{ this }}` to reference the node's own table. Multiple tests on one
    column go as comma-separated parameters in a single `@tests(...)` — repeating the
    annotation is silently ignored; only the first is kept. `@testsEnabled` must appear at node
    level for tests to execute.
  - **Node-level `@tests(...)` does NOT render** in the current SQL Stage v2 definition — the
    `tests` config item is not declared, so the annotation is silently dropped. Node-level
    custom SQL tests still require `coa serve`.
  - **`@insertStrategy("TRUNCATE")`** does not work — the definition only allows `INSERT`,
    `UNION`, `UNION ALL`. The `truncateBefore` toggle is declared but not consumed by the run
    template. Stages default to `INSERT INTO` (append). A `coa create` before `coa run`
    recreates the table empty, which is the workaround for a clean reload.
  - **`@preSQL`, `@postSQL`** work as node-level parameterized annotations.
  - Other node-level config beyond what's listed here must be set via `coa serve` and won't be
    tracked in the `.sql` file.
  - **WARNING on Fact v2 and Dimension v2:** column-level `@tests(...)` annotations **break**
    these node types with `'str object' has no attribute 'name'`. Their run templates expect a
    different test object shape (`{name, templateString}`) than the annotation parser produces
    (`{parameters: [...]}`). Do NOT use `@tests(...)` on Fact v2 (`10`) or Dimension v2 (`8`)
    nodes — use `coa serve` for those.
- **ODS nodes (`ODS_`):** use the **V2 Persistent Stage** node type (`fileVersion: 2`, `.sql`
  file, `@nodeType("9")`, under `nodeTypes/PersistentStagev2-9/`). Accumulates across runs via
  MERGE — never truncated.
  - `@isBusinessKey` required on the natural key column(s).
  - `@isSystemVersion` and `@isSystemCurrentFlag` must be in the SELECT.
  - System columns (surrogate key, version, current flag, start/end/create/update dates) are
    auto-added by the node type definition.
  - `@isChangeTracking` marks columns that trigger a new version. It has a known template bug
    (ambiguous column names in the SCD2 branch) — if that bites, drop it and accept Type 1
    (merge/upsert) behaviour instead.
- **Facts:** use the **V1 Fact** node type (`fileVersion: 1`, `.yml`, node type id `Fact`).
- **Dimensions:** use the **V1 Dimension** node type (`fileVersion: 1`, `.yml`, node type id
  `Dimension`). Always choose a good **business key** (required for dims).
- For facts and dims I (the user) will choose the remaining parameters in the **`coa serve`**
  interface — set up the node/business key, but leave other config for me to pick.

## Node building conventions

- **Pipeline pattern: Source → Stage(s) → ODS → Business Stage(s) → Dim/Fact**
  - **Stage (`STG_`):** light transformations only — trim, cast, rename, dedup, add audit
    columns. Truncate-and-reload each run.
  - **ODS (`ODS_`):** conformed, deduplicated, incrementally-loaded representation of each
    source entity, MERGEd on the business key. This is where an accurate picture of each
    source gets built, before any modelling. **Every source entity MUST have an ODS node.**
  - **Business Stage(s) (`BIZ_`):** at least one stage between ODS and Dim/Fact where the
    business logic lives — calculations, derived columns, business rules, cross-entity joins.
    Use **multiple stages** when there are different transformation types (see modularity).
  - **Dim/Fact (`DIM_`, `FCT_`):** history tracking and star-schema structure ONLY. Dims track
    history; facts accumulate events. No transformation logic, no business rules.
- **Always stage before a persistent table:** never point an ODS, dim or fact directly at a
  source. Every persistent node has at least one stage upstream of it, and more than one when
  there are a lot of transformations.
- **Modularity — one concern per stage:** do **not** combine different transformation types in
  the same stage node. Split them so the pipeline stays debuggable:
  - JSON / variant flattening → its own stage
  - Column-level transforms (casting, renaming, derivations) → its own stage
  - Aggregations / window functions → its own stage
  - Cross-entity joins / enrichment → its own stage
  - Business rules / calculations → its own stage
- **Keep facts and dims clean:** they are for **building history only**. Never put
  transformation logic in a fact or dim — do that work in the upstream business stage(s).
- **Always load incrementally where possible.** When a source table carries an incremental
  key (`UPDATED_AT`, `LAST_MODIFIED_TS`, `LOAD_DATE` or similar), filter on a high-watermark
  so a run only processes rows changed since the last one — never full-scan a table that
  tells you what changed.
  - ODS nodes: filter on the high-watermark so the MERGE stays cheap.
  - Stages reading append-only / CDC-style sources: resolve latest-version-per-key with
    `QUALIFY ROW_NUMBER() OVER (PARTITION BY <business key> ORDER BY <incremental key> DESC) = 1`.
  - Facts: prefer an incremental `WHERE` on the business date over a full reload.
  - Only fall back to a full refresh when the source genuinely has no reliable change
    indicator, and say so explicitly when you do.
  - Caveat: node-level config does not always render locally from the `.sql` file (see the
    stage-node note above), so an incremental filter expressed as node config rather than in
    the SELECT may need setting via `coa serve`. Prefer putting the predicate in the SELECT
    where the node type allows it, so it stays in version control.

## Knowledge lookups (definitions, metrics, policies)

- If I ask you to **look up a definition, metric, policy, term, or anything knowledge-related**,
  use the **Catalog MCP** (`user-catalog`). Its **`search_terms`** tool searches the knowledge
  base for definitions like metrics, policies, business terms, etc.
- Other Catalog MCP tools are available for related lookups (e.g. `search_tables`,
  `search_columns`, `search_dashboards`, `get_field_lineage`, `get_asset_lineage`) — use the
  most fitting one for the question.

## Intent mapping

- If I say **"build"**, **"pipeline"**, **"build node"**, **"update pipeline"**, or similar,
  I mean: author/update node files locally and build them via the **`coa` CLI** (referencing
  the workspace config through the MCP as needed).
- If I say **"inspect"**, "look at the workspace/environments", "check config", "check runs",
  or similar, use the **Coalesce Transform MCP** (read-only) against workspace `17`.
