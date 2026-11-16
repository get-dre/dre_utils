# dre_utils

Reusable macros for [DRE](https://github.com/get-dre/dre) reports: select all but a few columns,
pivot values into columns, unpivot, union and deduplicate relations, build a date spine, add
reporting helpers (safe division, shares, period changes), and run standard data tests, in SQL
that works on any database DRE reads from.

Dates and periods (`run.date.prev_month`, `period('mtd')`, timezones) are built into DRE itself;
see [DRE's template docs](https://github.com/get-dre/dre/blob/master/docs/templates.md).

## Install

Add the package to your project's `packages.yml` (or `dependencies.yml`) and run `dre deps`:

```yaml
packages:
  - git: https://github.com/get-dre/dre_utils.git
    revision: v0.2.0    # a tag, branch or commit
```

Call its macros through the package's name: `{{ dre_utils.star(...) }}`, and declare its data
tests the same way, e.g. `dre_utils.not_null`.

The ordinary macros work with earlier DRE releases. The data tests require DRE 0.11.0 or later;
the tests run on DRE 0.13.0. The [Slack components](#slack-components) need DRE 0.13.0 and the
`slack` plugin 1.4.0 or later.

## `star`

```sql
select {{ dre_utils.star('crm.customers', except=['ssn', '_etl_ts']) }}
from crm.customers
-- select "id", "name", "email", "created_at" from crm.customers
```

An explicit list of the relation's columns, without the ones in `except`. It works the same on
every database, instead of relying on `* except (...)` / `* exclude (...)`.

| Argument | |
|---|---|
| `relation` | A table, a fully qualified name, a temp table made by an earlier query, or `ref('file')`. |
| `except` | Column names to leave out (a list, or one name), matched case-insensitively. A name that isn't a column is an error, so a renamed column doesn't slip back in. |
| `alias` | Qualify each column: `alias='c'` gives `c."id"`. |
| `prefix`, `suffix` | Rename each column: `prefix='c_'` gives `"id" as "c_id"`. |
| `quote` | Quote column names (default `true`), with `quote_identifier`. |

The columns come from DRE's `columns()`, which asks the database once per relation in each query file.

## `pivot`

```sql
select account,
  {{ dre_utils.pivot('month', relation='ledger', agg='sum', then_value='amount') }}
from ledger group by account
-- sum(case when month = '2026-07' then amount else 0 end) as "2026-07",
-- sum(case when month = '2026-08' then amount else 0 end) as "2026-08"
```

One aggregated column per value, using portable `case when`.

| Argument | |
|---|---|
| `column` | The column whose values become columns. |
| `values` | The values, as a list. Or leave it out and give `relation`: |
| `relation`, `where`, `order_by`, `max` | Read the distinct values of `column` from `relation` (optionally filtered by `where`), ordered by `order_by` (default: the column). More than `max` (default 100) values is an error. |
| `agg` | The aggregate: `sum` (default), `count`, `avg`, `min`, `max`, ... |
| `then_value` | What's aggregated for matching rows (default `1`). |
| `else_value` | What's aggregated for other rows. Default: `0` for `sum`, `null` for everything else, so `count` and `avg` only see matching rows. |
| `prefix`, `suffix` | Around each value to make the column name. |
| `quote` | Quote column names (default `true`). The name is the value as it is: `"2026-07"`. |
| `quote_values` | Quote string values as SQL literals (default `true`); `false` puts them in as written. |
| `null_name` | The column name for a null value (default `null`); it matches with `is null`. |

## `column_values`

```sql
where region in ({{ dre_utils.column_values('sales', 'region', where='active') }})
-- where region in ('apac', 'emea')
```

The distinct values of a column as SQL literals, with the same `where`, `order_by`, `max` and
`quote_values` as `pivot`.

## `unpivot`

```sql
select * from ({{ dre_utils.unpivot('quarterly', exclude=['team']) }}) u
-- select "team", 'q1' as "name", cast("q1" as varchar) as "value" from quarterly
-- union all
-- select "team", 'q2' as "name", cast("q2" as varchar) as "value" from quarterly
```

Columns into rows: one `select` per column, joined with `union all`, so it needs no `unpivot`
keyword. It is a query to use as a subquery.

| Argument | |
|---|---|
| `relation` | A table, a temp table or `ref('file')`; its columns come from `columns()`. |
| `exclude` | Columns to keep as they are on every row (a list, or one name), matched case-insensitively. A name that isn't a column is an error, and so is leaving nothing to unpivot. |
| `name_column`, `value_column` | The two new columns (default `name` and `value`). |
| `cast_to` | The type every value is cast to, so columns of different types fit one column. Default: `varchar` (`string` on Databricks). |

## `union_relations`

```sql
select * from ({{ dre_utils.union_relations(['sales_2025', 'sales_2026']) }}) s
-- select "id" as "id", "total" as "total", null as "channel", 'sales_2025' as "_source" from sales_2025
-- union all
-- select "id" as "id", "total" as "total", "channel" as "channel", 'sales_2026' as "_source" from sales_2026
```

Stacks relations with `union all`, lining the columns up by name, matched case-insensitively.
Columns come in the order they're first seen, with the first spelling. A relation without a
column gets `null` there, uncast, so give such a column a type in the outer query if your
database needs one.

| Argument | |
|---|---|
| `relations` | A list of tables, temp tables or `ref('file')`. |
| `source_column` | A column holding each row's relation, as given (default `_source`). |

## `deduplicate`

```sql
select * from ({{ dre_utils.deduplicate('signups', 'email', 'created_at desc') }}) s
-- select "email", "created_at", "plan" from (
--   select t.*, row_number() over (partition by email order by created_at desc) as _dre_row_number from signups t
-- ) d where _dre_row_number = 1
```

One row per key: the first by `order_by`. It uses `row_number()` in a subquery, not `qualify`,
and returns the relation's columns only. Rows that tie on `order_by` are picked arbitrarily, so
order by something unique when it matters.

| Argument | |
|---|---|
| `relation` | A table, temp table or `ref('file')`. |
| `partition_by` | The key, a column or a list of columns, as SQL. |
| `order_by` | Which row wins, as SQL (`'created_at desc'`; a list also works). |

## `date_spine`

```sql
select * from ({{ dre_utils.date_spine("'2026-01-01'", "'2026-04-01'", 'month') }}) m
-- one row each for 2026-01-01, 2026-02-01 and 2026-03-01, in a column named date_month
```

One row per period from the start up to, not including, the end: a calendar to left join
facts onto, so that quiet periods still show. The dates are SQL expressions, so quote literals
(`"'2026-01-01'"`) or use `current_date`. It makes at most 10,000 periods. DuckDB and Postgres add
an interval; other databases use `dateadd`, which Snowflake and Databricks have. The reporting
macros are tested on DuckDB (in CI), Postgres and Databricks; Snowflake is untested. Integer
division follows the database: Postgres truncates `7 / 2`, so cast one side for a decimal result.

| Argument | |
|---|---|
| `start_date`, `end_date` | SQL expressions for the first date and the exclusive end. |
| `datepart` | `day` (default), `week`, `month`, `quarter` or `year`. Names the column: `date_day`, ... |

## `safe_divide`

```sql
select {{ dre_utils.safe_divide('revenue', 'orders') }} as revenue_per_order from daily
-- select revenue / nullif(orders, 0) as revenue_per_order from daily
```

A division that gives `null` instead of an error when the denominator is 0. Both arguments are SQL
expressions. Integer division follows your database (Postgres truncates `7 / 2`): multiply the
numerator by `1.0` for a fraction.

## `group_by`

```sql
select region, channel, sum(total) from sales {{ dre_utils.group_by(2) }}
-- select region, channel, sum(total) from sales group by 1, 2
```

`group by 1, 2, ..., n`: group by the first `n` columns of the select list. `n` is a whole number
of at least 1.

## `surrogate_key`

```sql
select {{ dre_utils.surrogate_key(['customer_id', 'lower(email)']) }} as customer_key from customers
-- select md5(coalesce(cast(customer_id as varchar), '_dre_null_') || '-' || coalesce(cast(lower(email) as varchar), '_dre_null_')) as customer_key from customers
```

A stable key for a combination of columns: the `md5` of each value as text, with a null replaced by
a marker so that it differs from an empty string, joined with `-`. The columns are SQL expressions,
used as written. On Databricks the text type is `string`.

## `pct_of_total`

```sql
select region, sum(total) as total, {{ dre_utils.pct_of_total('sum(total)') }} as share
from sales group by region
-- (sum(total)) * 1.0 / nullif(sum(sum(total)) over (), 0) as share
```

A value's share of the total, as a ratio (`0.25` for a quarter). With nothing else, the total
covers every row the query returns; with `partition_by` it covers each partition. In a grouped
query give the aggregate, as above; in a row-level query, give a column. A total of 0 gives `null`.

| Argument | |
|---|---|
| `expr` | A SQL expression: a column, or an aggregate like `sum(total)` in a grouped query. |
| `partition_by` | A column or list to take the total within, e.g. each region's share of its own region. |

## `period_change`

```sql
select month, sum(total) as total, {{ dre_utils.period_change('sum(total)', 'month') }} as growth
from sales group by month
-- (sum(total)) * 1.0 / nullif(lag(sum(total)) over (order by month), 0) - 1 as growth
```

How a value changed from the previous row, in `order_by` order, using `lag()`. The first row, and
a previous value of 0 for `pct`, give `null`. As with `pct_of_total`, give the aggregate in a
grouped query. Order by a column in the group, so each row has one previous period.

| Argument | |
|---|---|
| `expr` | A SQL expression. |
| `order_by` | What puts the rows in time order: a column or a list. |
| `partition_by` | Compare within each partition only, e.g. per region. |
| `kind` | `pct` (default): the ratio change, `0.5` for 50% up. `diff`: the difference. Anything else is an error. |

## Data tests

DRE runs a query's `data_tests` after it: each check returns failure rows, and zero rows is a
pass, so a count is the number of failing groups or rows the check found, not necessarily the
number of bad rows in the source. A check's `config` says where it runs, `local` (the default) against the
saved result or `source` against a relation in the query's session, and its severity. Column names
are quoted with `quote_identifier` for the report's database, so a check works on any database DRE
reads from.

```yaml
queries:
  - {query: seed_accounts, tab: false}
  - query: accounts
    data_tests:
      - dre_utils.not_null: {arguments: {column_name: account_id}}
      - dre_utils.unique: {arguments: {column_name: account_id}}
      - dre_utils.not_empty: {}
      - dre_utils.non_negative: {arguments: {column_name: amount}}
      - dre_utils.totals_match:
          query_results: {expected: expected_totals}
          arguments: {column_name: total, tolerance: 0.01}
```

`local` checks read the query's saved result, as `relation`; `source` checks need their relation
given as `arguments.relation`, the name of a table or view the query's session can see.

### `not_null`

`not_null(relation, column_name)`: a failure row per row of `relation` whose `column_name` is null.

### `unique`

`unique(relation, column_name)`: a failure row per value of `column_name` that appears more than
once in `relation`, with its `count(*) as duplicate_count`: one row per duplicated value, however
many rows it has.

### `not_empty`

`not_empty(relation)`: one failure row, `missing_data = 1`, when `relation` has no rows.

### `non_negative`

`non_negative(relation, column_name)`: a failure row per row of `relation` whose `column_name` is
below zero.

### `totals_match`

```yaml
- dre_utils.totals_match:
    query_results: {expected: expected_totals}
    arguments: {column_name: total, expected_column: amount, tolerance: 0.01}
```

`totals_match(relation, expected, column_name, expected_column=none, tolerance=0)` reconciles a
summary against its details: the sum of `column_name` over `relation` against the sum of
`expected_column` over `expected`, by default the same column name. `expected` is a relation too: a
local check's earlier query result, given as `query_results`, or a source check's relation. One
failure row, with `actual_total`, `expected_total` and `difference`, only when the two differ by
more than `tolerance`, an absolute amount in the column's own type. Both sums are 0 with no rows,
so two empty relations match: use `not_empty` when empty data must fail.

## Slack components

Ready-made [Block Kit](https://api.slack.com/block-kit) components for the Slack destination's
`blocks:` list, in `components/slack/`. Name one as `dre_utils/<file>.json` (DRE finds the file
by name in the package; `dre_utils/components/slack/<file>.json` works too) and pass its
arguments in `with:`; each reads the query it names through `results`:

```yaml
destination:
  - profile: team_slack
    channel: "#finance"
    blocks:
      - component: dre_utils/header.json
        with: {text: "Daily KPIs {{ run.date.iso }}"}
      - component: dre_utils/line_chart.json
        keep: last
        with: {query: revenue_by_day, label: day, values: [revenue], title: Revenue}
      - component: dre_utils/fields.json
        with: {query: totals}
```

| Component | Arguments |
|---|---|
| `bar_chart.json`, `line_chart.json`, `area_chart.json` | `query`, `label` (the category column), `value` (a column) or `values` (a list of columns, one series each); optional `series` (a column whose values name the series: long rows pivot into one series per value, categories in first-seen order, using `value`), `title`, `x_label`, `y_label` |
| `pie_chart.json` | `query`, `label`, `value`, `title` |
| `header.json` | `text` |
| `fields.json` | `query`; optional `label` and `value` columns (default: the first two). One `*name*\nvalue` field per row |

Slack's limits (20 points, 12 series, 20-character labels, 2 charts a message) are applied by
the slack plugin, which trims and warns instead of failing; see
[its docs](https://github.com/get-dre/dre/blob/master/docs/plugin-slack.md).
`dre run --preview` prints the rendered blocks, ready for Block Kit Builder: as they are
before the plugin's limit fixes, whose warnings show in a real run.

To change one, copy it into your project, for example to `components/slack/bar_chart.json`, and
name it by its project path: a project's own component wins over a package's. They are plain
JSON with Jinja; print values with `| tojson`.

## `string_literal`

`dre_utils.string_literal("O'Brien")` gives `'O''Brien'`, or `'O\'Brien'` on Databricks, which
doesn't read `''` as an escaped quote (`'O''Brien'` is two literals there, joined into
`OBrien`) and reads backslashes as escapes. `pivot` and `column_values` quote string values with
it. Dispatched like `quote_identifier`.

## `quote_identifier`

`dre_utils.quote_identifier('Order Date')` gives `"Order Date"`, or `` `Order Date` `` on
Databricks. It picks the variant for the report's database through `dispatch()`: define
`<source type>__quote_identifier` in your project's `macros/` to change it.

## Tests

`integration_tests/` is a DRE project that uses this package from `..`. `integration_tests/run.sh`
runs its reports against an in-memory DuckDB and checks each output against `expected/`, and each
error case against `errors.txt`; it previews each Slack component from fixture data and compares
the blocks with `expected/slack__*.json`; it then runs the data tests with `dre test`, checks each one's
failure count, and installs the package macros from a temporary local Git repository. A separate
report checks a local `not_null` pass and a source `not_empty` failure from that installation.
It needs `dre` on the `PATH` (or `DRE=...`) and the DuckDB, csv and slack plugins (`dre deps`
in `integration_tests/` installs them). The Git copy goes in a temporary folder, removed after it.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[Apache-2.0](LICENSE).
