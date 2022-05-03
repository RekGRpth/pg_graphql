create or replace function graphql.build_connection_query(
    ast jsonb,
    variable_definitions jsonb = '[]',
    variables jsonb = '{}',
    parent_type text = null,
    parent_block_name text = null
)
    returns text
    language plpgsql
as $$
declare
    block_name text = graphql.slug();
    entity regclass = t.entity
        from
            graphql.field f
            join graphql.type t
                on f.type_ = t.name
        where
            f.name = graphql.name_literal(ast)
            and f.parent_type = $4;

    ent alias for entity;

    arguments jsonb = graphql.jsonb_coalesce((ast -> 'arguments'), '[]');

    field_row graphql.field = f from graphql.field f where f.name = graphql.name_literal(ast) and f.parent_type = $4;
    first_ text = graphql.arg_clause(
        'first',
        arguments,
        variable_definitions,
        entity
    );
    last_ text = graphql.arg_clause('last',   arguments, variable_definitions, entity);

    -- If before or after is provided as a variable, and the value of the variable
    -- is explicitly null, we must treat it as though the value were not provided
    cursor_arg_ast jsonb = coalesce(
        graphql.get_arg_by_name('before', graphql.jsonb_coalesce(arguments, '[]')),
        graphql.get_arg_by_name('after', graphql.jsonb_coalesce(arguments, '[]'))
    );
    cursor_literal text = graphql.value_literal(cursor_arg_ast);
    cursor_var_name text = case graphql.is_variable(
            coalesce(cursor_arg_ast,'{}'::jsonb) -> 'value'
        )
        when true then graphql.name_literal(cursor_arg_ast -> 'value')
        else null
    end;
    cursor_var_ix int = graphql.arg_index(cursor_var_name, variable_definitions);

    -- ast
    before_ast jsonb = graphql.get_arg_by_name('before', arguments);
    after_ast jsonb = graphql.get_arg_by_name('after',  arguments);

    -- ordering is part of the cache key, so it is safe to extract it from
    -- variables or arguments
    -- Ex: [{"id": "AscNullsLast"}, {"name": "DescNullsFirst"}]
    order_by_arg jsonb = graphql.arg_coerce_list(
        graphql.arg_to_jsonb(
            graphql.get_arg_by_name('orderBy',  arguments),
            variables
        )
    );
    column_orders graphql.column_order_w_type[] = graphql.to_column_orders(
        order_by_arg,
        entity,
        variables
    );

    filter_arg jsonb = graphql.get_arg_by_name('filter',  arguments);

    total_count_ast jsonb = jsonb_path_query_first(
        ast,
        '$.selectionSet.selections ? ( @.name.value == $name )',
        '{"name": "totalCount"}'
    );

    __typename_ast jsonb = jsonb_path_query_first(
        ast,
        '$.selectionSet.selections ? ( @.name.value == $name )',
        '{"name": "__typename"}'
    );

    page_info_ast jsonb = jsonb_path_query_first(
        ast,
        '$.selectionSet.selections ? ( @.name.value == $name )',
        '{"name": "pageInfo"}'
    );

    edges_ast jsonb = jsonb_path_query_first(
        ast,
        '$.selectionSet.selections ? ( @.name.value == $name )',
        '{"name": "edges"}'
    );

    cursor_ast jsonb = jsonb_path_query_first(
        edges_ast,
        '$.selectionSet.selections ? ( @.name.value == $name )',
        '{"name": "cursor"}'
    );

    node_ast jsonb = jsonb_path_query_first(
        edges_ast,
        '$.selectionSet.selections ? ( @.name.value == $name )',
        '{"name": "node"}'
    );

    __typename_clause text;
    total_count_clause text;
    page_info_clause text;
    node_clause text;
    edges_clause text;

    result text;
begin
    if first_ is not null and last_ is not null then
        perform graphql.exception('only one of "first" and "last" may be provided');
    elsif before_ast is not null and after_ast is not null then
        perform graphql.exception('only one of "before" and "after" may be provided');
    elsif first_ is not null and before_ast is not null then
        perform graphql.exception('"first" may only be used with "after"');
    elsif last_ is not null and after_ast is not null then
        perform graphql.exception('"last" may only be used with "before"');
    end if;

    __typename_clause = format(
        '%L, %L',
        graphql.alias_or_name_literal(__typename_ast),
        field_row.type_
    ) where __typename_ast is not null;

    total_count_clause = format(
        '%L, coalesce(min(%I.%I), 0)',
        graphql.alias_or_name_literal(total_count_ast),
        block_name,
        '__total_count'
    ) where total_count_ast is not null;

    page_info_clause = case
        when page_info_ast is null then null
        else (
            select
                format(
                '%L, jsonb_build_object(%s)',
                graphql.alias_or_name_literal(page_info_ast),
                string_agg(
                    format(
                        '%L, %s',
                        graphql.alias_or_name_literal(pi.sel),
                        case graphql.name_literal(pi.sel)
                            when '__typename' then format('%L', pit.name)
                            when 'startCursor' then format('graphql.first(%I.__cursor order by %I.__page_row_num asc )', block_name, block_name)
                            when 'endCursor' then format('graphql.first(%I.__cursor order by %I.__page_row_num desc)', block_name, block_name)
                            when 'hasNextPage' then format(
                                'coalesce(bool_and(%I.__has_next_page), false)',
                                block_name
                            )
                            when 'hasPreviousPage' then format(
                                'coalesce(bool_and(%s), false)',
                                case
                                    when first_ is not null and after_ast is not null then 'true'
                                    when last_ is not null and before_ast is not null then 'true'
                                    else 'false'
                                end
                            )
                            else graphql.exception_unknown_field(graphql.name_literal(pi.sel), 'PageInfo')
                        end
                    ),
                    ','
                )
            )
        from
            jsonb_array_elements(page_info_ast -> 'selectionSet' -> 'selections') pi(sel)
            join graphql.type pit
                on true
        where
            pit.meta_kind = 'PageInfo'
        )
    end;


    node_clause = case
        when node_ast is null then null
        else (
            select
                format(
                    'jsonb_build_object(%s)',
                    string_agg(
                        format(
                            '%L, %s',
                            graphql.alias_or_name_literal(n.sel),
                            case
                                when gf_s.name = '__typename' then format('%L', gt.name)
                                when gf_s.column_name is not null and gf_s.column_type = 'bigint'::regtype then format(
                                    '(%I.%I)::text',
                                    block_name,
                                    gf_s.column_name
                                )
                                when gf_s.column_name is not null then format('%I.%I', block_name, gf_s.column_name)
                                when gf_s.local_columns is not null and gf_s.meta_kind = 'Relationship.toOne' then
                                    graphql.build_node_query(
                                        ast := n.sel,
                                        variable_definitions := variable_definitions,
                                        variables := variables,
                                        parent_type := gt.name,
                                        parent_block_name := block_name
                                    )
                                when gf_s.local_columns is not null and gf_s.meta_kind = 'Relationship.toMany' then
                                    graphql.build_connection_query(
                                        ast := n.sel,
                                        variable_definitions := variable_definitions,
                                        variables := variables,
                                        parent_type := gt.name,
                                        parent_block_name := block_name
                                    )
                                when gf_s.meta_kind = 'Function' then format('%I.%s', block_name, gf_s.func)
                                else graphql.exception_unknown_field(graphql.name_literal(n.sel), gt.name)
                            end
                        ),
                        ','
                    )
                )
                from
                    jsonb_array_elements(node_ast -> 'selectionSet' -> 'selections') n(sel) -- node selection
                    join graphql.type gt -- return type of node
                        on true
                    left join graphql.field gf_s -- node selections
                        on gt.name = gf_s.parent_type
                        and graphql.name_literal(n.sel) = gf_s.name
                where
                    gt.meta_kind = 'Node'
                    and gt.entity = ent
                    and not coalesce(gf_s.is_arg, false)
        )
    end;

    edges_clause = case
        when edges_ast is null then null
        else (
            select
                format(
                    '%L, coalesce(jsonb_agg(jsonb_build_object(%s)), jsonb_build_array())',
                    graphql.alias_or_name_literal(edges_ast),
                    string_agg(
                        format(
                            '%L, %s',
                            graphql.alias_or_name_literal(ec.sel),
                            case graphql.name_literal(ec.sel)
                                when 'cursor' then format('%I.%I', block_name, '__cursor')
                                when '__typename' then format('%L', gf_e.type_)
                                when 'node' then node_clause
                                else graphql.exception_unknown_field(graphql.name_literal(ec.sel), gf_e.type_)
                            end
                        ),
                        E',\n'
                    )
                )
                from
                    jsonb_array_elements(edges_ast -> 'selectionSet' -> 'selections') ec(sel)
                    join graphql.field gf_e -- edge field
                        on gf_e.parent_type = field_row.type_
                        and gf_e.name = 'edges'
        )
    end;

    -- Error out on invalid top level selections
    perform case
                when gf.name is not null then ''
                else graphql.exception_unknown_field(graphql.name_literal(root.sel), field_row.type_)
            end
        from
            jsonb_array_elements((ast -> 'selectionSet' -> 'selections')) root(sel)
            left join graphql.field gf
                on gf.parent_type = field_row.type_
                and gf.name = graphql.name_literal(root.sel);

    select
        format('
    (
        with xyz_tot as (
            select
                count(1) as __total_count
            from
                %s as %I
            where
                %s
                -- join clause
                and %s
                -- where clause
                and %s
        ),
        -- might contain 1 extra row
        xyz_maybe_extra as (
            select
                %s::text as __cursor,
                row_number() over () as __page_row_num_for_page_size,
                %s -- all requested columns
            from
                %s as %I
            where
                true
                --pagination_clause
                and ((%s is null) or (%s))
                -- join clause
                and %s
                -- where clause
                and %s
            order by
                %s
            limit
                least(%s, 30) + 1
        ),
        xyz as (
            select
                *,
                max(%I.__page_row_num_for_page_size) over () > least(%s, 30) as __has_next_page,
                row_number() over () as __page_row_num
            from
                xyz_maybe_extra as %I
            order by
                %s
            limit
                least(%s, 30)
        )
        select
            jsonb_build_object(%s)
        from
        (
            select
                *
            from
                xyz,
                xyz_tot
            order by
                %s
        ) as %I
    )
    ',
            -- total from
            entity,
            block_name,
            -- total count only computed if requested
            case
                when total_count_ast is null then 'false'
                else 'true'
            end,
            -- total join clause
            coalesce(graphql.join_clause(field_row.local_columns, block_name, field_row.foreign_columns, parent_block_name), 'true'),
            -- total where
            graphql.where_clause(filter_arg, entity, block_name, variables, variable_definitions),
            -- __cursor
            format(
                'graphql.encode(%s)',
                graphql.to_cursor_clause(
                    block_name,
                    column_orders
                )
            ),
            -- enumerate columns
            (
                select
                    coalesce(
                        string_agg(
                            case f.meta_kind
                                when 'Column' then format('%I.%I', block_name, column_name)
                                when 'Function' then format('%s(%I) as %s', f.func, block_name, f.func)
                                else graphql.exception('Unexpected meta_kind in select')
                            end,
                            ', '
                        )
                    )
                from
                    graphql.field f
                    join graphql.type t
                        on f.parent_type = t.name
                where
                    f.meta_kind in ('Column', 'Function') --(f.column_name is not null or f.func is not null)
                    and t.entity = ent
                    and t.meta_kind = 'Node'
            ),
            -- from
            entity,
            block_name,
            -- pagination
            case
                -- no variable or literal. do not restrict
                when cursor_var_ix is null and cursor_literal is null then 'null'
                when cursor_literal is not null then '1'
                else format('$%s', cursor_var_ix)
            end,
            graphql.cursor_where_clause(
                block_name := block_name,
                column_orders := case
                    when last_ is not null then graphql.reverse(column_orders)
                    else column_orders
                end,
                cursor_ := cursor_literal,
                cursor_var_ix := cursor_var_ix
            ),
            -- join
            coalesce(graphql.join_clause(field_row.local_columns, block_name, field_row.foreign_columns, parent_block_name), 'true'),
            -- where
            graphql.where_clause(filter_arg, entity, block_name, variables, variable_definitions),
            -- order
            graphql.order_by_clause(
                block_name,
                case
                    when last_ is not null then graphql.reverse(column_orders)
                    else column_orders
                end
            ),
            -- limit
            coalesce(first_, last_, '30'),
            -- has_next_page block namex
            block_name,
            -- xyz_has_next_page limit
            coalesce(first_, last_, '30'),
            -- xyz
            block_name,
            graphql.order_by_clause(
                block_name,
                case
                    when last_ is not null then graphql.reverse(column_orders)
                    else column_orders
                end
            ),
            coalesce(first_, last_, '30'),
            -- JSON selects
            concat_ws(', ', total_count_clause, page_info_clause, __typename_clause, edges_clause),
            -- final order by
            graphql.order_by_clause('xyz', column_orders),
            -- block name
            block_name
        )
        into result;

    return result;
end;
$$;
