begin;
    create table account(
        id serial primary key,
        first_name varchar(255) not null,
        last_name varchar(255) not null
    );

    -- Extend with function
    create function full_name(rec public.account)
        returns text
        immutable
        strict
        language sql
    as $$
        select format('%s %s', rec.first_name, rec.last_name)
    $$;

    comment on function public.full_name(public.account) is E'@graphql({"name": "wholeName"})';

    select
        name
    from
        graphql.field
    where
        entity = 'public.account'::regclass
        and func = 'full_name'::regproc
        and meta_kind = 'Function';

rollback;
