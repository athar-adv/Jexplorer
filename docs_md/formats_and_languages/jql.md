# Jexplorer Query Language

The Jexplorer Query Language (JQL) is the language used by the explorer search bar to structure instance queries.

It contains a few operators that you can use to narrow your search down:

| Operator Syntax | Alias | Example | Passes if an Instance |
| --- | --- | --- | --- |
| `(PROPERTY NAME) = (UDF VALUE)` | Property Equality | `ClassName = %Folder` | has this property and the specified value assigned to it. |
| `(PROPERTY NAME) != (UDF_VALUE)` | Property Inequality | `ClassName != %Folder` | has this property but not the specified value assigned to it. |
| `(TAG NAME)` | Has Tag | `MyTag` | has a tag of this name. |
| `!(TAG NAME)` | Doesn't Have Tag | `!MyTag` | doesn't have a tag of this name. |
| `<(CONDITION)` | Parent Condition | `<<Name = %Workspace` | 's Parent passes the CONDITION. Is stackable. |
| `>(CONDITION)` | First Child Condition | `>>Name = %Part` | contains atleast 1 child of the specified depth (amount of > arrows) where CONDITION passes. Is stackable. |