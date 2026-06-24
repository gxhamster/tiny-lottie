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
) else if "%~1" == "bench_decode" (
    shift /1
    if "%~1" == "debug" (
        odin build tools\decoder_benchmark\ -show-timings -collection:src=src -out:build\decoder_benchmark.exe -o:none -debug
    ) else (
        odin build tools\decoder_benchmark\ -show-timings -collection:src=src -out:build\decoder_benchmark.exe -o:speed
    )
) else if "%~1" == "simdjson_bench" (
    shift /1
    if "%~1" == "debug" (
        "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\cl.exe" /EHsc tools\simdjson\bench.cpp tools\simdjson\simdjson.cpp /link /out:"build\simdjson.exe"
    ) else (
        "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\cl.exe" /EHsc /O2 tools\simdjson\bench.cpp tools\simdjson\simdjson.cpp /link /out:"build\simdjson.exe"
    )
) else if "%~1" == "sample_app" (
    shift /1
    if "%~1" == "debug" (
        odin build tools\sample_app\ -show-timings -collection:src=src -out:build\sample_app.exe -o:none -debug
    ) else (
        odin build tools\sample_app\ -show-timings -collection:src=src -out:build\sample_app.exe -o:speed
    )
)


