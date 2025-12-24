package main

import "core:fmt"
import "core:os"
import "core:encoding/json"
import "core:math"

JsonLottie_Error :: enum {
    None,
    Missing_Required_Value,
    Outof_Range_Value,
}

Error :: union {
    os.Error,
    JsonLottie_Error,
    json.Unmarshal_Error
}

JSON_NUMBER_DEFAULT_VALUE :: max(f32);
JSON_INTEGER_DEFAULT_VALUE :: max(int);
JsonLottie_Animation :: struct {
    nm: string,
    layers: []json.Object,
    ver: i64,
    fr: f64,
    ip: f64,
    op: f64,
    w: i64,
    h: i64,
    assets: []json.Object,
    markers: []json.Object,
    slots: json.Object,
}

JsonLottie :: struct {
    animation: JsonLottie_Animation,
    raw: []u8
}


json_lottie_read_file_handle :: proc(fd: os.Handle,
                                     allocator := context.allocator,
                                     loc := #caller_location
                                     ) -> (data: JsonLottie, err: Error)
{

    data.raw = os.read_entire_file_from_handle_or_err(fd, allocator, loc) or_return;
    parsed_json, parse_err := json.parse(data.raw);
    if parse_err != nil {
        return JsonLottie{}, err;
    }

    root := parsed_json.(json.Object);
    if root["h"] == nil || root["w"] == nil || root["fr"] == nil ||
        root["op"] == nil || root["ip"] == nil
    {
        return JsonLottie{}, JsonLottie_Error.Missing_Required_Value;
    }

    data.animation.nm = root["nm"].(json.String);
    data.animation.fr = root["fr"].(json.Float);
    data.animation.op = root["op"].(json.Float);
    data.animation.ip = root["ip"].(json.Float);
    data.animation.w = i64(root["w"].(json.Float));
    data.animation.h = i64(root["h"].(json.Float));

    if data.animation.h < 0 {
        return JsonLottie{}, JsonLottie_Error.Outof_Range_Value;
    }
    if data.animation.w < 0 {
        return JsonLottie{}, JsonLottie_Error.Outof_Range_Value;
    }
    if data.animation.fr < 1 {
        return JsonLottie{}, JsonLottie_Error.Outof_Range_Value;
    }
    LOTTIE_VERSION_MIN :: 10000;
    if root["ver"] != nil && root["ver"].(json.Integer) < LOTTIE_VERSION_MIN {
        return JsonLottie{}, JsonLottie_Error.Outof_Range_Value;
    } else if root["ver"] != nil && root["ver"].(json.Integer) > LOTTIE_VERSION_MIN {
        data.animation.ver = root["ver"].(json.Integer);
    }


    return data, JsonLottie_Error.None;
}

json_lottie_read_file_name :: proc(file_name: string,
                                   allocator := context.allocator,
                                   loc := #caller_location
                                   ) -> (data: JsonLottie, err: Error)
{
    context.allocator = allocator;
    fd := os.open(file_name, os.O_RDONLY, 0) or_return
    defer os.close(fd);
    return json_lottie_read_file_handle(fd, allocator, loc);
}

main :: proc() {
    fmt.println("Welcome to tiny lottie project");
    lottie_struct, err := json_lottie_read_file_name("./data/Fire.json");
    fmt.eprintln(lottie_struct.animation);
}
