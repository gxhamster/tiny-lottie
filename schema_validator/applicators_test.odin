package schema_validator

import "core:testing"

@(test)
contains_test :: proc(t: ^testing.T) {
    TEST_FILE :: "tests/contains.json"
    run_test_in_spec_file(t, TEST_FILE)
}

@(test)
allof_test :: proc(t: ^testing.T) {
    TEST_FILE :: "tests/allOf.json"
    run_test_in_spec_file(t, TEST_FILE)
}

@(test)
anyof_test :: proc(t: ^testing.T) {
    TEST_FILE :: "tests/anyOf.json"
    run_test_in_spec_file(t, TEST_FILE)
}

@(test)
oneof_test :: proc(t: ^testing.T) {
    TEST_FILE :: "tests/oneOf.json"
    run_test_in_spec_file(t, TEST_FILE)
}

@(test)
if_then_else_test :: proc(t: ^testing.T) {
    TEST_FILE :: "tests/if-then-else.json"
    run_test_in_spec_file(t, TEST_FILE)
}

@(test)
not_test :: proc(t: ^testing.T) {
    TEST_FILE :: "tests/not.json"
    run_test_in_spec_file(t, TEST_FILE)
}

@(test)
properties_test :: proc(t: ^testing.T) {
    TEST_FILE :: "tests/properties.json"
    run_test_in_spec_file(t, TEST_FILE)
}

@(test)
items_test :: proc(t: ^testing.T) {
    TEST_FILE :: "tests/items.json"
    run_test_in_spec_file(t, TEST_FILE)
}

@(test)
additional_properties_test :: proc(t: ^testing.T) {
    TEST_FILE :: "tests/additionalProperties.json"
    run_test_in_spec_file(t, TEST_FILE)
}
