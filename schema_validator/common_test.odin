package schema_validator

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:testing"

// Used as a helper function run all the tests in the .json
// files. Just used as a way to reduce copypasta of test code
// in so many places
run_test_in_spec_file :: proc(t: ^testing.T, test_file: string) {
	allocator := context.allocator
	defer free_all()

	fd, open_err := os.open(test_file, os.O_RDONLY, 0)
	testing.expect(t, open_err == os.General_Error.None, "os.open returned error")
	defer os.close(fd)
	data_bytes, ok := os.read_entire_file_from_handle(fd, allocator)
	testing.expect(t, ok == true, "Can read the test file")
	parsed_json, parse_err := json.parse(data_bytes)

	schema_context := Context{}
	init_context(&schema_context, 100, allocator)

	for test_object, test_idx in parsed_json.(json.Array) {
		test_object := test_object.(json.Object)
		if schema_object, ok := test_object["schema"].(json.Object); ok {
			schema_struct, idx, err := parse_schema_from_json_value(schema_object, &schema_context)
			msg := fmt.tprintf(
				"(file=%v, grp='%v') Error occured when parsing schema (%v)",
				test_file,
				test_object["description"].(json.String),
				err,
			)
			testing.expect(t, err == .None, msg)

			schema_tests := test_object["tests"].(json.Array)
			for schema_test in schema_tests {
				schema_test := schema_test.(json.Object)
				description := schema_test["description"].(json.String)
				expected_result := schema_test["valid"].(json.Boolean)

				schema_test_data := schema_test["data"]
				err := validate_json_value_with_subschema(
					schema_test_data,
					schema_struct,
					&schema_context,
				)
				if expected_result {
					msg := fmt.tprintf(
						"(file=%v, grp='%v', test='%v') test should pass, returned (%v)",
						test_file,
						test_object["description"].(json.String),
						description,
						err,
					)
					testing.expect(t, err == .None, msg)
				} else {
					msg := fmt.tprintf(
						"(file=%v, grp='%v', test='%v') test should fail, returned (%v)",
						test_file,
						test_object["description"].(json.String),
						description,
						err,
					)
					testing.expect(t, err != .None, msg)
				}

			}

		} else {
			testing.expect(t, ok == true, "Schema is not an object")
		}

	}
}
