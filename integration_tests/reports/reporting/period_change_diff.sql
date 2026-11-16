select month, sum(amount) as amount, {{ dre_utils.period_change('sum(amount)', 'month', kind='diff') }} as change from sales {{ dre_utils.group_by(1) }} order by month
