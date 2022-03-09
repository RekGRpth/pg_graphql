create materialized view graphql.relationship as
    with rels as materialized (
        select
            const.conname as constraint_name,
            const.oid as constraint_oid,
            e.entity as local_entity,
            array_agg(local_.attname::text order by l.col_ix asc) as local_columns,
            case graphql.column_set_is_unique(e.entity, array_agg(local_.attname::text))
                when true then 'ONE'
                else 'MANY'
            end::graphql.cardinality as local_cardinality,
            const.confrelid::regclass as foreign_entity,
            array_agg(ref_.attname::text order by r.col_ix asc) as foreign_columns,
            'ONE'::graphql.cardinality as foreign_cardinality,
            com.comment_,
            graphql.comment_directive(com.comment_) ->> 'local_name' as local_name_override,
            graphql.comment_directive(com.comment_) ->> 'foreign_name' as foreign_name_override
        from
            graphql.entity e
            join pg_constraint const
                on const.conrelid = e.entity
            join pg_attribute local_
                on const.conrelid = local_.attrelid
                and local_.attnum = any(const.conkey)
            join pg_attribute ref_
                on const.confrelid = ref_.attrelid
                and ref_.attnum = any(const.confkey),
            unnest(const.conkey) with ordinality l(col, col_ix)
            join unnest(const.confkey) with ordinality r(col, col_ix)
                on l.col_ix = r.col_ix,
            lateral (
                select pg_catalog.obj_description(const.oid, 'pg_constraint') body
            ) com(comment_)
        where
            const.contype = 'f'
        group by
            e.entity,
            com.comment_,
            const.oid,
            const.conname,
            const.confrelid
    )
    select
        constraint_name,
        local_entity,
        local_columns,
        local_cardinality,
        foreign_entity,
        foreign_columns,
        foreign_cardinality,
        foreign_name_override
    from
        rels
    union all
    select
        constraint_name,
        foreign_entity,
        foreign_columns,
        foreign_cardinality,
        local_entity,
        local_columns,
        local_cardinality,
        local_name_override
    from
        rels;
