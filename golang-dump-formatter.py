#!/usr/bin/env python3
"""
A formatter for Go data structure dumps. (%#v output)
"""
import sys

def tokenize_go_dump(text):
    """
    A state-machine lexer that distinguishes between Go syntax and 
    content inside string literals.
    """
    tokens = []
    buffer = []
    in_string = False
    escaped = False

    for char in text:
        if in_string:
            buffer.append(char)
            if escaped:
                escaped = False
            elif char == '\\':
                escaped = True
            elif char == '"':
                in_string = False
                tokens.append(("STRING", "".join(buffer)))
                buffer = []
        else:
            if char == '"':
                if buffer:
                    tokens.append(("TEXT", "".join(buffer).strip()))
                    buffer = []
                in_string = True
                buffer.append(char)
            elif char in "{},":
                if buffer:
                    tokens.append(("TEXT", "".join(buffer).strip()))
                    buffer = []
                tokens.append(("SYNTAX", char))
            else:
                buffer.append(char)
    
    if buffer:
        tokens.append(("TEXT", "".join(buffer).strip()))
    
    return [t for t in tokens if t[1]] # Filter empty strings

def format_go_dump(text, indent_size=4):
    tokens = tokenize_go_dump(text)
    level = 0
    result = []
    
    for i, (kind, val) in enumerate(tokens):
        if val == "{":
            result.append(" {")
            level += 1
            result.append("\n" + " " * (level * indent_size))
        elif val == "}":
            level = max(0, level - 1)
            # Adjust to avoid a trailing space before the closing brace
            if result and result[-1].strip() == "":
                result[-1] = "\n" + " " * (level * indent_size)
            else:
                result.append("\n" + " " * (level * indent_size))
            result.append("}")
        elif val == ",":
            result.append(",\n" + " " * (level * indent_size))
        else:
            # Add a space after colons in "Field:Value" for readability
            if kind == "TEXT" and ":" in val:
                # Split only on the first colon
                parts = val.split(":", 1)
                result.append(f"{parts[0]}: {parts[1].strip()}")
            else:
                result.append(val)
                
    # Final cleanup of spacing
    return "".join(result).replace("  {", " {")

if __name__ == "__main__":
    # If piped: cat dump.txt | python3 format.py
    if not sys.stdin.isatty():
        raw_input = sys.stdin.read()
        print(format_go_dump(raw_input))
    else:
        # Example showing that it respects braces inside strings
        example = 'main.User{Name:"Alice {The Architect}", Meta:map[string]int{"a":1}, Bio:"Quotes \\"escaped\\" work too,"}'
        print(format_go_dump(example))
