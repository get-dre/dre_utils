# dre_utils

Reusable macros for [DRE](https://github.com/get-dre/dre) reports: select all but a few columns,
pivot values into columns, and run standard data tests, in SQL that works on any database DRE
reads from.

Dates and periods (`run.date.prev_month`, `period('mtd')`, timezones) are built into DRE itself;
see [DRE's template docs](https://github.com/get-dre/dre/blob/master/docs/templates.md).

## Install

Add the package to your project's `packages.yml` (or `dependencies.yml`) and run `dre deps`:

```yaml
packages:
  - git: https://github.com/get-dre/dre_utils.git
    revision: v0.1.0    # a tag, branch or commit
```

Call its macros through the package's name: `{{ dre_utils.star(...) }}`, and declare its data
tests the same way, e.g. `dre_utils.not_null`.

The data tests need DRE with data-test support, which no release has yet: install DRE from a
commit of the `dre` repository (see [Building from source](https://github.com/get-dre/dre/blob/master/docs/building-from-source.md))
until a release includes it.

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
error case against `errors.txt`; it then runs the data tests with `dre test`, checks each one's
failure count, and installs the package macros from a temporary local Git repository. A separate
report checks a local `not_null` pass and a source `not_empty` failure from that installation.
It needs `dre` on the `PATH` (or `DRE=...`) and the DuckDB and csv plugins (`dre deps`
in `integration_tests/` installs them). The Git copy goes in a temporary folder, removed after it.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[Apache-2.0](LICENSE).
