begin;
    create table account(
        id int primary key
    );


    insert into public.account(id)
    select * from generate_series(1,5);


    select jsonb_pretty(
        graphql.resolve($$
            {
              accountCollection(last: 2, before: "WyJhY2NvdW50IiwgM10=") {
                edges {
                  node {
                    id
                  }
                }
              }
            }
        $$)
    );

    -- Last without a before clause
    select jsonb_pretty(
        graphql.resolve($$
            {
              accountCollection(last: 2) {
                edges {
                  node {
                    id
                  }
                }
              }
            }
        $$)
    );



rollback;
