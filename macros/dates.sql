{#- date_spine(start_date, end_date, datepart='day')

    A query with one row per period from `start_date` up to, but not including, `end_date`, in
    a column named `date_<datepart>` (`date_day`, `date_month`, ...). `datepart` is `day`,
    `week`, `month`, `quarter` or `year`. The dates are SQL expressions: `"'2026-01-01'"`,
    `"current_date"`. Use it as a subquery, e.g. to left join facts onto every day. It makes at
    most 10,000 periods. Dispatched for date arithmetic: DuckDB and Postgres add an interval,
    everything else (Snowflake, Databricks) uses `dateadd`. -#}
{% macro date_spine(start_date, end_date, datepart='day') -%}
{%- if datepart not in ['day', 'week', 'month', 'quarter', 'year'] -%}
{{ raise_error("dre_utils.date_spine: `datepart` must be day, week, month, quarter or year, not '" ~ datepart ~ "'") }}
{%- endif -%}
select date_{{ datepart }} from (
  select {{ _date_add(start_date, datepart, "(a.n + b.n * 10 + c.n * 100 + d.n * 1000)") }} as date_{{ datepart }} from
  (select 0 as n union all select 1 union all select 2 union all select 3 union all select 4 union all select 5 union all select 6 union all select 7 union all select 8 union all select 9) a
  cross join (select 0 as n union all select 1 union all select 2 union all select 3 union all select 4 union all select 5 union all select 6 union all select 7 union all select 8 union all select 9) b
  cross join (select 0 as n union all select 1 union all select 2 union all select 3 union all select 4 union all select 5 union all select 6 union all select 7 union all select 8 union all select 9) c
  cross join (select 0 as n union all select 1 union all select 2 union all select 3 union all select 4 union all select 5 union all select 6 union all select 7 union all select 8 union all select 9) d
) spine where date_{{ datepart }} < cast({{ end_date }} as date)
{%- endmacro %}

{#- `start` plus `n` periods, as a date. -#}
{% macro _date_add(start, datepart, n) -%}
{{ dispatch('_date_add', 'dre_utils')(start, datepart, n) }}
{%- endmacro %}

{% macro default___date_add(start, datepart, n) -%}
dateadd({{ datepart }}, {{ n }}, cast({{ start }} as date))
{%- endmacro %}

{% macro duckdb___date_add(start, datepart, n) -%}
cast(cast({{ start }} as date) + {{ n }} * interval '{{ "3 month" if datepart == "quarter" else "1 " ~ datepart }}' as date)
{%- endmacro %}

{% macro postgres___date_add(start, datepart, n) -%}
{{ duckdb___date_add(start, datepart, n) }}
{%- endmacro %}
