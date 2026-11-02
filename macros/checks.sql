{#- Each test returns failure rows; zero rows is a pass. Column names are quoted with
    `quote_identifier` for the report's database, so a test works on any database DRE reads. -#}

{#- not_null(relation, column_name): a row per row of `relation` whose `column_name` is null. -#}
{% test not_null(relation, column_name) %}
select * from {{ relation }} where {{ dre_utils.quote_identifier(column_name) }} is null
{% endtest %}

{#- unique(relation, column_name): a row per value of `column_name` that appears more than once in
    `relation`, with its count. -#}
{% test unique(relation, column_name) %}
select {{ dre_utils.quote_identifier(column_name) }}, count(*) as duplicate_count
from {{ relation }}
group by {{ dre_utils.quote_identifier(column_name) }}
having count(*) > 1
{% endtest %}

{#- not_empty(relation): a row when `relation` has no rows. -#}
{% test not_empty(relation) %}
select 1 as missing_data where not exists (select 1 from {{ relation }})
{% endtest %}

{#- non_negative(relation, column_name): a row per row of `relation` whose `column_name` is below
    zero. -#}
{% test non_negative(relation, column_name) %}
select * from {{ relation }} where {{ dre_utils.quote_identifier(column_name) }} < 0
{% endtest %}

{#- totals_match(relation, expected, column_name, expected_column=none, tolerance=0)

    A test reconciling a total: the sum of `relation`'s `column_name` against the sum of
    `expected`'s `expected_column` (by default the same name). One row, with both sums and their
    difference, only when they differ by more than `tolerance` (an absolute amount; give
    `expected_column` when the detail and summary name their column differently). Both sums are
    0 for no rows, so two empty relations match. Give the earlier query's result as `expected`
    (the test's `query_results`), or a source relation for a source test. -#}
{% test totals_match(relation, expected, column_name, expected_column=none, tolerance=0) %}
select actual.total as actual_total, expected_total.total as expected_total, actual.total - expected_total.total as difference
from (select coalesce(sum({{ dre_utils.quote_identifier(column_name) }}), 0) as total from {{ relation }}) actual
cross join (select coalesce(sum({{ dre_utils.quote_identifier(expected_column if expected_column is not none else column_name) }}), 0) as total from {{ expected }}) expected_total
where abs(actual.total - expected_total.total) > {{ tolerance }}
{% endtest %}