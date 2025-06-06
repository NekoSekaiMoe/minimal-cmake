# Check for various link-related capabilities
# Based on the autoconf macros by Bruno Haible, Marcus Daniels

include(CMakeParseArguments)

# Function to check for basic ln (hard link) capability
function(check_ln_capabilities)
    # Create a test file
    file(WRITE "${CMAKE_BINARY_DIR}/ln_test.tmp" "test data")
    
    # Try to create a hard link
    execute_process(
        COMMAND ln "${CMAKE_BINARY_DIR}/ln_test.tmp" "${CMAKE_BINARY_DIR}/ln_test_link.tmp"
        RESULT_VARIABLE LN_RESULT
        ERROR_VARIABLE LN_ERROR
        OUTPUT_QUIET
    )

    # First check if cp -p works (similar to what would be in Cp.cmake)
    execute_process(
        COMMAND cp -p "${CMAKE_BINARY_DIR}/ln_test.tmp" "${CMAKE_BINARY_DIR}/cp_test.tmp"
        RESULT_VARIABLE CP_P_RESULT
        ERROR_VARIABLE CP_P_ERROR
        OUTPUT_QUIET
    )

    # Determine the cp command to use as fallback
    if(CP_P_RESULT EQUAL 0)
        set(CP_FALLBACK "cp -p")
    else()
        set(CP_FALLBACK "cp")
    endif()

    # Set the LN command based on the test result
    if(LN_RESULT EQUAL 0)
        set(LN_COMMAND "ln" CACHE STRING "Command to create hard links")
    else()
        set(LN_COMMAND "${CP_FALLBACK}" CACHE STRING "Command to create hard links (fallback to copy)")
    endif()

    # Clean up test files
    file(REMOVE 
        "${CMAKE_BINARY_DIR}/ln_test.tmp"
        "${CMAKE_BINARY_DIR}/ln_test_link.tmp"
        "${CMAKE_BINARY_DIR}/cp_test.tmp"
    )
    
    message(STATUS "Hard link command set to: ${LN_COMMAND}")
endfunction()

# Function to check for symbolic link capability
function(check_ln_s_capabilities)
    # Try to create a symbolic link
    execute_process(
        COMMAND ln -s test_nonexistent "${CMAKE_BINARY_DIR}/ln_s_test.tmp"
        RESULT_VARIABLE LN_S_RESULT
        ERROR_VARIABLE LN_S_ERROR
        OUTPUT_QUIET
    )

    # Set the LN_S command based on the test result
    if(LN_S_RESULT EQUAL 0)
        set(LN_S_COMMAND "ln -s" CACHE STRING "Command to create symbolic links")
    else()
        # If symbolic links aren't supported, fall back to LN
        set(LN_S_COMMAND "${LN_COMMAND}" CACHE STRING "Command to create symbolic links (fallback to hard link/copy)")
    endif()

    # Clean up test files
    file(REMOVE "${CMAKE_BINARY_DIR}/ln_s_test.tmp")
    
    message(STATUS "Symbolic link command set to: ${LN_S_COMMAND}")
endfunction()

# Function to check for proper hard linking to symlinks (HLN)
function(check_hln_capabilities)
    if("${LN_S_COMMAND}" STREQUAL "ln -s")
        # Create a test file
        file(WRITE "${CMAKE_BINARY_DIR}/hln_test.tmp" "test data")
        
        # Create a symbolic link
        execute_process(
            COMMAND ln -s "${CMAKE_BINARY_DIR}/hln_test.tmp" "${CMAKE_BINARY_DIR}/hln_test_sym.tmp"
            RESULT_VARIABLE SYMLINK_RESULT
        )

        # Try to create a hard link to the symlink
        execute_process(
            COMMAND ln "${CMAKE_BINARY_DIR}/hln_test_sym.tmp" "${CMAKE_BINARY_DIR}/hln_test_hard.tmp"
            RESULT_VARIABLE HARDLINK_RESULT
        )

        # Remove the original file
        file(REMOVE "${CMAKE_BINARY_DIR}/hln_test.tmp")

        # Try to read the hard link
        if(EXISTS "${CMAKE_BINARY_DIR}/hln_test_hard.tmp")
            file(READ "${CMAKE_BINARY_DIR}/hln_test_hard.tmp" HARD_LINK_CONTENT ERROR_QUIET)
        endif()

        if(DEFINED HARD_LINK_CONTENT)
            # If we can still read the content, ln is not SVR4-style
            set(HLN_COMMAND "ln" CACHE STRING "Command to create hard links to symlinks")
        else()
            # If we can't read the content, we need hln
            set(HLN_COMMAND "hln" CACHE STRING "Command to create hard links to symlinks")
        endif()
    else()
        # If symbolic links aren't supported, just use regular ln
        set(HLN_COMMAND "ln" CACHE STRING "Command to create hard links to symlinks")
    endif()

    # Clean up test files
    file(REMOVE 
        "${CMAKE_BINARY_DIR}/hln_test.tmp"
        "${CMAKE_BINARY_DIR}/hln_test_sym.tmp"
        "${CMAKE_BINARY_DIR}/hln_test_hard.tmp"
    )
    
    message(STATUS "Hard link to symlink command set to: ${HLN_COMMAND}")
endfunction()

# Run all checks in the correct order
check_ln_capabilities()
check_ln_s_capabilities()
check_hln_capabilities()
