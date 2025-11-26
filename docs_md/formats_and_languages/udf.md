# Universal Datatype Format

Universal Datatype Format (UDF) is a way for Jexplorer to serialize values as strings such that when it is deserialized the type is known and the value can be fully reconstructed.

To achieve this, at the beginning of each UDF string there is a "tag" which is just square brackets enclosing the type of the value described after it.

Example:
```
[vec3] 10, 2, 30
[str] Hello World!
[num] 10
```

Typing each tag out manually may be tedious for applications such as using the Jexplorer search bar or the style editor, so ontop of tags UDF additionally provides some specialized sigils as shorthands for types.

All of them are listed below

| Sigil | Is the same as | Example |
| --- | --- | --- |
| `%` | `[str]` | `%Hello World!` |
| `#` | `[num]` | `#10` |
| `?` | `[bool]` | `?true` |
| `$` | `[expr]` | `$ 10 + $MyToken` |
| `@` | `[selector]` | `@icon(Folder, nil)` |

List of UDF datatype tags

| Tag | Alias | Example |
| --- | --- | --- |
| `[str] (STRING)` | String | `[str] Hello World!` |
| `[num] (FLOAT OR INT)` | Number | `[num] 1.101` |
| `[bool] (BOOLEAN)` | Boolean | `[bool] true` |
| `[udim2] (X SCALE), (X OFFSET), (Y SCALE), (Y OFFSET)` | UDim2 | `[udim2] 0, 10, 1, 0` |
| `[udim] (SCALE), (OFFSET)` | UDim | `[udim] 1, 0` |
| `[rgb] (R), (G), (B)` | Color3 (RGB) | `[rgb] 200, 2, 0` |
| `[hex] (HEX STRING)` | Color3 (Hex) | `[hex] 00ffe1` |
| `[vec3] (X), (Y), (Z)` | Vector3 | `[vec3] 10, 2, 10` |
| `[vec2] (X), (Y)` | Vector2 | `[vec2] 10, 2` |
| `[enum.EnumType] (ENUM ITEM NAME)` | EnumItem | `[enum.CameraType] Custom` |
| `[expr] (EXPRESSION)` | JELExpression | `[expr] $Token > 10 ? rgb(1, 2, 3) : rgb(2, 3, 4)` |
| `[json] (JSON)` | JSON | `[json] {"hello": "world", "empty":null}` |
| `[selector] (MACRO AND ARGS)` | StyleSelectorMacro | `[selector] icon(Model, nil)` |
| `[font_enum] (FONT ENUM NAME)` | FontFace | `[font_enum] SourceSans` |
| `[font_asset] (WEIGHT) (STYLE) (ASSET ID)` | FontFace | `[font_asset] Light Italic ROBLOX_ID` |
| `[font_family] (WEIGHT) (STYLE) (FAMILY NAME)` | FontFace | `[font_family] Light Normal SourceSans` |