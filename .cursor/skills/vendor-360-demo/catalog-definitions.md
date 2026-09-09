# Cached catalog definitions

Both terms live in the Catalog MCP (`user-catalog`). Do the live lookup — the calls are at the
bottom of this file, and two in parallel take about two seconds. The text below is the same
content cached verbatim, as a fallback for when the MCP is slow or unavailable, and as the
reference for which parts are worth reading out.

## Vendor Category

- **Term ID:** `7ec56e61-9118-478e-91f3-2b919e8105b8`
- **Name:** `Vendor Category`
- **Slug / link:** `vendor-category-bcb368bc` — https://app.castordoc.com/terms/vendor-category-bcb368bc
- **Owner:** Scott Shellien-Walker (scott.walker@coalesce.io)
- **Last updated:** 2024-06-10

> The "Vendor Category" metric classifies vendors or suppliers into distinct groups based on
> shared characteristics such as product type, service offering, industry, or strategic
> importance. This categorization enables organizations to segment their vendor base for more
> effective management, reporting, and analysis. By grouping vendors into categories, teams can
> streamline procurement processes, monitor spending patterns, assess risk, and optimize vendor
> relationships.
>
> The calculation for category is:
>
> ```
> VENDORS WITH MORE THAN 100 DRIVERS = ENTERPRISE
> VENDORS WITH LESS THAN 100 DRIVERS = COMMERCIAL
> ```
>
> **Things to be careful about:** Be cautious when assigning vendors to categories, as
> misclassification can lead to inaccurate reporting, skewed analysis, or suboptimal
> decision-making. Ensure that the criteria for categorization are clearly defined and
> consistently applied.

**Two genuine ambiguities to call out on stage** — this is the most valuable moment in the
whole demo, because it shows the agent reading the definition rather than pattern-matching a
column name:

1. The definition says "drivers", not "active drivers". `BRONZE.DRIVERS` carries an `IS_ACTIVE`
   flag, and `BRONZE.VENDOR_DETAILS` carries a separate declared `DRIVERS` count. Three
   candidate numerators, one definition.
2. "More than 100" and "less than 100" leave exactly 100 unclassified.

Resolution baked into the build: `COUNT_IF(IS_ACTIVE)`, with `>= 100` as ENTERPRISE. The
declared count is carried alongside as `DRIVER_COUNT_DECLARED` for reconciliation, and the
boundary choice is written into the column description so the decision is discoverable in
lineage rather than buried in SQL.

## Fare Revenue Per Mile

- **Term ID:** `5581674e-fc41-4aec-977d-18f4fe387545`
- **Name:** `Fare Revenue Per Mile ` (note the trailing space in the catalog record)
- **Slug / link:** `fare-revenue-per-mile-aafc9b24` — https://app.castordoc.com/terms/fare-revenue-per-mile-aafc9b24
- **Owner:** Austin Banta (austin.banta@coalesce.io)

> **Overview.** Fare Revenue per Mile measures how much base fare revenue is generated for every
> mile traveled across all trips. It is a core yield efficiency metric, reflecting the
> revenue-generating performance of the network on a distance-normalized basis.
>
> **Formula:** `SUM(fare_revenue) / SUM(trip_distance)`
> **Unit:** Currency per mile (e.g. $/mi)
> **Aggregation:** Both the numerator and denominator are summed independently before dividing —
> this is a ratio of totals, not an average of per-trip ratios.
> **Grain:** Typically computed at the fleet, market, or time-period level.
>
> **Included in `fare_revenue`:** base fare charged to the rider; distance- or time-based fare
> components; promotional fare amounts where the fare itself was reduced at checkout.
>
> **Not included in `fare_revenue`:** taxes; platform or booking fees; tolls or surcharges passed
> through to the rider; tips; cancellation or no-show fees; any other non-fare line items.
>
> *Why this matters: taxes and fees flow through the platform but are not revenue the business
> earns from the act of transportation. Including them would inflate the metric and obscure the
> underlying pricing performance.*
>
> **Ratio of totals vs. average of ratios.** The metric is `SUM(fare) / SUM(miles)`, not
> `AVG(fare_per_mile per trip)`. These differ whenever trip lengths are not uniform. Ratio of
> totals gives longer trips proportionally more weight, which is the correct behaviour.
>
> **Short-trip distortion.** Short trips have higher fare-per-mile rates due to base fare
> minimums, so trip-mix shifts move the metric even when pricing has not changed. Always read
> average trip distance alongside it.

**How this lands in the build:** `FARE_AMOUNT` is the only column that matches the inclusion
list — `TOTAL_AMOUNT` bundles tips, tolls and surcharges, so it is the wrong numerator. Voided
trips are excluded from both numerator and denominator. Every ratio is divided exactly once at
its final grain, and the additive numerator and denominator are always carried alongside it so
downstream consumers can re-aggregate without averaging an average.

## The lookup calls

Two `user-catalog` / `search_terms` calls, issued in parallel in a single message. The name filter
is a relevance hint rather than a hard filter, so select the result by `id`, not by position —
Vendor Category comes back second on its own query.

```json
{ "query": "vendor category", "optionalFilters": { "name": "Vendor Category" },
  "truncate_description": false, "limit": 3 }
```

```json
{ "query": "fare revenue per mile", "optionalFilters": { "name": "Fare Revenue Per Mile" },
  "truncate_description": false, "limit": 3 }
```
