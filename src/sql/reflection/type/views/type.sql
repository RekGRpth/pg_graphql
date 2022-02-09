create view graphql.type as
    select
        id,
        type_kind,
        meta_kind,
        is_builtin,
        constant_name,
        name,
        entity,
        graphql_type_id,
        enum,
        description
    from
        graphql._type t
    where
        t.entity is null
        or case
            when meta_kind in ('Node', 'Edge', 'Connection', 'OrderBy')
                then
                    pg_catalog.has_any_column_privilege(
                        current_user,
                        t.entity,
                        'SELECT'
                    )
            when meta_kind = 'FilterEntity'
                then
                    pg_catalog.has_any_column_privilege(
                        current_user,
                        t.entity,
                        'SELECT'
                    ) or pg_catalog.has_any_column_privilege(
                        current_user,
                        t.entity,
                        'UPDATE'
                    ) or pg_catalog.has_any_column_privilege(
                        current_user,
                        t.entity,
                        'DELETE'
                    )
            when meta_kind = 'CreateNode'
                then
                    pg_catalog.has_any_column_privilege(
                        current_user,
                        t.entity,
                        'INSERT'
                    ) and pg_catalog.has_any_column_privilege(
                        current_user,
                        t.entity,
                        'SELECT'
                    )
            when meta_kind = 'UpdateNode'
                then
                    pg_catalog.has_any_column_privilege(
                        current_user,
                        t.entity,
                        'UPDATE'
                    ) and pg_catalog.has_any_column_privilege(
                        current_user,
                        t.entity,
                        'SELECT'
                    )
            else true
        end;
