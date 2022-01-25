## Table/Column Visibility
Table and column visibility in the GraphQL schema are controlled by standard PostgreSQL permissions. Revoking `SELECT` access from the user/role executing queries removes that entity from the schema.

For example:
```sql
revoke all privileges on public.account from api_user;
```

removes the `Account` GraphQL type.


## Comment Directives

Comment directives are snippets of configuration you can associated with SQL entities to alter how they will be reflected into the GraphQL schema.

The format of a comment directive is

```sql
@graphql(<JSON>)
```

### Rename a Table's Type

Use the `"name"` JSON key to override a table's type name.

```sql
create table account(
    id serial primary key
);

comment on table public.account is
e'@graphql({"name": "AccountHolder"})';
```

results in:
```graphql
type AccountHolder { # previously: "Account"
  id: Int!
}
```

### Rename a Column's Field

Use the `"name"` JSON key to override a column's field name.

```sql
create table public.account(
    id serial primary key,
    email text
);

comment on column public.account.email is
e'@graphql({"name": "emailAddress"})';
```

results in:
```graphql
type Account {
  id: Int!
  emailAddress: String! # previously "email"
}
```

### Rename a Relationship's (Foreign Key) Field

Use the `"local_name"` and `"foreign_name"` JSON keys to override a a relationships inbound and outbound field names.

```sql
create table account(
    id serial primary key
);

create table post(
    id serial primary key,
    account_id integer not null references account(id),
    title text not null,
    body text
);

comment on constraint post_owner_id_fkey
on post
is E'@graphql({"foreign_name": "author", "local_name": "posts"})';

```

results in:
```graphql
type Post {
  id: Int!
  accountId: Int!
  title: String!
  body: String!
  author: Account # was "account"
}

type Account {
  id: Int!
  posts( # was "postCollection"
    after: Cursor,
    before: Cursor,
    filter: PostFilter,
    first: Int,
    last: Int,
    orderBy: [PostOrderBy!]
  ): PostConnection
}
```
