# frozen_string_literal: true

module Missions
  # Canonical reference for the expression evaluation engine used by the mission
  # runtime. All expression syntax documentation for agents and node-level prompts
  # should reference these constants instead of duplicating content.
  module ExpressionDocs
    # Concise summary for individual node designer_instructions that mention
    # expressions. They should tell the agent to "see the full reference in
    # the system prompt" rather than repeating the whole doc.
    NODE_HINT = <<~HINT.strip
      Expressions use the built-in formula engine. Supports math, logic, string
      functions, and direct variable references like `llm.response`.
      Reserve `{{variable}}` interpolation for text templates, not expression operands.
      Refer to the **Expression Reference** in the system prompt for the full
      operator/function list.
    HINT

    # Comprehensive reference included once in the mission-designer system prompt.
    FULL_REFERENCE = <<~REFERENCE.strip
      ## Expression Reference

      The workflow engine evaluates expressions with a safe math & logic formula
      engine.

      Prefer direct variable references inside formulas:
      - Node-scoped: `node.var`
      - Global: `variable_name`

      `{{...}}` interpolation is raw text substitution performed **before** the
      formula is parsed. That is useful for text templates, but unsafe for
      string and JSON operands inside expressions because values are inserted
      without quoting.

      ### 1. Operators (by precedence, highest first)

      | Precedence | Operators | Notes |
      |------------|-----------|-------|
      | Parentheses | `( )` | Group sub-expressions |
      | Power | `^` | Exponentiation |
      | Unary | `NOT`, `-` (negation) | |
      | Multiplicative | `*`, `/`, `%` | Modulo = remainder |
      | Additive | `+`, `-` | |
      | Bitwise | `&`, `\\|`, `<<`, `>>` | Bitwise AND, OR, shifts |
      | Comparison | `<`, `>`, `<=`, `>=`, `==` (or `=`), `!=` (or `<>`) | |
      | Logical | `AND`, `OR`, `XOR` | Short-circuit evaluation |

      ### 2. Comparison & String Rules

      - **Strings MUST be single-quoted:** `status == 'approved'`
      - Prefer direct variable references in formulas: `llm.response == 'true'`, not `{{llm.response}} == 'true'`.
      - `==` and `=` are both equality. Prefer `==`.
      - `!=` and `<>` are both inequality.
      - **Booleans:** compare with bare `true` / `false`.
      - Operators and function names are **case-insensitive** (`AND`, `and`, `And` all work).

      ### 3. Built-in Functions

      #### Conditional
      | Function | Description | Example |
      |----------|-------------|---------|
      | `IF(cond, true_val, false_val)` | Conditional value | `IF(score > 80, 'pass', 'fail')` |
      | `SWITCH(val, case1, result1, …, default)` | Multi-way branch | `SWITCH(status, 'a', 1, 'b', 2, 0)` |
      | `CASE val WHEN c1 THEN r1 … ELSE default END` | SQL-style case | Standard CASE syntax |

      #### Logic
      | Function | Description | Example |
      |----------|-------------|---------|
      | `AND(a, b, …)` | All true? | `AND(x > 0, y > 0)` |
      | `OR(a, b, …)` | Any true? | `OR(role == 'admin', level > 5)` |
      | `NOT(a)` | Negate | `NOT(is_blocked)` |
      | `XOR(a, b)` | Exclusive or | `XOR(a, b)` |

      #### Numeric / Aggregation
      | Function | Description | Example |
      |----------|-------------|---------|
      | `MIN(a, b, …)` | Minimum | `MIN(3, 7, 1)` → 1 |
      | `MAX(a, b, …)` | Maximum | `MAX(3, 7, 1)` → 7 |
      | `SUM(a, b, …)` | Sum | `SUM(1, 2, 3)` → 6 |
      | `AVG(a, b, …)` | Average | `AVG(2, 4)` → 3 |
      | `COUNT(a, b, …)` | Count of args | `COUNT(1, 2, 3)` → 3 |
      | `ABS(x)` | Absolute value | `ABS(-5)` → 5 |
      | `INTERCEPT(b, m, x)` | Linear intercept | `INTERCEPT(2, 3, 4)` → 14 |

      #### Rounding
      | Function | Description | Example |
      |----------|-------------|---------|
      | `ROUND(x)` | Round to nearest int | `ROUND(8.5)` → 9 |
      | `ROUND(x, n)` | Round to n decimals | `ROUND(8.2759, 2)` → 8.28 |
      | `ROUNDUP(x)` | Ceiling | `ROUNDUP(8.1)` → 9 |
      | `ROUNDDOWN(x)` | Floor | `ROUNDDOWN(8.9)` → 8 |

      #### String
      | Function | Description | Example |
      |----------|-------------|---------|
      | `LEN(s)` | String length | `LEN('hello')` → 5 |
      | `LEFT(s, n)` | First n chars | `LEFT('hello', 2)` → 'he' |
      | `RIGHT(s, n)` | Last n chars | `RIGHT('hello', 2)` → 'lo' |
      | `MID(s, start, len)` | Substring | `MID('hello', 2, 3)` → 'ell' |
      | `FIND(needle, haystack)` | Position (1-based) | `FIND('ll', 'hello')` → 3 |
      | `SUBSTITUTE(s, old, new)` | Replace | `SUBSTITUTE('hello', 'l', 'r')` → 'herro' |
      | `CONCAT(a, b, …)` | Concatenate | `CONCAT('a', 'b')` → 'ab' |
      | `CONTAINS(haystack, needle)` | Contains? (boolean) | `CONTAINS('hello', 'ell')` → true |

      #### Collection
      | Function | Description | Example |
      |----------|-------------|---------|
      | `MAP(coll, var, expr)` | Transform items | `MAP(items, x, x * 2)` |
      | `FILTER(coll, var, expr)` | Keep matching items | `FILTER(items, x, x > 5)` |
      | `ALL(coll, var, expr)` | All items match? | `ALL(scores, s, s > 0)` |
      | `ANY(coll, var, expr)` | Any item matches? | `ANY(scores, s, s > 90)` |
      | `PLUCK(coll, key)` | Extract field | `PLUCK(users, 'name')` |

      #### Math (from Ruby's Math module)
      `SIN`, `COS`, `TAN`, `ASIN`, `ACOS`, `ATAN`, `SINH`, `COSH`, `TANH`,
      `SQRT`, `LOG`, `LOG2`, `LOG10`, `EXP`, `CBRT`, `HYPOT(a,b)`,
      `ATAN2(y,x)`, `ERF`, `ERFC`, `GAMMA`, `LGAMMA`

      ### 4. Custom Functions

      #### `STR(value)`
      Converts any value to its string representation.
      ```
      STR(42)             → '42'
      STR(true)           → 'true'
      STR(3.14)           → '3.14'
      ```

      #### `DIG(json, key1, key2, …)`
      Deep-digs into a JSON string or object. Keys can be **string keys** for
      objects or **integer positions** for arrays.
      ```
      DIG('{"user":{"name":"Alice"}}', 'user', 'name')        → 'Alice'
      DIG('{"items":["a","b","c"]}', 'items', 1)               → 'b'
      DIG('{"a":{"b":[10,20,30]}}', 'a', 'b', 2)              → 30
      DIG('{"users":[{"n":"X"},{"n":"Y"}]}', 'users', 0, 'n') → 'X'
      ```
      - Returns `nil` if any key is missing or the JSON is invalid.
      - Numeric arguments are treated as array indices (0-based).
      - String arguments are treated as hash/object keys.

      ### 5. Variable References

      Preferred inside formulas:
      - **Node-scoped:** `node_prefix.variable`
      - **Global:** `variable_name`

      Raw interpolation syntax (prefer for templates, not formula operands):
      - `{{node_prefix.variable}}`
      - `{{variable_name}}`

      Avoid `{{...}}` inside formulas when the value may be a string or JSON.
      Examples of broken patterns:
      - `{{llm.response}} == 'true'` becomes `true == 'true'`
      - `DIG({{http_request.response_body}}, 'status')` injects raw JSON text
      - `take_top_two.items == '[5,4]'` compares an array output directly instead of a scalar
      - `DIG('{{take_top_two.items}}', 0)` tries to force a typed array output through interpolation

      - Use the exact node prefix surfaced by `list_node_variables` or the expanded
        `read_mission_flow` output.
      - Prefixes are normalized to lowercase/underscores, and duplicate node labels receive
        numeric suffixes.
        "Score Analyzer", "Score Analyzer" → `score_analyzer`, `score_analyzer_2`

      ### 6. Common Patterns

      ```
      # Threshold check
      analyzer.score > 0.8

      # String equality
      classifier.label == 'positive'

      # LLM text that contains the literal string 'true'
      llm.response == 'true'

      # Non-empty check
      LEN(llm.response) > 0

      # Multi-condition
      scorer.value > 5 AND filter.pass == true

      # Conditional value
      IF(node.count > 0, node.count, 0)

      # Nested JSON extraction
      DIG(http_request.response_body, 'data', 'results', 0, 'id')

      # Convert to string for comparison
      STR(node.numeric_id) == '123'

      # Build strings inside formulas
      CONCAT('top_two_sum=', STR(sum_top_two.result), ', branch=', set_alpha_message.branch_message)
      ```

      ### 7. Important Rules

      - Only **numeric**, **string**, and **boolean** values work in expressions.
      - For formulas, prefer direct variable references over `{{...}}` interpolation.
      - Use `CONCAT(...)` for string concatenation inside formulas or `set_variable` assignments; `+` is not a string-join operator here.
      - Typed mission `array` and `hash` outputs cannot be used directly as formula operands.
        Derive a scalar upstream first (count, aggregate field, extracted scalar, normalized string, etc.).
      - Do not interpolate typed mission arrays or hashes into formulas to work around that restriction.
        `DIG()` is for JSON text inputs, not for forcing `list_node_variables` array/hash outputs through formulas.
      - Division by zero returns `nil` (node fails).
      - An expression that cannot be evaluated causes a **node failure**.
      - Inline comments: `score > 80 /* threshold for passing */`
    REFERENCE
  end
end
