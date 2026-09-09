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
  dependent stage's types will resolve — build layers in order. Node-level annotations
  (`@preSQL`, `@postSQL`, `@tests`, non-default `@insertStrategy`) do not render locally with
  this `coa` CLI version even when the node type declares a matching config `attributeName` —
  verified empirically 2026-08-25. Only column-level annotations (`@isBusinessKey`,
  `@description(...)`, etc.) work. Any node-level config beyond the SELECT itself must be set
  via the `coa serve` UI after the node is created, and won't be tracked in the `.sql` file.
- **Facts:** use the **V1 Fact** node type (`fileVersion: 1`, `.yml`, node type id `Fact`).
- **Dimensions:** use the **V1 Dimension** node type (`fileVersion: 1`, `.yml`, node type id
  `Dimension`). Always choose a good **business key** (required for dims).
- For facts and dims I (the user) will choose the remaining parameters in the **`coa serve`**
  interface — set up the node/business key, but leave other config for me to pick.

## Node building conventions

- **Always stage before modelling:** every fact or dim must have **at least one stage** node
  upstream. Use **more than one stage** when there are a lot of transformations.
- **One concern per stage:** do **not** combine column-level transformations, JSON
  flattening, and aggregations in the same node — split them across separate stages.
- **Keep facts and dims clean:** they are for **modelling logic only**. Never put
  transformations in a fact or dim unless absolutely necessary — do that work in the
  upstream stage(s).

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
