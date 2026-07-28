MELODY_ANCHOR :: 5;
BREAKDOWN_LOW_PASS_HZ :: 800.0;
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
    bpm: int = 135;
    bars: int = 70;
    output_path: string = "out/song.wav";
}

Noise_State :: struct {
    value: u32 = 0x12345678;
}

main :: () {
    if maybe_run_reverb_oracle() return;
    if maybe_run_low_pass_oracle() return;
    if maybe_run_debug_sine() return;
    if maybe_run_debug_synth_events() return;
    if maybe_run_debug_synth_pulse() return;

    config := parse_args();

    if config.bpm < 30  config.bpm = 30;
    if config.bpm > 300 config.bpm = 300;
    if config.bars < 1   config.bars = 1;
    if config.bars > 64  config.bars = 64;

    samples := render_song(config.bpm, config.bars);
    defer array_free(samples);

    success := write_wav_16_mono(config.output_path, samples);
    if !success {
        print("Failed to write %\n", config.output_path);
        return;
    }

    seconds := cast(float) samples.count / cast(float) SAMPLE_RATE_HZ;
    print("Wrote % (% bpm, % bars, % samples, % seconds)\n", config.output_path, config.bpm, config.bars, samples.count, seconds);
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
    print("Usage: bin/tbx_music [--bpm 135] [--bars 47] [--out out/song.wav]\n");
    print("       bin/tbx_music --debug-sine [out/sine.wav]\n");
}

render_song :: (bpm: int, bars: int) -> [..] float {

    beats_per_bar := 4;
    sixteenths_per_bar := 16;
    total_sixteenths := bars * sixteenths_per_bar;
    seconds_per_beat := 60.0 / cast(float) bpm;
    seconds_per_sixteenth := seconds_per_beat / 4.0;
    tail_seconds := 0.55;
    total_seconds := cast(float) bars * cast(float) beats_per_bar * seconds_per_beat + tail_seconds;
    total_samples := cast(int) ceil(total_seconds * cast(float) SAMPLE_RATE_HZ);

    samples: [..] float;
    array_resize(*samples, total_samples);
    for 0..samples.count - 1 samples[it] = 0.0;

    noise: Noise_State;
    hihat: [..] float;
    array_resize(*hihat, total_samples);
    defer array_free(hihat);
    for 0..hihat.count - 1 hihat[it] = 0.0;

    breakdown_drums: [..] float;
    array_resize(*breakdown_drums, total_samples);
    defer array_free(breakdown_drums);
    for 0..breakdown_drums.count - 1 breakdown_drums[it] = 0.0;

    breakdown_melody: [..] float;
    array_resize(*breakdown_melody, total_samples);
    defer array_free(breakdown_melody);
    for 0..breakdown_melody.count - 1 breakdown_melody[it] = 0.0;

    breakdown_sparks: [..] float;
    array_resize(*breakdown_sparks, total_samples);
    defer array_free(breakdown_sparks);
    for 0..breakdown_sparks.count - 1 breakdown_sparks[it] = 0.0;

    intro_melody: [..] float;
    array_resize(*intro_melody, total_samples);
    defer array_free(intro_melody);
    for 0..intro_melody.count - 1 intro_melody[it] = 0.0;

    dry_synth: [..] float;
    array_resize(*dry_synth, total_samples);
    defer array_free(dry_synth);
    for 0..dry_synth.count - 1 dry_synth[it] = 0.0;

    reverbed_synth: [..] float;
    array_resize(*reverbed_synth, total_samples);
    defer array_free(reverbed_synth);
    for 0..reverbed_synth.count - 1 reverbed_synth[it] = 0.0;

    bass: [..] float;
    array_resize(*bass, total_samples);
    defer array_free(bass);
    for 0..bass.count - 1 bass[it] = 0.0;

    spark_noise: Noise_State;
    spark_noise.value = 0x62F3A91D;

    synth_events := parse_note_pattern(synth_pattern_notation(), .UNTIL_NEXT_NOTE, 0.0);
    defer array_free(synth_events);
    intro_melody_events := parse_note_pattern(intro_melody_phrase_notation(), .UNTIL_NEXT_NOTE, 0.0);
    defer array_free(intro_melody_events);
    synth_pulse_events := parse_note_pattern(synth_pulse_pattern_notation(), .FIXED, 0.78);
    defer array_free(synth_pulse_events);
    synth_pulse_phrase_sixteenths := count_note_pattern_sixteenths(synth_pulse_pattern_notation());
    bass_events := parse_note_pattern(bass_pattern_notation(), .FIXED, 15.5);
    defer array_free(bass_events);
    bass_phrase_sixteenths := count_note_pattern_sixteenths(bass_pattern_notation());
    breakdown_melody_events := parse_note_pattern(breakdown_melody_notation(), .FIXED, 3.84);
    defer array_free(breakdown_melody_events);
    breakdown_melody_phrase_sixteenths := count_note_pattern_sixteenths(breakdown_melody_notation());

    for current_sixteenth: 0..total_sixteenths - 1 {

        current_seconds := cast(float) current_sixteenth * seconds_per_sixteenth;
        beat_index_in_bar := (current_sixteenth / 4) % 4;
        sixteenth_index_in_beat := current_sixteenth % 4;
        bar_index := current_sixteenth / sixteenths_per_bar;
        sixteenth_index_in_bar := current_sixteenth % sixteenths_per_bar;

        // sixteenth-note hihat, with occasional 32nd-note fills on one beat of the bar.
        if !(bar_index >= 24 && bar_index <= 39 || bar_index >= 63) {
            amp := ifx sixteenth_index_in_beat == 0 then 0.24 else 0.16;
            fill_beat := hihat_fill_beat_for_bar(bar_index);
            if beat_index_in_bar == fill_beat {
                if beat_index_in_bar % 3 == 0 {
                    add_hihat(hihat, current_seconds, 0.013, amp * 0.88, *noise);
                    add_hihat(hihat, current_seconds + seconds_per_sixteenth * 0.25, 0.016, amp * 0.74, *noise);
                    add_hihat(hihat, current_seconds + 2 * seconds_per_sixteenth * 0.25, 0.016, amp * 0.74, *noise);
                    add_hihat(hihat, current_seconds + 3 * seconds_per_sixteenth * 0.25, 0.016, amp * 0.74, *noise);
                } else {
                    add_hihat(hihat, current_seconds, 0.026, amp * 0.88, *noise);
                    add_hihat(hihat, current_seconds + seconds_per_sixteenth * 0.5, 0.026, amp * 0.74, *noise);
                }
            } else {
                add_hihat(hihat, current_seconds, 0.045, amp, *noise);
            }
        }

        // bass drum on 1, 2&, and 3&.
        if sixteenth_index_in_bar == 0 || sixteenth_index_in_bar == 6 || sixteenth_index_in_bar == 10 {
            if bar_index >= 24 && bar_index <= 39 {
                add_kick(breakdown_drums, current_seconds, 0.95);
            } else {
                add_kick(samples, current_seconds, 0.95);
            }
        }

        // backbeat spark on beats 2 and 4.
        if sixteenth_index_in_beat == 0 && (beat_index_in_bar == 1 || beat_index_in_bar == 3) {
            if bar_index >= 24 && bar_index <= 39 {
                add_spark(breakdown_drums, current_seconds, 0.85, *noise);
            } else {
                add_spark(samples, current_seconds, 0.85, *noise);
            }
        }

        // bars 25-40: breakdown melody.
        if bar_index >= 24 && bar_index <= 39 {
            breakdown_sixteenth_index := (current_sixteenth - (25 - 1) * sixteenths_per_bar) % breakdown_melody_phrase_sixteenths;
            add_matching_note_event(breakdown_melody, breakdown_melody_events, breakdown_sixteenth_index, current_sixteenth, breakdown_melody_phrase_sixteenths, seconds_per_sixteenth, total_sixteenths, 0.23);
        }

        // bars 37-40: extra bright hits into the end of the breakdown.
        if bar_index >= 36 && bar_index <= 39 && sixteenth_index_in_beat == 0 {
            add_spark(breakdown_sparks, current_seconds, 0.54, *spark_noise);
        }

        // bars 41+: hyper sixteenth sine melody, repeating every four bars.
        if bar_index >= 40 && bar_index <= 47   {
            phrase_sixteenth_index := (current_sixteenth - (41 - 1) * sixteenths_per_bar) % (4 * sixteenths_per_bar);
            add_matching_note_event(intro_melody, intro_melody_events, phrase_sixteenth_index, current_sixteenth, 4 * sixteenths_per_bar, seconds_per_sixteenth, total_sixteenths, 0.23);
        }

        // bars 1-24: dry pulse synth over the groove.
        if bar_index >= 0 && bar_index <= 23 {
            synth_pulse_sixteenth_index := current_sixteenth % synth_pulse_phrase_sixteenths;
            add_matching_note_event(dry_synth, synth_pulse_events, synth_pulse_sixteenth_index, current_sixteenth, synth_pulse_phrase_sixteenths, seconds_per_sixteenth, total_sixteenths, 0.26);
        }

        // bars 9-24: reverb synth pattern. do do do do 
        if bar_index >= 8 && bar_index <= 23 || bar_index >= 48 && bar_index <= 63  {
            pattern_sixteenth_index := (current_sixteenth - (9 - 1) * sixteenths_per_bar) % (4 * sixteenths_per_bar);
            add_matching_note_event(reverbed_synth, synth_events, pattern_sixteenth_index, current_sixteenth, 4 * sixteenths_per_bar, seconds_per_sixteenth, total_sixteenths, 0.20);
        }

        // bars 17-40: bass notes begin later in the groove and continue through the breakdown.
        if bar_index >= 16 && bar_index <= 39 || bar_index >= 48 {
            bass_sixteenth_index := (current_sixteenth - (17 - 1) * sixteenths_per_bar) % bass_phrase_sixteenths;
            add_matching_bass_event(bass, bass_events, bass_sixteenth_index, current_sixteenth, bass_phrase_sixteenths, seconds_per_sixteenth, total_sixteenths, 0.34);
        }
    }

    apply_repeating_low_pass_sweep(hihat, bpm);
    apply_constant_low_pass(breakdown_drums, BREAKDOWN_LOW_PASS_HZ);
    for i: 0..samples.count - 1 samples[i] += hihat[i];
    for i: 0..samples.count - 1 samples[i] += breakdown_drums[i];

    apply_repeating_low_pass_sweep(breakdown_melody, bpm);
    apply_reverb_to_melody(samples, breakdown_melody);

    apply_reverb_to_signal(samples, breakdown_sparks, dry_gain = 0.18, wet_gain = 1.35);

    apply_repeating_low_pass_sweep(intro_melody, bpm);
    apply_reverb_to_melody(samples, intro_melody);

    for i: 0..samples.count - 1 samples[i] += dry_synth[i] * 1.18;
    apply_reverb_to_signal(samples, reverbed_synth, dry_gain = 0.86, wet_gain = 0.58);
    for i: 0..samples.count - 1 samples[i] += bass[i] * 0.88;

    normalize(samples, 0.95);
    return samples;
}

hihat_fill_beat_for_bar :: (bar_index: int) -> int {
    h := randomish_u32(cast(u32) bar_index, 0xA511E9B3);
    if (h & 3) != 0 return -1;
    return cast(int) ((h >> 8) % 4);
}

randomish_u32 :: (value: u32, seed: u32) -> u32 {
    x := value + seed;
    x = (x ^ (x >> 16)) * 0x7FEB352D;
    x = (x ^ (x >> 15)) * 0x846CA68B;
    x = x ^ (x >> 16);
    return x;
}

apply_repeating_low_pass_sweep :: (samples: [] float, bpm: int) {
    filter: Low_Pass;
    low_pass_init(*filter, cast(float) SAMPLE_RATE_HZ);

    seconds_per_beat := 60.0 / cast(float) bpm;
    cycle_samples := cast(int) (4.0 * 4.0 * seconds_per_beat * cast(float) SAMPLE_RATE_HZ + 0.5);
    if cycle_samples < 1 cycle_samples = 1;

    for i: 0..samples.count - 1 {
        cycle_index := i % cycle_samples;
        progress := cast(float) cycle_index / cast(float) max(1, cycle_samples - 1);
        filter.frequency = linear_interpolate(12000.0, 650.0, progress);
        samples[i] = low_pass_process(*filter, samples[i]);
    }
}

// these don't have to be functions

// 16 bars

synth_pulse_pattern_notation :: () -> string {
    notation := #string END
[ 0 0 - 0 ] [ - 0 0 0 ] [ 0 0 - 0 ] [ - 0 0 0 ]
[ 8, 8, - 8, ] [ - 8, 8, 8, ] [ 8, 8, - 8, ] [ - 8, 8, 8, ]
[ 3, 3, - 3, ] [ - 3, 3, 3, ] [ 3, 3, - 3, ] [ - 3, 3, 3, ]
[ 7, 7, - 7, ] [ - 7, 7, 7, ] [ 7, 7, - 7, ] [ - 7, 7, 7, ]
END
    return notation;
}

// 16 bars

synth_pattern_notation :: () -> string {
    notation := #string END
[ 0 ~ ~ ~ ] [ ~ ~ ~ ~ ] [ ~ ~ ~ ~ ] [ 2 ~ 3 ~ ]
[ 8 ~ ~ ~ ] [ ~ ~ ~ ~ ] [ ~ ~ ~ ~ ] [ 8 ~ 10 ~ ]
[ 3 ~ ~ ~ ] [ ~ ~ ~ ~ ] [ ~ ~ ~ ~ ] [ 3 ~ 5 ~ ]
[ 2 ~ ~ ~ ] [ ~ ~ ~ ~ ] [ ~ ~ ~ ~ ] [ ~ ~ ~ ~ ]
END
    return notation;
}

// 32 bars

intro_melody_phrase_notation :: () -> string {
    notation := #string END
[ 0 7, 2 7, ] [ 3 7, 5 7, ] [ 3 7, 0 7, ] [ 2 7, 7, 7, ] 
[ 3 10, 5 10, ] [ 7 10, 8 10,] [ 7 10, 3 10, ] [ 5 10, 10, 10,]
[ 7 2 8 2 ] [ 10 2 0' 2 ] [ 10 2 7 2 ] [ 8 2 2 2 ] 
[ 10 5 0' 5 ] [ 2' 5 3' 5 ] [ 2' 5 10 5 ] [ 0' 5 5 5 ]
[ 0' 7 2' 7 ] [ 3' 7 5' 7 ] [ 3' 7 0' 7 ] [ 2' 7 7 7 ]
[ 8 3 10 3 ] [ 0' 3 2' 3 ] [ 0' 3 8 3 ] [ 10 3 3 3 ]
[ 5 0 7 0 ] [ 8 0 10 0 ] [ 8 0 5 0 ] [ 7 0 0 0 ] 
[ 2 10, 3 10, ] [ 5 10, 7 10, ] [ 5 10, 2 10, ] [ 3 10,  10, ]
END
    return notation;
}

// 16 bars

later_melody_phrase_notation :: () -> string {
    notation := #string END
[ 7 ~ ~ ~ ] [ 7 ~ ~ ~ ] [ - - - - ] [ 0' ~ 2' ~ ]
[ 3' ~ 2' ~ ] [ - - - - ] [ - - - - ] [ 3 ~ 2 ~ ]
[ 3 ~ 2 ~ ] [ - - - - ] [ - - - - ] [ 10 ~ 7 ~ ]
[ - - - - ] [ - - - - ] [ - - - - ] [ - - - - ]
END
    return notation;
}

// 16 bars

bass_pattern_notation :: () -> string {
    notation := #string END
[ 8,, ~ ~ ~ ] [ ~ ~ ~ ~ ] [ ~ ~ ~ ~ ] [ ~ ~ ~ ~ ]
[ 5,, ~ ~ ~ ] [ ~ ~ ~ ~ ] [ ~ ~ ~ ~ ] [ ~ ~ ~ ~ ]
[ 0,, ~ ~ ~ ] [ ~ ~ ~ ~ ] [ ~ ~ ~ ~ ] [ ~ ~ ~ ~ ]
[ 10,, ~ ~ ~ ] [ ~ ~ ~ ~ ] [ ~ ~ ~ ~ ] [ ~ ~ ~ ~ ]
END
    return notation;
}

// 32 bars

breakdown_melody_notation :: () -> string {
    notation := #string END
0' 7   2'  3' 
8  ~   3'  5'
7' 10  7'  8'
(5' 10) ~ ~ ~

0' 10   2'  3' 
8  ~   3'  5'
7' 3  7'  8'
(5' 2) ~ ~ ~

END
    return notation;
}

parse_note_pattern :: (notation: string, duration_mode: Note_Duration_Mode, duration_sixteenths: float) -> [..] Note_Event {
    events: [..] Note_Event;
    current_sixteenth := 0;
    cursor := 0;
    inside_beat := false;

    while cursor < notation.count {
        c := notation[cursor];

        if c == #char "[" {
            inside_beat = true;
            cursor += 1;
            continue;
        }

        if c == #char "]" {
            inside_beat = false;
            cursor += 1;
            continue;
        }

        if is_note_notation_separator(c) {
            cursor += 1;
            continue;
        }

        token_sixteenths := ifx inside_beat then 1 else 4;

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
    inside_beat := false;

    while cursor < notation.count {
        c := notation[cursor];

        if c == #char "[" {
            inside_beat = true;
            cursor += 1;
            continue;
        }

        if c == #char "]" {
            inside_beat = false;
            cursor += 1;
            continue;
        }

        if is_note_notation_separator(c) {
            cursor += 1;
            continue;
        }

        token_sixteenths := ifx inside_beat then 1 else 4;

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

#import "Basic";
#import "File";
#import "File_Utilities";
#import "Math";
#import "String";
#import "tbx/music";
