# -----------------------------------------------------------------------------
# Toolchain for libdragon N64 development
#
# Pass to CMake as CMAKE_TOOLCHAIN_FILE; do not include() it. Flags mirror libdragon's
# n64.mk at the LIBDRAGON_COMMIT pinned in this image's Dockerfile.
# -----------------------------------------------------------------------------

cmake_minimum_required(VERSION 3.27)

if(NOT DEFINED ENV{N64_INST} OR "$ENV{N64_INST}" STREQUAL "")
	message(FATAL_ERROR "N64_INST is not set: this toolchain file expects the libdragon SDK shipped by the toygine2.n64.toolchain image")
endif()

# -----------------------------------------------------------------------------
# Platform configuration

set(N64_SDK_INCLUDE "$ENV{N64_INST}/mips64-elf/include")
set(N64_SDK_LIB "$ENV{N64_INST}/mips64-elf/lib")
set(N64_SDK_BIN "$ENV{N64_INST}/bin")

set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR mips64)
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

set(CMAKE_C_COMPILER "${N64_SDK_BIN}/mips64-elf-gcc")
set(CMAKE_CXX_COMPILER "${N64_SDK_BIN}/mips64-elf-g++")
set(CMAKE_STRIP "${N64_SDK_BIN}/mips64-elf-strip" CACHE FILEPATH "")

# find_* stays inside the SDK root
set(CMAKE_FIND_ROOT_PATH "$ENV{N64_INST}/mips64-elf")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# n64.mk's N64_C_AND_CXX_FLAGS minus -g and -ffile-prefix-map; LIBDRAGON_PREVIEW=2
# mirrors n64.mk's `LIBDRAGON_PREVIEW ?= 2` default
set(N64_ARCH_SETTINGS "-march=vr4300 -mtune=vr4300 -mabi=o64")
set(N64_COMMON_FLAGS "${N64_ARCH_SETTINGS} -DLIBDRAGON_PREVIEW=2 -I${N64_SDK_INCLUDE}/newlib_overrides -I${N64_SDK_INCLUDE} -include ktls.h -DN64 -ffunction-sections -fdata-sections -falign-functions=32")
set(CMAKE_C_FLAGS_INIT "${N64_COMMON_FLAGS}")
set(CMAKE_CXX_FLAGS_INIT "${N64_COMMON_FLAGS}")
set(CMAKE_ASM_FLAGS_INIT "${N64_ARCH_SETTINGS} -I${N64_SDK_INCLUDE}")

# n64.mk links every ELF through g++ (ld inconsistencies with global ctors/dtors)
set(CMAKE_C_LINK_EXECUTABLE
	"<CMAKE_CXX_COMPILER> <FLAGS> <CMAKE_C_LINK_FLAGS> <LINK_FLAGS> <OBJECTS> -o <TARGET> <LINK_LIBRARIES>")
set(CMAKE_CXX_LINK_EXECUTABLE
	"<CMAKE_CXX_COMPILER> <FLAGS> <CMAKE_CXX_LINK_FLAGS> <LINK_FLAGS> <OBJECTS> -o <TARGET> <LINK_LIBRARIES>")

set(CMAKE_EXE_LINKER_FLAGS_INIT
	"-L${N64_SDK_LIB} -Wl,-T,${N64_SDK_LIB}/n64.ld -Wl,--gc-sections -Wl,--wrap,__do_global_ctors")
set(CMAKE_C_STANDARD_LIBRARIES_INIT "-lc -ldragon -lm -ldragonsys")
set(CMAKE_CXX_STANDARD_LIBRARIES_INIT "-lc -ldragon -lm -ldragonsys")

# -----------------------------------------------------------------------------
# Platform-specific helper utilities

function(n64_create_rom target)
	cmake_parse_arguments(PARSE_ARGV 1 N64 "" "OUTPUT;TITLE;CATEGORY;REGION;ELFCOMPRESS" "DFS;MSYM")

	if(NOT DEFINED N64_OUTPUT)
		set(N64_OUTPUT "${target}.z64")
	endif()
	get_filename_component(N64_OUTPUT "${N64_OUTPUT}" ABSOLUTE BASE_DIR "${CMAKE_CURRENT_BINARY_DIR}")
	if(NOT DEFINED N64_TITLE)
		set(N64_TITLE "Made with libdragon")
	endif()
	if(NOT DEFINED N64_ELFCOMPRESS)
		set(N64_ELFCOMPRESS 1)
	endif()

	set(N64_TOOL_ARGS -T --title "${N64_TITLE}")
	if(DEFINED N64_CATEGORY)
		list(APPEND N64_TOOL_ARGS -C "${N64_CATEGORY}")
	endif()
	if(DEFINED N64_REGION)
		list(APPEND N64_TOOL_ARGS -R "${N64_REGION}")
	endif()

	set(sym "$<TARGET_FILE_DIR:${target}>/$<TARGET_FILE_BASE_NAME:${target}>.sym")
	set(stripped "$<TARGET_FILE_DIR:${target}>/$<TARGET_FILE_BASE_NAME:${target}>.stripped")

	add_custom_command(TARGET ${target} POST_BUILD
		COMMAND "${N64_SDK_BIN}/n64sym" --all "$<TARGET_FILE:${target}>" "${sym}"
		COMMAND "${CMAKE_COMMAND}" -E copy "$<TARGET_FILE:${target}>" "${stripped}"
		COMMAND "${N64_SDK_BIN}/mips64-elf-strip" -s "${stripped}"
		COMMAND "${N64_SDK_BIN}/n64elfcompress" -o "$<TARGET_FILE_DIR:${target}>" -c "${N64_ELFCOMPRESS}" "${stripped}"
		COMMAND "${N64_SDK_BIN}/n64tool" ${N64_TOOL_ARGS} --output "${N64_OUTPUT}.tmp" --align 256
			"${stripped}" "${sym}" ${N64_DFS} ${N64_MSYM}
		COMMAND "${CMAKE_COMMAND}" -E rename "${N64_OUTPUT}.tmp" "${N64_OUTPUT}"
		BYPRODUCTS "${N64_OUTPUT}"
		COMMENT "Building N64 ROM for ${target}"
		VERBATIM
	)
endfunction()
