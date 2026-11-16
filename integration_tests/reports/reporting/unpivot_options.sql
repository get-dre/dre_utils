select * from ({{ dre_utils.unpivot('north', exclude=['id', 'name'], name_column='field', value_column='val', cast_to='double') }}) u order by id, field
