{#- A list or a string as a comma-separated string. -#}
{% macro _csv(x) -%}
{{ x if x is string else (x | join(', ')) }}
{%- endmacro %}

{#- The database's text type: `varchar`, or `string` on Databricks, which wants a length on varchar. -#}
{% macro _string_type() -%}
{{ dispatch('_string_type', 'dre_utils')() }}
{%- endmacro %}

{% macro default___string_type() -%}varchar{%- endmacro %}

{% macro databricks___string_type() -%}string{%- endmacro %}

{#- unpivot(relation, exclude=[], name_column='name', value_column='value', cast_to=none)

    A query turning columns into rows: one `select` per column of `relation` not in `exclude`,
    joined with `union all`, so it works on any database. Each row keeps the `exclude` columns
    (matched case-insensitively; a name that isn't a column is an error), then holds the column's
    name in `name_column` and its value in `value_column`, cast to `cast_to` (default: the
    database's text type) so columns of different types can share one column. Use it as a
    subquery: `from ({{ dre_utils.unpivot('t', exclude=['id']) }}) u`. -#}
{% macro unpivot(relation, exclude=[], name_column='name', value_column='value', cast_to=none) -%}
{%- if exclude is string -%}{%- set exclude = [exclude] -%}{%- endif -%}
{%- set cols = columns(relation) -%}
{%- set known = cols | map(attribute='name') | map('lower') | list -%}
{%- set skip = exclude | map('lower') | list -%}
{%- for e in exclude if (e | lower) not in known -%}
{{ raise_error("dre_utils.unpivot: `" ~ e ~ "` in `exclude` isn't a column of " ~ relation ~ "; its columns are " ~ (cols | map(attribute='name') | join(', '))) }}
{%- endfor -%}
{%- set ns = namespace(keep=[], rest=[]) -%}
{%- for c in cols -%}
{%- if (c.name | lower) in skip -%}{%- set ns.keep = ns.keep + [quote_identifier(c.name)] -%}
{%- else -%}{%- set ns.rest = ns.rest + [c.name] -%}{%- endif -%}
{%- endfor -%}
{%- if not ns.rest -%}
{{ raise_error("dre_utils.unpivot: `exclude` leaves no columns of " ~ relation ~ " to unpivot") }}
{%- endif -%}
{%- set type = cast_to if cast_to else _string_type() -%}
{%- for name in ns.rest -%}
{%- if not loop.first %}
union all
{% endif -%}
select {% for k in ns.keep %}{{ k }}, {% endfor %}{{ string_literal(name) }} as {{ quote_identifier(name_column) }}, cast({{ quote_identifier(name) }} as {{ type }}) as {{ quote_identifier(value_column) }} from {{ relation }}
{%- endfor -%}
{%- endmacro %}

{#- safe_divide(numerator, denominator): `numerator / nullif(denominator, 0)`: null, not an
    error, when the denominator is zero. The arguments are SQL expressions. -#}
{% macro safe_divide(numerator, denominator) -%}
{{ numerator }} / nullif({{ denominator }}, 0)
{%- endmacro %}

{#- group_by(n): `group by 1, 2, ..., n`. -#}
{% macro group_by(n) -%}
{%- if n is not number or n < 1 or n != n | int -%}
{{ raise_error("dre_utils.group_by: `n` must be a whole number of at least 1, not " ~ n) }}
{%- endif -%}
group by {{ range(1, (n | int) + 1) | join(', ') }}
{%- endmacro %}

{#- surrogate_key(columns): `md5` of the columns cast to text, each null replaced by a fixed
    marker, joined with `-`: the same values give the same key, and a null differs from an empty
    string. `columns` is a list of SQL expressions (a column name, or something like
    `lower(email)`; quote names that need it). -#}
{% macro surrogate_key(columns) -%}
{%- if columns is string -%}{%- set columns = [columns] -%}{%- endif -%}
{%- if not columns -%}
{{ raise_error("dre_utils.surrogate_key: give at least one column") }}
{%- endif -%}
{%- set ns = namespace(parts=[]) -%}
{%- for c in columns -%}
{%- set ns.parts = ns.parts + ["coalesce(cast(" ~ c ~ " as " ~ _string_type() ~ "), '_dre_null_')"] -%}
{%- endfor -%}
md5({{ ns.parts | join(" || '-' || ") }})
{%- endmacro %}

{#- pct_of_total(expr, partition_by=none)

    `expr` as a share of its total: `(expr) * 1.0 / nullif(sum(expr) over (...), 0)`. The total
    is over every row of the query, or per `partition_by` (a column, or a list). In a grouped
    query give the aggregate: `pct_of_total('sum(amount)')` is each group's share of all groups.
    A zero total gives null. -#}
{% macro pct_of_total(expr, partition_by=none) -%}
({{ expr }}) * 1.0 / nullif(sum({{ expr }}) over ({% if partition_by %}partition by {{ _csv(partition_by) }}{% endif %}), 0)
{%- endmacro %}

{#- period_change(expr, order_by, partition_by=none, kind='pct')

    `expr` compared with its value on the previous row in `order_by` (within `partition_by`, if
    given), through `lag()`. `kind='pct'` is the change as a ratio (`0.25` for 25% up); `'diff'`
    is the difference. The first row has no previous one, and a previous value of 0 has no
    percentage: both give null. In a grouped query give the aggregate, `expr='sum(amount)'`. -#}
{% macro period_change(expr, order_by, partition_by=none, kind='pct') -%}
{%- if kind not in ['pct', 'diff'] -%}
{{ raise_error("dre_utils.period_change: `kind` must be 'pct' or 'diff', not '" ~ kind ~ "'") }}
{%- endif -%}
{%- set prev = "lag(" ~ expr ~ ") over (" ~ (("partition by " ~ _csv(partition_by) ~ " ") if partition_by else "") ~ "order by " ~ _csv(order_by) ~ ")" -%}
{%- if kind == 'diff' -%}({{ expr }}) - {{ prev }}
{%- else -%}{{ safe_divide("(" ~ expr ~ ") * 1.0", prev) }} - 1
{%- endif -%}
{%- endmacro %}

{#- deduplicate(relation, partition_by, order_by)

    One row per `partition_by` (a column, or a list), the first by `order_by`: `row_number()` in
    a subquery, so it works without `qualify`. Every column of `relation` comes back, and
    nothing else. Use it as a subquery or `from` source. -#}
{% macro deduplicate(relation, partition_by, order_by) -%}
select {% for c in columns(relation) %}{{ quote_identifier(c.name) }}{{ ", " if not loop.last }}{% endfor %} from (
  select t.*, row_number() over (partition by {{ _csv(partition_by) }} order by {{ _csv(order_by) }}) as _dre_row_number from {{ relation }} t
) d where _dre_row_number = 1
{%- endmacro %}

{#- union_relations(relations, source_column='_source')

    The rows of every relation in `relations`, one after the other (`union all`), with their
    columns lined up by name, matched case-insensitively. Columns in the first relation come
    first, then new ones from later relations in order, with the first spelling kept. A relation
    without a column gets `null` for it. `source_column` holds the relation's name as it was
    given. -#}
{% macro union_relations(relations, source_column='_source') -%}
{%- if relations is string -%}{%- set relations = [relations] -%}{%- endif -%}
{%- if not relations -%}
{{ raise_error("dre_utils.union_relations: give at least one relation") }}
{%- endif -%}
{%- set ns = namespace(names=[], lower=[]) -%}
{%- for r in relations -%}
{%- for c in columns(r) if (c.name | lower) not in ns.lower -%}
{%- set ns.names = ns.names + [c.name] -%}{%- set ns.lower = ns.lower + [c.name | lower] -%}
{%- endfor -%}
{%- endfor -%}
{%- for r in relations -%}
{%- set rcols = columns(r) -%}
{%- if not loop.first %}
union all
{% endif -%}
select {% for n in ns.names %}{% set f = namespace(name=none) %}{% for c in rcols if (c.name | lower) == (n | lower) %}{% set f.name = c.name %}{% endfor %}{% if f.name is none %}null{% else %}{{ quote_identifier(f.name) }}{% endif %} as {{ quote_identifier(n) }}, {% endfor %}{{ string_literal(r | string) }} as {{ quote_identifier(source_column) }} from {{ r }}
{%- endfor -%}
{%- endmacro %}
