package schema_validator

import "core:testing"

@(test)
type_test :: proc(t: ^testing.T) {
	TEST_FILE :: "tests/type.json"
	run_test_in_spec_file(t, TEST_FILE)
}

@(test)
enum_test :: proc(t: ^testing.T) {
	TEST_FILE :: "tests/enum.json"
	run_test_in_spec_file(t, TEST_FILE)
}

@(test)
const_test :: proc(t: ^testing.T) {
	TEST_FILE :: "tests/const.json"
	run_test_in_spec_file(t, TEST_FILE)
}

@(test)
max_length_test :: proc(t: ^testing.T) {
	TEST_FILE :: "tests/maxLength.json"
	run_test_in_spec_file(t, TEST_FILE)
}

@(test)
min_length_test :: proc(t: ^testing.T) {
	TEST_FILE :: "tests/minLength.json"
	run_test_in_spec_file(t, TEST_FILE)
}

@(test)
exclusive_maximum_test :: proc(t: ^testing.T) {
	TEST_FILE :: "tests/exclusiveMaximum.json"
	run_test_in_spec_file(t, TEST_FILE)
}

@(test)
exclusive_minimum_test :: proc(t: ^testing.T) {
	TEST_FILE :: "tests/exclusiveMinimum.json"
	run_test_in_spec_file(t, TEST_FILE)
}

@(test)
maximum_test :: proc(t: ^testing.T) {
	TEST_FILE :: "tests/maximum.json"
	run_test_in_spec_file(t, TEST_FILE)
}

@(test)
minimum_test :: proc(t: ^testing.T) {
	TEST_FILE :: "tests/minimum.json"
	run_test_in_spec_file(t, TEST_FILE)
}

@(test)
multipleof_test :: proc(t: ^testing.T) {
	TEST_FILE :: "tests/multipleOf.json"
	run_test_in_spec_file(t, TEST_FILE)
}

@(test)
max_properties_test :: proc(t: ^testing.T) {
	TEST_FILE :: "tests/maxProperties.json"
	run_test_in_spec_file(t, TEST_FILE)
}

@(test)
min_properties_test :: proc(t: ^testing.T) {
	TEST_FILE :: "tests/minProperties.json"
	run_test_in_spec_file(t, TEST_FILE)
}
