@echo off

if not exist build mkdir build

if "%~1" == "bench" (
    shift /1
    if "%~1" == "debug" (
        odin build tools\benchmark\ -show-timings -collection:src=src -out:build\benchmark.exe -o:none -debug
    ) else (
        odin build tools\benchmark\ -show-timings -collection:src=src -out:build\benchmark.exe -o:speed
    )
) else if "%~1" == "validator" (
    shift /1
    if "%~1" == "debug" (
        odin build tools\lottie_validator\main.odin -file -show-timings -collection:src=src -out:build\lottie_validator.exe -o:none -debug
    ) else (
        odin build tools\lottie_validator\main.odin -file -show-timings -collection:src=src -out:build\lottie_validator.exe -o:speed
    )
) else if "%~1" == "cubic" (
    shift /1
    if "%~1" == "debug" (
        odin build tools\cubic_curve_generator\main.odin -file -show-timings -collection:src=src -out:build\cubic_curve_gen.exe -o:none -debug
    ) else (
        odin build tools\cubic_curve_generator\main.odin -file -show-timings -collection:src=src -out:build\cubic_curve_gen.exe -o:speed
    )
)


