package schema_validator

import "core:encoding/json"
import "core:strings"
import "core:os"
import "core:log"
import "core:testing"
import "core:fmt"

TEST_FILE :: "tests/const.json"

@(test)
const_test :: proc(t: ^testing.T) {
	allocator := context.allocator
    defer free_all()

	fd, open_err := os.open(TEST_FILE, os.O_RDONLY, 0)
	testing.expect(t, open_err == os.General_Error.None, "os.open returned error")
    defer os.close(fd)
	data_bytes, ok := os.read_entire_file_from_handle(
        fd,
        allocator,
    )
    testing.expect(t, ok == true, "Can read the test file")
    parsed_json, parse_err := json.parse(data_bytes)

    for test_object, test_idx in parsed_json.(json.Array) {
    	test_object := test_object.(json.Object)
		if schema_object, ok := test_object["schema"].(json.Object); ok {
    		schema_struct, err := parse_schema_from_json_value(schema_object)
    		testing.expect(t, err == .None, "Error occured when parsing schema")

    		schema_tests := test_object["tests"].(json.Array)
    		for schema_test in schema_tests {
    			schema_test := schema_test.(json.Object)
    			description := schema_test["description"].(json.String)
    			expected_result := schema_test["valid"].(json.Boolean)

    			schema_test_data := schema_test["data"]
    			err := validate_json_value_with_subschema(schema_test_data, schema_struct)
    			if expected_result {
    				msg := fmt.tprintf("test (desc='%v') should pass, returned (%v)", description, err)
    				testing.expect(t, err == .None, msg)
    			} else {
    				msg := fmt.tprintf("test (desc='%v') should fail, returned (%v)", description, err)
    				testing.expect(t, err != .None, msg)
    			}
    			
    		}

		} else {
			testing.expect(t, ok == true, "Schema is not an object")
		}
    	
    }
}