select * from ({{ dre_utils.union_relations(['north', 'south']) }}) u order by id
