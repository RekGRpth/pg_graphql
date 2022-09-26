## PostgreSQL Builtin (Preferred)

PostgreSQL has a builtin method for adding [generated columns](https://www.postgresql.org/docs/14/ddl-generated-columns.html) to tables. Generated columns are reflected identically to non-generated columns. This is the recommended approach to adding computed fields when your computation meets the restrictions. Namely:

- expression must be immutable
- expression may only reference the current row

For example:
```sql
--8<-- "test/expected/extend_type_with_generated_column.out"
```


## Extending Types with Functions

For arbitrary computations that do not meet the requirements for [generated columns](https://www.postgresql.org/docs/14/ddl-generated-columns.html), a table's reflected GraphQL type can be extended by creating a function that:

- accepts a single parameter of the table's tuple type
- has a name starting with an underscore

```sql
--8<-- "test/expected/extend_type_with_function.out"
```
