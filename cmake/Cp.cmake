# Check for cp command and its capabilities
# Similar to the autoconf CL_PROG_CP macro

include(CMakeParseArguments)

function(check_cp_capabilities)
    # Create a temporary test file
    file(WRITE "${CMAKE_BINARY_DIR}/cp_test.tmp" "test content")
    
    # Try cp -p first
    execute_process(
        COMMAND cp -p "${CMAKE_BINARY_DIR}/cp_test.tmp" "${CMAKE_BINARY_DIR}/cp_test_copy.tmp"
        RESULT_VARIABLE CP_P_RESULT
        ERROR_VARIABLE CP_P_ERROR
        OUTPUT_QUIET
    )

    # Set the CP command based on the test result
    if(CP_P_RESULT EQUAL 0)
        set(CP_COMMAND "cp -p" CACHE STRING "Command to copy files preserving attributes")
    else()
        set(CP_COMMAND "cp" CACHE STRING "Command to copy files")
    endif()

    # Clean up test files
    file(REMOVE "${CMAKE_BINARY_DIR}/cp_test.tmp" "${CMAKE_BINARY_DIR}/cp_test_copy.tmp")
    
    message(STATUS "Copy command set to: ${CP_COMMAND}")
endfunction()

# Call the function to perform the check
check_cp_capabilities()
