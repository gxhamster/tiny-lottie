mkdir build


if [[ $1 == "bench" ]]; then
    shift
    if [[ $1 == "debug" ]]; then
        odin build tools/benchmark/ -show-timings -collection:src=src -out:build/benchmark -o:none -debug
    else
        odin build tools/benchmark/ -show-timings -collection:src=src -out:build/benchmark -o:speed
    fi
fi

if [[ $1 == "validator" ]]; then
    shift
    if [[ $1 == "debug" ]]; then
        odin build tools/lottie_validator/main.odin -file -show-timings -collection:src=src -out:build/lottie_validator -o:none -debug
    else
        odin build tools/lottie_validator/main.odin -file -show-timings -collection:src=src -out:build/lottie_validator -o:speed
    fi
fi

if [[ $1 == "validator" ]]; then
    shift
    if [[ $1 == "debug" ]]; then
        odin build tools/cubic_curve_generator/main.odin -file -show-timings -collection:src=src -out:build/cubic_curve_gen -o:none -debug
    else
        odin build tools/cubic_curve_generator/main.odin -file -show-timings -collection:src=src -out:build/cubic_curve_generator -o:speed
    fi
fi


