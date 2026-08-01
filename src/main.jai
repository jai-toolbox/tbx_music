NOTE_EVENT_MAX_NOTES :: 8;

Note_Duration_Mode :: enum {
    FIXED;
    UNTIL_NEXT_NOTE;
}

Note_Event_Kind :: enum {
    NOTE;
    REST;
}

Note_Event :: struct {
    sixteenth_offset: int;
    kind: Note_Event_Kind;
    note_count: int;
    relative_notes: [NOTE_EVENT_MAX_NOTES] int;
    duration_mode: Note_Duration_Mode;
    duration_sixteenths: float;
}

Render_Config :: struct {
    bpm: int = 134;
    bars: int = 8;
    output_path: string = "out/song_two.wav";
}

Noise_State :: struct {
    value: u32 = 0x12345678;
}

main :: () {
    render_song_from_command_line();
}

maybe_run_debug_or_oracle_command :: () -> bool {
    if maybe_run_reverb_oracle() return true;
    if maybe_run_low_pass_oracle() return true;
    if maybe_run_variable_delay_oracle() return true;
    if maybe_run_pan2_oracle() return true;
    if maybe_run_debug_sine() return true;
    if maybe_run_debug_synth_events() return true;
    if maybe_run_debug_synth_pulse() return true;

    return false;
}

render_song_from_command_line :: () {
    if maybe_run_debug_or_oracle_command() return;

    config := parse_args();

    if config.bpm < 30  config.bpm = 30;
    if config.bpm > 300 config.bpm = 300;
    if config.bars < 1   config.bars = 1;
    if config.bars > 64  config.bars = 64;

    samples := render_song_two(config.bpm, config.bars);
    defer array_free(samples);

    apply_constant_low_pass_stereo(samples, 3600.0);
    apply_reverb_to_stereo_signal(samples, dry_gain = 0.92, wet_gain = 0.34);

    success := write_wav_16_stereo(config.output_path, samples);
    if !success {
        print("Failed to write %\n", config.output_path);
        return;
    }

    seconds := cast(float) samples.count / cast(float) SAMPLE_RATE_HZ;
    print("Wrote % (% bpm, % bars, % frames, % seconds)\n", config.output_path, config.bpm, config.bars, samples.count, seconds);
    print("Try: aplay %\n", config.output_path);
}

maybe_run_debug_synth_pulse :: () -> bool {
    args := get_command_line_arguments();
    defer array_reset(*args);

    if args.count < 2 return false;
    if args[1] != "--debug-synth-pulse" return false;

    events := parse_note_pattern(synth_pulse_pattern_notation(), .FIXED, 0.78);
    defer array_free(events);

    phrase_length_sixteenths := count_note_pattern_sixteenths(synth_pulse_pattern_notation());
    print("pulse phrase length=% sixteenths (% bars)\n", phrase_length_sixteenths, cast(float) phrase_length_sixteenths / 16.0);

    for event_index: 0..events.count - 1 {
        event := events[event_index];
        print("pulse % offset=% kind=% note_count=% first_note=% mode=% duration_sixteenths=%\n", event_index, event.sixteenth_offset, event.kind, event.note_count, event.relative_notes[0], event.duration_mode, event.duration_sixteenths);
    }

    return true;
}

maybe_run_debug_synth_events :: () -> bool {
    args := get_command_line_arguments();
    defer array_reset(*args);

    if args.count < 2 return false;
    if args[1] != "--debug-synth-events" return false;

    events := parse_note_pattern(synth_pattern_notation(), .UNTIL_NEXT_NOTE, 0.0);
    defer array_free(events);
    phrase_length_sixteenths := 4 * 16;
    for event_index: 0..events.count - 1 {
        event := events[event_index];
        duration := note_event_duration_sixteenths(events, event_index, phrase_length_sixteenths);
        print("event % offset=% kind=% note_count=% first_note=% mode=% duration_sixteenths=%\n", event_index, event.sixteenth_offset, event.kind, event.note_count, event.relative_notes[0], event.duration_mode, duration);
    }

    return true;
}

maybe_run_debug_sine :: () -> bool {
    args := get_command_line_arguments();
    defer array_reset(*args);

    if args.count < 2 return false;
    if args[1] != "--debug-sine" return false;

    output_path := "out/sine.wav";
    seconds := 3.0;
    frequency := 440.0;
    amp := 0.80;

    if args.count >= 3 output_path = args[2];

    sample_count := cast(int) ceil(seconds * cast(float) SAMPLE_RATE_HZ);
    samples: [..] float;
    array_resize(*samples, sample_count);
    defer array_free(samples);

    for i: 0..sample_count - 1 {
        t := cast(float) i / cast(float) SAMPLE_RATE_HZ;
        samples[i] = amp * sin(TAU * frequency * t);
    }

    success := write_wav_16_mono(output_path, samples);
    if !success {
        print("Failed to write debug sine: %\n", output_path);
        return true;
    }

    print("Wrote debug sine % (% Hz, amp %, % samples)\n", output_path, frequency, amp, sample_count);
    return true;
}

maybe_run_reverb_oracle :: () -> bool {
    args := get_command_line_arguments();
    defer array_reset(*args);

    if args.count < 2 return false;
    if args[1] != "--reverb-oracle" return false;

    output_path := "oracle/jai_reverb.raw";
    sample_count := SAMPLE_RATE_HZ * 3;

    if args.count >= 3 output_path = args[2];
    if args.count >= 4 {
        value, ok, _ := string_to_int(args[3]);
        if ok sample_count = value;
    }

    samples: [..] float;
    array_resize(*samples, sample_count);
    defer array_free(samples);

    reverb: Reverb;
    reverb_init(*reverb, cast(float) SAMPLE_RATE_HZ, feedback = 0.93, low_pass_frequency = 8500.0, pitch_mod = 1.0);
    defer reverb_free(*reverb);

    for i: 0..sample_count - 1 {
        input := reverb_oracle_input(i);
        samples[i] = reverb_process_mono(*reverb, input);
    }

    directory := path_strip_filename(output_path);
    if directory.count > 0 make_directory_if_it_does_not_exist(directory, recursive = true);

    ok := write_entire_file(output_path, samples.data, samples.count * size_of(float));
    if !ok {
        print("Failed to write oracle output: %\n", output_path);
    } else {
        print("Wrote Jai reverb oracle output: % (% samples)\n", output_path, sample_count);
    }

    return true;
}

maybe_run_low_pass_oracle :: () -> bool {
    args := get_command_line_arguments();
    defer array_reset(*args);

    if args.count < 2 return false;
    if args[1] != "--low-pass-oracle" return false;

    output_path := "oracle/jai_low_pass.raw";
    sample_count := SAMPLE_RATE_HZ * 3;

    if args.count >= 3 output_path = args[2];
    if args.count >= 4 {
        value, ok, _ := string_to_int(args[3]);
        if ok sample_count = value;
    }

    samples: [..] float;
    array_resize(*samples, sample_count);
    defer array_free(samples);

    filter: Low_Pass;
    low_pass_init(*filter, cast(float) SAMPLE_RATE_HZ);

    for i: 0..sample_count - 1 {
        input := low_pass_oracle_input(i);
        filter.frequency = low_pass_oracle_cutoff(i, sample_count);
        samples[i] = low_pass_process(*filter, input);
    }

    directory := path_strip_filename(output_path);
    if directory.count > 0 make_directory_if_it_does_not_exist(directory, recursive = true);

    ok := write_entire_file(output_path, samples.data, samples.count * size_of(float));
    if !ok {
        print("Failed to write oracle output: %\n", output_path);
    } else {
        print("Wrote Jai low-pass oracle output: % (% samples)\n", output_path, sample_count);
    }

    return true;
}

maybe_run_variable_delay_oracle :: () -> bool {
    args := get_command_line_arguments();
    defer array_reset(*args);

    if args.count < 2 return false;
    if args[1] != "--variable-delay-oracle" return false;

    output_path := "oracle/jai_vdelay.raw";
    sample_count := SAMPLE_RATE_HZ * 3;

    if args.count >= 3 output_path = args[2];
    if args.count >= 4 {
        value, ok, _ := string_to_int(args[3]);
        if ok sample_count = value;
    }

    samples: [..] float;
    array_resize(*samples, sample_count);
    defer array_free(samples);

    delay: Variable_Delay;
    variable_delay_init(*delay, cast(float) SAMPLE_RATE_HZ, 0.021);
    defer variable_delay_free(*delay);
    delay.feedback = 0.31;

    for i: 0..sample_count - 1 {
        delay.delay_seconds = variable_delay_oracle_delay(i);
        samples[i] = variable_delay_process(*delay, variable_delay_oracle_input(i));
    }

    directory := path_strip_filename(output_path);
    if directory.count > 0 make_directory_if_it_does_not_exist(directory, recursive = true);

    ok := write_entire_file(output_path, samples.data, samples.count * size_of(float));
    if !ok {
        print("Failed to write oracle output: %\n", output_path);
    } else {
        print("Wrote Jai variable-delay oracle output: % (% samples)\n", output_path, sample_count);
    }

    return true;
}

maybe_run_pan2_oracle :: () -> bool {
    args := get_command_line_arguments();
    defer array_reset(*args);

    if args.count < 2 return false;
    if args[1] != "--pan2-oracle" return false;

    output_path := "oracle/jai_pan2.raw";
    sample_count := SAMPLE_RATE_HZ;

    if args.count >= 3 output_path = args[2];
    if args.count >= 4 {
        value, ok, _ := string_to_int(args[3]);
        if ok sample_count = value;
    }

    samples: [..] Stereo_Sample;
    array_resize(*samples, sample_count);
    defer array_free(samples);

    pan: Pan_2;
    pan2_init(*pan);

    for i: 0..sample_count - 1 {
        pan.pan = pan2_oracle_pan(i);
        pan.mode = pan2_oracle_mode(i);
        samples[i] = pan2_process(*pan, pan2_oracle_input(i));
    }

    directory := path_strip_filename(output_path);
    if directory.count > 0 make_directory_if_it_does_not_exist(directory, recursive = true);

    ok := write_entire_file(output_path, samples.data, samples.count * size_of(Stereo_Sample));
    if !ok {
        print("Failed to write oracle output: %\n", output_path);
    } else {
        print("Wrote Jai pan2 oracle output: % (% frames)\n", output_path, sample_count);
    }

    return true;
}

reverb_oracle_input :: (sample_index: int) -> float {
    t := cast(float) sample_index / cast(float) SAMPLE_RATE_HZ;
    env := ifx sample_index < 12000 then 1.0 else 0.0;
    return env * (0.35 * sin(TAU * 440.0 * t) + 0.20 * sin(TAU * 660.0 * t));
}

low_pass_oracle_input :: (sample_index: int) -> float {
    if sample_index == 0 return 1.0;
    if sample_index == 4096 return -0.6;
    if sample_index == 12000 return 0.35;
    if (sample_index % 997) == 0 return 0.18;
    return 0.0;
}

low_pass_oracle_cutoff :: (sample_index: int, sample_count: int) -> float {
    progress := cast(float) sample_index / cast(float) max(1, sample_count - 1);
    return linear_interpolate(12000.0, 650.0, progress);
}

variable_delay_oracle_input :: (sample_index: int) -> float {
    if sample_index == 0 return 1.0;
    if sample_index == 307 return 0.5;
    if sample_index == 1024 return -0.45;
    if (sample_index % 997) == 0 return -0.35;
    if (sample_index % 211) == 0 return 0.12;
    return 0.0;
}

variable_delay_oracle_delay :: (sample_index: int) -> float {
    segment := sample_index % 5000;
    progress := cast(float) segment / 4999.0;
    return linear_interpolate(0.003, 0.017, progress);
}

pan2_oracle_input :: (sample_index: int) -> float {
    segment := sample_index % 251;
    return (cast(float) segment - 125.0) / 125.0;
}

pan2_oracle_pan :: (sample_index: int) -> float {
    segment := sample_index % 4096;
    progress := cast(float) segment / 4095.0;
    return linear_interpolate(-1.0, 1.0, progress);
}

pan2_oracle_mode :: (sample_index: int) -> int {
    return (sample_index / 4096) % 4;
}

parse_args :: () -> Render_Config {
    config: Render_Config;
    args := get_command_line_arguments();
    defer array_reset(*args);

    i := 1;
    while i < args.count {
        arg := args[i];

        if (arg == "--help") || (arg == "-h") {
            print_usage();
            exit(0);
        }

        if (arg == "--bpm") && (i + 1 < args.count) {
            value, ok, _ := string_to_int(args[i + 1]);
            if ok config.bpm = value;
            i += 2;
            continue;
        }

        if (arg == "--bars") && (i + 1 < args.count) {
            value, ok, _ := string_to_int(args[i + 1]);
            if ok config.bars = value;
            i += 2;
            continue;
        }

        if (arg == "--out") && (i + 1 < args.count) {
            config.output_path = args[i + 1];
            i += 2;
            continue;
        }

        print("Ignoring unknown argument: %\n", arg);
        i += 1;
    }

    return config;
}

print_usage :: () {
    print("tbx_music: synthesize a small kick + snare + hihat + sine synth beat to WAV.\n");
    print("Usage: bin/tbx_music [--bpm 135] [--bars 47] [--out out/song_two.wav]\n");
    print("       bin/tbx_music --debug-sine [out/sine.wav]\n");
}

parse_note_pattern :: (notation: string, duration_mode: Note_Duration_Mode, duration_sixteenths: float) -> [..] Note_Event {
    events: [..] Note_Event;
    current_sixteenth := 0;
    cursor := 0;
    bracket_depth := 0;

    while cursor < notation.count {
        c := notation[cursor];

        if c == #char "[" {
            bracket_depth += 1;
            cursor += 1;
            continue;
        }

        if c == #char "]" {
            if bracket_depth > 0 bracket_depth -= 1;
            cursor += 1;
            continue;
        }

        if is_note_notation_separator(c) {
            cursor += 1;
            continue;
        }

        token_sixteenths := ifx bracket_depth > 0 then 1 else 4;

        if c == #char "-" {
            if duration_mode == .UNTIL_NEXT_NOTE {
                array_add(*events, make_rest_event(current_sixteenth, duration_mode));
            }
            current_sixteenth += token_sixteenths;
            cursor += 1;
            continue;
        }

        if c == #char "~" {
            current_sixteenth += token_sixteenths;
            cursor += 1;
            continue;
        }

        if c == #char "(" {
            event := make_note_event(current_sixteenth, duration_mode, duration_sixteenths);
            cursor += 1;

            while cursor < notation.count {
                if notation[cursor] == #char ")" {
                    cursor += 1;
                    break;
                }

                if is_note_notation_separator(notation[cursor]) {
                    cursor += 1;
                    continue;
                }

                if notation[cursor] >= #char "0" && notation[cursor] <= #char "9" {
                    if event.note_count < NOTE_EVENT_MAX_NOTES {
                        event.relative_notes[event.note_count] = parse_relative_note(notation, *cursor);
                        event.note_count += 1;
                    } else {
                        parse_relative_note(notation, *cursor);
                    }
                    continue;
                }

                cursor += 1;
            }

            if event.note_count > 0 array_add(*events, event);
            current_sixteenth += token_sixteenths;
            continue;
        }

        if c >= #char "0" && c <= #char "9" {
            event := make_note_event(current_sixteenth, duration_mode, duration_sixteenths);
            event.relative_notes[0] = parse_relative_note(notation, *cursor);
            event.note_count = 1;
            array_add(*events, event);
            current_sixteenth += token_sixteenths;
            continue;
        }

        cursor += 1;
    }

    return events;
}

make_rest_event :: (sixteenth_offset: int, duration_mode: Note_Duration_Mode) -> Note_Event {
    event: Note_Event;
    event.sixteenth_offset = sixteenth_offset;
    event.kind = .REST;
    event.duration_mode = duration_mode;
    return event;
}

make_note_event :: (sixteenth_offset: int, duration_mode: Note_Duration_Mode, duration_sixteenths: float) -> Note_Event {
    event: Note_Event;
    event.sixteenth_offset = sixteenth_offset;
    event.kind = .NOTE;
    event.duration_mode = duration_mode;
    event.duration_sixteenths = duration_sixteenths;
    return event;
}

parse_relative_note :: (notation: string, cursor: *int) -> int {
    relative_note := 0;

    while cursor.* < notation.count && notation[cursor.*] >= #char "0" && notation[cursor.*] <= #char "9" {
        relative_note = relative_note * 10 + cast(int) (notation[cursor.*] - #char "0");
        cursor.* += 1;
    }

    while cursor.* < notation.count {
        if notation[cursor.*] == #char "," {
            relative_note -= 12;
            cursor.* += 1;
            continue;
        }

        if notation[cursor.*] == #char "'" {
            relative_note += 12;
            cursor.* += 1;
            continue;
        }

        break;
    }

    return relative_note;
}

count_note_pattern_sixteenths :: (notation: string) -> int {
    sixteenth_count := 0;
    cursor := 0;
    bracket_depth := 0;

    while cursor < notation.count {
        c := notation[cursor];

        if c == #char "[" {
            bracket_depth += 1;
            cursor += 1;
            continue;
        }

        if c == #char "]" {
            if bracket_depth > 0 bracket_depth -= 1;
            cursor += 1;
            continue;
        }

        if is_note_notation_separator(c) {
            cursor += 1;
            continue;
        }

        token_sixteenths := ifx bracket_depth > 0 then 1 else 4;

        if c == #char "-" || c == #char "~" {
            sixteenth_count += token_sixteenths;
            cursor += 1;
            continue;
        }

        if c == #char "(" {
            cursor += 1;
            while cursor < notation.count {
                if notation[cursor] == #char ")" {
                    cursor += 1;
                    break;
                }

                if notation[cursor] >= #char "0" && notation[cursor] <= #char "9" {
                    parse_relative_note(notation, *cursor);
                    continue;
                }

                cursor += 1;
            }

            sixteenth_count += token_sixteenths;
            continue;
        }

        if c >= #char "0" && c <= #char "9" {
            parse_relative_note(notation, *cursor);
            sixteenth_count += token_sixteenths;
            continue;
        }

        cursor += 1;
    }

    return sixteenth_count;
}

is_note_notation_separator :: (c: u8) -> bool {
    if c == #char " "  return true;
    if c == #char "\t" return true;
    if c == #char "\n" return true;
    if c == #char "\r" return true;
    return false;
}

add_matching_note_event :: (
    samples: [] float,
    events: [] Note_Event,
    phrase_sixteenth_index: int,
    current_sixteenth: int,
    phrase_length_sixteenths: int,
    seconds_per_sixteenth: float,
    total_sixteenths: int,
    amp: float
) {
    for event_index: 0..events.count - 1 {
        event := events[event_index];
        if phrase_sixteenth_index != event.sixteenth_offset continue;
        if event.kind != .NOTE return;

        duration_sixteenths := note_event_duration_sixteenths(events, event_index, phrase_length_sixteenths);
        remaining_sixteenths := total_sixteenths - current_sixteenth;
        if duration_sixteenths > cast(float) remaining_sixteenths duration_sixteenths = cast(float) remaining_sixteenths;

        start_seconds := cast(float) current_sixteenth * seconds_per_sixteenth;
        duration_seconds := duration_sixteenths * seconds_per_sixteenth;
        chord_gain := amp / sqrt(cast(float) max(1, event.note_count));
        for note_index: 0..event.note_count - 1 {
            semitones_from_c4 := MELODY_ANCHOR + event.relative_notes[note_index];
            add_sine_synth_note(samples, start_seconds, duration_seconds, semitones_from_c4, chord_gain);
        }
    }
}

add_matching_bass_event :: (
    samples: [] float,
    events: [] Note_Event,
    phrase_sixteenth_index: int,
    current_sixteenth: int,
    phrase_length_sixteenths: int,
    seconds_per_sixteenth: float,
    total_sixteenths: int,
    amp: float
) {
    for event_index: 0..events.count - 1 {
        event := events[event_index];
        if phrase_sixteenth_index != event.sixteenth_offset continue;
        if event.kind != .NOTE return;

        duration_sixteenths := note_event_duration_sixteenths(events, event_index, phrase_length_sixteenths);
        remaining_sixteenths := total_sixteenths - current_sixteenth;
        if duration_sixteenths > cast(float) remaining_sixteenths duration_sixteenths = cast(float) remaining_sixteenths;

        start_seconds := cast(float) current_sixteenth * seconds_per_sixteenth;
        duration_seconds := duration_sixteenths * seconds_per_sixteenth;
        chord_gain := amp / sqrt(cast(float) max(1, event.note_count));
        for note_index: 0..event.note_count - 1 {
            semitones_from_c4 := MELODY_ANCHOR + event.relative_notes[note_index];
            add_bass_synth_note(samples, start_seconds, duration_seconds, semitones_from_c4, chord_gain);
        }
    }
}

note_event_duration_sixteenths :: (events: [] Note_Event, event_index: int, phrase_length_sixteenths: int) -> float {
    event := events[event_index];
    if event.duration_mode == .FIXED return event.duration_sixteenths;

    next_sixteenth_offset := phrase_length_sixteenths;
    for i: 0..events.count - 1 {
        if events[i].sixteenth_offset <= event.sixteenth_offset continue;
        if events[i].sixteenth_offset < next_sixteenth_offset next_sixteenth_offset = events[i].sixteenth_offset;
    }

    return cast(float) (next_sixteenth_offset - event.sixteenth_offset);
}

add_melody_step :: (samples: [] float, start_sixteenth: int, relative_note: int, duration_sixteenths: int, seconds_per_sixteenth: float, total_sixteenths: int) {
    if start_sixteenth >= total_sixteenths return;

    remaining_sixteenths := total_sixteenths - start_sixteenth;
    actual_duration_sixteenths := min(duration_sixteenths, remaining_sixteenths);
    start_seconds := cast(float) start_sixteenth * seconds_per_sixteenth;
    duration_seconds := cast(float) actual_duration_sixteenths * seconds_per_sixteenth * 0.96;
    semitones_from_c4 := MELODY_ANCHOR + relative_note;
    add_sine_synth_note(samples, start_seconds, duration_seconds, semitones_from_c4, 0.23);
}

add_kick :: (samples: [] float, start_seconds: float, amp: float) {
    start := cast(int) floor(start_seconds * cast(float) SAMPLE_RATE_HZ);
    length := cast(int) (0.42 * cast(float) SAMPLE_RATE_HZ);

    phase := 0.0;
    for i: 0..length - 1 {
        index := start + i;
        if index < 0 || index >= samples.count break;

        t := cast(float) i / cast(float) SAMPLE_RATE_HZ;
        env := exp(-t * 10.0);
        click_env := exp(-t * 95.0);
        pitch := 48.0 + 92.0 * exp(-t * 28.0);
        phase += TAU * pitch / cast(float) SAMPLE_RATE_HZ;

        tone := sin(phase) * env;
        click := sin(TAU * 1500.0 * t) * click_env;
        samples[index] += amp * (0.92 * tone + 0.16 * click);
    }
}

add_snare :: (samples: [] float, start_seconds: float, amp: float, noise: *Noise_State) {
    start := cast(int) floor(start_seconds * cast(float) SAMPLE_RATE_HZ);
    length := cast(int) (0.28 * cast(float) SAMPLE_RATE_HZ);

    for i: 0..length - 1 {
        index := start + i;
        if index < 0 || index >= samples.count break;

        t := cast(float) i / cast(float) SAMPLE_RATE_HZ;
        noise_env := exp(-t * 22.0);
        body_env := exp(-t * 34.0);

        noisy := white_noise(noise) * noise_env;
        body := sin(TAU * 185.0 * t) * body_env;
        click := sin(TAU * 2800.0 * t) * exp(-t * 90.0);

        samples[index] += amp * (0.72 * noisy + 0.24 * body + 0.10 * click);
    }
}

add_spark :: (samples: [] float, start_seconds: float, amp: float, noise: *Noise_State) {
    start := cast(int) floor(start_seconds * cast(float) SAMPLE_RATE_HZ);
    length := cast(int) (0.045 * cast(float) SAMPLE_RATE_HZ);

    previous := 0.0;
    for i: 0..length - 1 {
        index := start + i;
        if index < 0 || index >= samples.count break;

        t := cast(float) i / cast(float) SAMPLE_RATE_HZ;
        env := exp(-t * 95.0);
        n := white_noise(noise);
        bright_noise := n - previous * 0.78;
        previous = n;

        click := sin(TAU * 4200.0 * t) * exp(-t * 145.0);
        glass := sin(TAU * 9800.0 * t) * exp(-t * 120.0);
        samples[index] += amp * env * (0.78 * bright_noise + 0.18 * click + 0.14 * glass);
    }
}

add_hihat :: (samples: [] float, start_seconds: float, duration: float, amp: float, noise: *Noise_State) {
    start := cast(int) floor(start_seconds * cast(float) SAMPLE_RATE_HZ);
    length := cast(int) (duration * cast(float) SAMPLE_RATE_HZ);

    previous := 0.0;
    for i: 0..length - 1 {
        index := start + i;
        if index < 0 || index >= samples.count break;

        t := cast(float) i / cast(float) SAMPLE_RATE_HZ;
        env := exp(-t * 70.0);
        n := white_noise(noise);
        high_passish := n - previous * 0.86;
        previous = n;

        metallic := sin(TAU * 8200.0 * t) * 0.18 + sin(TAU * 11200.0 * t) * 0.12;
        samples[index] += amp * env * (0.82 * high_passish + metallic);
    }
}

white_noise :: (state: *Noise_State) -> float {
    state.value = state.value * 1664525 + 1013904223;
    v := (state.value >> 8) & 0xFFFF;
    return (cast(float) v / 32767.5) - 1.0;
}

midi_note_to_frequency :: (midi_note: int) -> float {
    return 440.0 * pow(2.0, cast(float) (midi_note - 69) / 12.0);
}

#load "song_one.jai";
#load "song_two.jai";

#import "Basic";
#import "File";
#import "File_Utilities";
#import "Math";
#import "String";
#import "tbx/music";
