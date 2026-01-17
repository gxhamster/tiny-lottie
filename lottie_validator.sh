if [[ $1 == "debug" ]]
then
    shift

	odin build tools/lottie_validator/main.odin -file -show-timings -collection:src=src -out:build/lottie_validator -o:none -debug
    exit 0
fi

odin build tools/lottie_validator/main.odin -file -show-timings -collection:src=src -out:build/lottie_validator -o:speed