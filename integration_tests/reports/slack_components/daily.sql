select day, sum(revenue) as revenue, sum(orders) as orders from sales group by day order by day
