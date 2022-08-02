begin;
    create table account(
        id int primary key,
        is_verified bool,
        name text
    );

    insert into public.account(id, is_verified, name)
    values
        (1, true, 'foo'),
        (2, true, 'bar'),
        (3, false, 'baz');

    savepoint a;

    -- Filter by Int
    select jsonb_pretty(
        graphql.resolve($$
            {
              accountCollection(filter: {id: {eq: 2}}) {
                edges {
                  node {
                    id
                  }
                }
              }
            }
        $$)
    );
    rollback to savepoint a;

    -- Filter by Int and bool. has match
    select jsonb_pretty(
        graphql.resolve($$
            {
              accountCollection(filter: {id: {eq: 2}, isVerified: {eq: true}}) {
                edges {
                  node {
                    id
                  }
                }
              }
            }
        $$)
    );
    rollback to savepoint a;

    -- Filter by Int and bool. no match
    select jsonb_pretty(
        graphql.resolve($$
            {
              accountCollection(filter: {id: {eq: 2}, isVerified: {eq: false}}) {
                edges {
                  node {
                    id
                  }
                }
              }
            }
        $$)
    );
    rollback to savepoint a;

    -- Filter is null should have no effect
    select jsonb_pretty(
        graphql.resolve($$
            {
              accountCollection(filter: null) {
                edges {
                  node {
                    id
                  }
                }
              }
            }
        $$)
    );

    -- filter = null is ignored
    select graphql.resolve($${accountCollection(filter: null) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- neq
    select graphql.resolve($${accountCollection(filter: {id: {neq: 2}}) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- lt
    select graphql.resolve($${accountCollection(filter: {id: {lt: 2}}) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- lt - null - should be ignored
    select graphql.resolve($${accountCollection(filter: {id: {lt: null}}) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- lte
    select graphql.resolve($${accountCollection(filter: {id: {lte: 2}}) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- gte
    select graphql.resolve($${accountCollection(filter: {id: {gte: 2}}) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- gt
    select graphql.resolve($${accountCollection(filter: {id: {gt: 2}}) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- in - int
    select graphql.resolve($${accountCollection(filter: {id: {in: [1, 2]}}) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- in - int coerce to list
    select graphql.resolve($${accountCollection(filter: {id: {in: 2}}) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- in - bool
    select graphql.resolve($${accountCollection(filter: {isVerified: {in: [false]}}) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- in - text
    select graphql.resolve($${accountCollection(filter: {name: {in: ["foo", "bar"]}}) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- in - text coerce to list
    select graphql.resolve($${accountCollection(filter: {name: {in: "baz"}}) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- in - empty list
    select graphql.resolve($${accountCollection(filter: {name: {in: []}}) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- in - null
    select graphql.resolve($${accountCollection(filter: {name: {in: null}}) { edges { node { id } } }}$$);
    rollback to savepoint a;

    -- Variable: In, mixed List Int
    select jsonb_pretty(
        graphql.resolve($$
           query AccountsFiltered($filt: Int!)
           {
             accountCollection(filter: {id: {in: [1, $filt]}}) {
               edges {
                 node{
                   id
                 }
               }
             }
           }
        $$,
        variables:= '{"filt": 2}'
      )
    );
    rollback to savepoint a;

    -- Variable: In: single elem wrapped in list
    select jsonb_pretty(
        graphql.resolve($$
           query AccountsFiltered($filt: Int!)
           {
             accountCollection(filter: {id: {in: [$filt]}}) {
               edges {
                 node{
                   id
                 }
               }
             }
           }
        $$,
        variables:= '{"filt": 3}'
      )
    );
    rollback to savepoint a;

    -- Variable: In: single elem coerce to list
    select jsonb_pretty(
        graphql.resolve($$
           query AccountsFiltered($filt: Int!)
           {
             accountCollection(filter: {id: {in: $filt}}) {
               edges {
                 node{
                   id
                 }
               }
             }
           }
        $$,
        variables:= '{"filt": 1}'
      )
    );
    rollback to savepoint a;

    -- Variable: In: multi-element list
    select jsonb_pretty(
        graphql.resolve($$
           query AccountsFiltered($filt: [Int!])
           {
             accountCollection(filter: {id: {in: $filt}}) {
               edges {
                 node{
                   id
                 }
               }
             }
           }
        $$,
        variables:= '{"filt": [2, 3]}'
      )
    );
    rollback to savepoint a;

    -- Variable: In: variables not an object
    select jsonb_pretty(
        graphql.resolve($$
           query AccountsFiltered($filt: [Int!])
           {
             accountCollection(filter: {id: {in: $filt}}) {
               edges {
                 node{
                   id
                 }
               }
             }
           }
        $$,
        variables:= '[{"filt": [2, 3]}]'
      )
    );
    rollback to savepoint a;

    -- Variable: Int
    select jsonb_pretty(
        graphql.resolve($$
           query AccountsFiltered($filt: Int!)
           {
             accountCollection(filter: {id: {eq: $filt}}) {
               edges {
                 node{
                   id
                 }
               }
             }
           }
        $$,
        variables:= '{"filt": 1}'
      )
    );
    rollback to savepoint a;

    -- Variable: IntFilter
    select jsonb_pretty(
        graphql.resolve($$
           query AccountsFiltered($ifilt: IntFilter!)
           {
             accountCollection(filter: {id: $ifilt}) {
               edges {
                 node{
                   id
                 }
               }
             }
           }
        $$,
        variables:= '{"ifilt": {"eq": 3}}'
      )
    );
    rollback to savepoint a;

    -- Variable: AccountFilter, single col
    select jsonb_pretty(
        graphql.resolve($$
           query AccountsFiltered($afilt: AccountFilter!)
           {
             accountCollection(filter: $afilt) {
               edges {
                 node{
                   id
                 }
               }
             }
           }
        $$,
        variables:= '{"afilt": {"id": {"eq": 2}} }'
      )
    );
    rollback to savepoint a;

    -- Variable: AccountFilter, multi col match
    select jsonb_pretty(
        graphql.resolve($$
           query AccountsFiltered($afilt: AccountFilter!)
           {
             accountCollection(filter: $afilt) {
               edges {
                 node{
                   id
                 }
               }
             }
           }
        $$,
        variables:= '{"afilt": {"id": {"eq": 2}, "isVerified": {"eq": true}} }'
      )
    );
    rollback to savepoint a;

    -- Variable: AccountFilter, multi col no match
    select jsonb_pretty(
        graphql.resolve($$
           query AccountsFiltered($afilt: AccountFilter!)
           {
             accountCollection(filter: $afilt) {
               edges {
                 node{
                   id
                 }
               }
             }
           }
        $$,
        variables:= '{"afilt": {"id": {"eq": 2}, "isVerified": {"eq": false}} }'
      )
    );
    rollback to savepoint a;

    -- Variable: AccountFilter, invalid field name
    select jsonb_pretty(
        graphql.resolve($$
           query AccountsFiltered($afilt: AccountFilter!)
           {
             accountCollection(filter: $afilt) {
               edges {
                 node{
                   id
                 }
               }
             }
           }
        $$,
        variables:= '{"afilt": {"dne_id": 2} }'
      )
    );
    rollback to savepoint a;

    -- Variable: AccountFilter, invalid IntFilter
    select jsonb_pretty(
        graphql.resolve($$
           query AccountsFiltered($afilt: AccountFilter!)
           {
             accountCollection(filter: $afilt) {
               edges {
                 node{
                   id
                 }
               }
             }
           }
        $$,
        variables:= '{"afilt": {"id": 2} }'
      )
    );
    rollback to savepoint a;

    -- Variable: AccountFilter, invalid data type
    select jsonb_pretty(
        graphql.resolve($$
           query AccountsFiltered($afilt: AccountFilter!)
           {
             accountCollection(filter: $afilt) {
               edges {
                 node{
                   id
                 }
               }
             }
           }
        $$,
        variables:= '{"afilt": {"id": {"eq": true}} }'
      )
    );
    rollback to savepoint a;

    -- Variable: AccountFilter, null does not apply any filters
    select jsonb_pretty(
        graphql.resolve($$
           query AccountsFiltered($afilt: AccountFilter!)
           {
             accountCollection(filter: $afilt) {
               edges {
                 node{
                   id
                 }
               }
             }
           }
        $$,
        variables:= '{"afilt": null }'
      )
    );
    rollback to savepoint a;

rollback;
