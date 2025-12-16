# Jexplorer Expression Language

JEL is a language used in Jexplorer made to make using computed expressions, mostly for usage in Styes, possible.

## Operators:

| Symbol | Alias | Description | Example |
| --- | --- | --- | --- |
| `+, -, *, /, //, %, ^` | `Math` | The usual arithmetic and geometric operators in luau, you should know what these do. | `1 + (-1)` |
| `()` | `Parentheses` | Explicitly specifies an expression and computes it before anything else. | `(1 + 1)` |
| `$` | `Variable` | Uses the value of the variable assigned to the name. | `$MyVar + 1` |
| `==` | `Equality` | Checks if both operands are equal. | `$MyVar == 1` | 
| `!=` | `Inequality` | Checks if both operands are inequal. | `$MyVar != 2` |
| `<` | `Less than` | Checks if the first operand is less than the 2nd operand. | `$MyVar < 5` |
| `>` | `More than` | Checks if the first operand is more than the 2nd operand. | `5 > $MyVar` |
| `<=` | `Less than or equal to` | Checks if the first operand is less than or equal to the 2nd operand. | `5 >= 5` |
| `>=` | `More than or equal to` | Checks if the first operand is more than or equal to the 2nd operand. | `4 >= 2` |
| `? :` | `Ternary` | Uses the 2nd operand if the 1st operand is truthy, and the 3rd operand if not. | `$MyVar < 5 ? 25 : 10` |
| `''` | `String Constructor` | Constructs a string. | `'Helllo Worldddlldld'` |

## Functions:

| Signature | Description | Example |
| --- | --- | --- |
| `rgb(r: number, g: number, b: number) -> color3` | Constructs a `color3` from 3 rgb number values. | `$MyVar + rgb(1, 2, 3)` |
| `hex(hexstr: string) -> color3` | Constructs a `color3` from a hex string. | `hex('#ff00ff')` |
| `udim(scale: number, offset: number) -> udim` | Constructs a `udim` from a scale and offset value. | `udim(0.5, 10)` |
| `udim2(xscale: number, xoffset: number, yscale: number, yoffset: number) -> udim2` | Constructs a `udim2` from a scale and offset value for both the x and y axis respectively. | `udim2(0.5, 0, 0, 10)` |
| `vec3(x: number, y: number, z: number) -> vector3` | Constructs a `vector3` from x, y and z number values. | `vec3(0.5, 1, -2)` |
| `vec2(x: number, y: number) -> vector2` | Constructs a `vector2` from x and y number values. | `vec2(0.5, 1)` |
| `min(...number) -> number` | Returns the smallest number out of a tuple of numbers. | `min(1, 2, 3, 4)` returns 1 |
| `max(...number) -> number` | Returns the biggest number out of a tuple of numbers. | `max(1, 2, 3, 4)` returns 4 |
| `floor(x: number)` | Returns the smallest integer to x. | `floor(0.5)` returns 0 |
| `ceil(x: number)` | Returns the largest integer to x. | `ceil(0.5)` returns 1 |
| `round(x: number)` | Returns the closest integer to x. | `round(0.5)` returns 1 but `round(0.4)` returns 0 |
| `clamp(x: number, min: number, max: number)` | Returns the value clamped to more than or equal to min and less than or equal to max. | `clamp(5, 1, 3)` returns 3. |

