#!/usr/bin/env bash

if [[ $1 == "debug" ]]
then
    shift

	odin build tools/cubic_curve_generator/main.odin -file -show-timings -collection:src=src -out:build/cubic_curve_gen -o:none -debug
    exit 0
fi

odin build tools/cubic_curve_generator/main.odin -file -show-timings -collection:src=src -out:build/cubic_curve_generator -o:speed
