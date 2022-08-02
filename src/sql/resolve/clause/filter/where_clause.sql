create or replace function graphql.where_clause(
    filter_arg jsonb,
    entity regclass,
    alias_name text,
    variables jsonb default '{}',
    variable_definitions jsonb default '{}'
)
    returns text
    language plpgsql
    immutable
    as
$$
declare
    clause_arr text[] = array['true'];
    variable_name text;
    variable_ix int;
    variable_value jsonb;
    variable_part jsonb;
    variable_part_literal text;

    sel jsonb;
    ix smallint;

    field_name text;
    column_name text;
    column_type regtype;

    field_value_obj jsonb;
    op_name text;
    comp_op graphql.comparison_op;
    field_value text;

    format_str text;

    -- Collect allowed comparison columns
    column_fields graphql.field[] = array_agg(f)
        from
            graphql.type t
            left join graphql.field f
                on t.name = f.parent_type
        where
            t.entity = $2
            and t.meta_kind = 'Node'
            and f.column_name is not null;
begin

    -- No filter specified
    if filter_arg is null or graphql.value_literal_is_null(filter_arg) then
        return 'true';

    elsif (filter_arg -> 'value' ->> 'kind') not in ('ObjectValue', 'Variable') then
        return graphql.exception('Invalid filter argument');
    end if;

    -- "{"id": {"eq": 1}, "name": {"in": ["john", "amy"]}, ...}"
    variable_value = graphql.arg_to_jsonb(
        filter_arg,
        variables
    );


    for field_name, op_name, variable_part, column_name, column_type in
        select
            f.name, -- id
            case
                when jsonb_typeof(je.v) = 'object' then  (select k from jsonb_object_keys(je.v) x(k) limit 1) -- eq
                else graphql.exception('Invalid filter field')
            end,
            (select v from jsonb_each(je.v) x(k, v) limit 1), -- 1
            f.column_name,
            f.column_type
        from
            jsonb_each(variable_value) je(k, v)
            left join unnest(column_fields) f
                on je.k = f.name
        loop

        -- Null should be ignored
        if jsonb_typeof(variable_part) = 'null' or variable_part is null then
            continue;
        end if;

        comp_op = graphql.text_to_comparison_op(op_name);

        if comp_op = 'in' then

            variable_part = graphql.arg_coerce_list(
                variable_part
            ); -- this is now a jsonb array


            variable_part_literal = (
                'array['
                || (
                    select
                        coalesce(
                            string_agg(format('(((%L::jsonb) #>> $a${}$a$ )::%s)', v, column_type), ', '),
                            ''
                        )
                    from
                        jsonb_array_elements(variable_part) jae(v)
                   )
                || format(']::%s[]', column_type)
            );

            clause_arr = clause_arr || format(
                '%I.%I = any(%s)',
                alias_name,
                column_name,
                variable_part_literal
            );
        else
            -- Extract json as text to use with %L
            variable_part_literal = format('((%L::jsonb) #>> $a${}$a$ )::%s', variable_part, column_type);

            clause_arr = clause_arr || format(
                '%I.%I %s %s',
                alias_name,
                column_name,
                comp_op,
                variable_part_literal
            );
        end if;
    end loop;

    return array_to_string(clause_arr, ' and ');
end;
$$;
