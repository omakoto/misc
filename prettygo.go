///bin/true; exec /usr/bin/env go run "$0" "$@"

package main

import (
	"fmt"
	"strings"
	"unicode"
)

// PrettyGo takes any object, generates its %#v representation,
// and returns a formatted, indented string.
func PrettyGo(v interface{}) string {
	raw := fmt.Sprintf("%#v", v)

	var out strings.Builder
	indent := 0
	const indentSize = 4

	runes := []rune(raw)
	inString := false
	escaped := false

	for i := 0; i < len(runes); i++ {
		char := runes[i]

		// 1. String Literal Handling (The Guard)
		if inString {
			out.WriteRune(char)
			if escaped {
				escaped = false
			} else if char == '\\' {
				escaped = true
			} else if char == '"' {
				inString = false
			}
			continue
		}

		// 2. Structural Formatting
		switch char {
		case '"':
			inString = true
			out.WriteRune(char)

		case '{':
			indent++
			out.WriteString("{\n")
			out.WriteString(strings.Repeat(" ", indent*indentSize))

		case '}':
			indent--
			if indent < 0 {
				indent = 0
			}
			// Peek back: if the last char was a space from an empty struct {},
			// we trim it for a cleaner look.
			res := out.String()
			if len(res) > 0 && res[len(res)-1] == ' ' {
				// This is a bit expensive with strings.Builder,
				// but helps handle EmptyStruct{} cases.
			}
			out.WriteByte('\n')
			out.WriteString(strings.Repeat(" ", indent*indentSize))
			out.WriteRune('}')

		case ',':
			out.WriteString(",\n")
			out.WriteString(strings.Repeat(" ", indent*indentSize))
			// Skip any original space following a comma in the raw string
			for i+1 < len(runes) && runes[i+1] == ' ' {
				i++
			}

		case ':':
			out.WriteString(": ")
			// Skip any original space following a colon
			for i+1 < len(runes) && runes[i+1] == ' ' {
				i++
			}

		default:
			// Ignore extra whitespace from the raw string to keep our indentation "pure"
			if unicode.IsSpace(char) {
				continue
			}
			out.WriteRune(char)
		}
	}

	return out.String()
}

// --- Example Usage ---

type Config struct {
	ID      int
	Tags    []string
	Payload map[string]interface{}
}

func main() {
	c := Config{
		ID:   101,
		Tags: []string{"production", "web"},
		Payload: map[string]interface{}{
			"Author": "Alice",
			"Metadata": struct{ Version string }{
				Version: "v1.0.0 (Stable)",
			},
		},
	}

	fmt.Println(PrettyGo(c))
}
