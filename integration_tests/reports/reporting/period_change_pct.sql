select region, month, sum(amount) as amount, {{ dre_utils.period_change('sum(amount)', 'month', partition_by='region') }} as change from sales {{ dre_utils.group_by(2) }} order by region, month
