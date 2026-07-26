MELODY_ANCHOR :: 5;
BREAKDOWN_LOW_PASS_HZ :: 800.0;
INTRO_SECTION_BARS :: 8;
BREAKDOWN_SECTION_BARS :: 16;
GROOVE_SECTION_BARS :: 24;
GROOVE_START_BAR :: 0;
SYNTH_PATTERN_START_BAR :: GROOVE_START_BAR + 8;
BASS_START_BAR :: SYNTH_PATTERN_START_BAR + 8;
BREAKDOWN_START_BAR :: GROOVE_START_BAR + GROOVE_SECTION_BARS;
INTRO_START_BAR :: BREAKDOWN_START_BAR + BREAKDOWN_SECTION_BARS;

Melody_Event :: struct {
    step_offset: int;
    relative_note: int;
}

Render_Config :: struct {
    bpm: int = 135;
    bars: int = GROOVE_SECTION_BARS + BREAKDOWN_SECTION_BARS + INTRO_SECTION_BARS;
    output_path: string = "out/song.wav";
}

Noise_State :: struct {
    value: u32 = 0x12345678;
}

main :: () {
    if maybe_run_reverb_oracle() return;
    if maybe_run_low_pass_oracle() return;

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

    for step: 0..total_sixteenths - 1 {

        t := cast(float) step * seconds_per_sixteenth;
        beat_in_bar := (step / 4) % 4;
        sixteenth_in_beat := step % 4;
        bar_index := step / sixteenths_per_bar;
        is_breakdown_bar := bar_index >= BREAKDOWN_START_BAR && bar_index < INTRO_START_BAR;
        drum_bus := ifx is_breakdown_bar then breakdown_drums else samples;

        // Sixteenth-note hihat, with occasional 32nd-note fills on one beat of the bar.
        if !is_breakdown_bar {
            amp := ifx sixteenth_in_beat == 0 then 0.24 else 0.16;
            fill_beat := hihat_fill_beat_for_bar(bar_index);
            if beat_in_bar == fill_beat {
                add_hihat(hihat, t, 0.026, amp * 0.88, *noise);
                add_hihat(hihat, t + seconds_per_sixteenth * 0.5, 0.026, amp * 0.74, *noise);
            } else {
                add_hihat(hihat, t, 0.045, amp, *noise);
            }
        }

        // Bass drum on 1, 2&, and 3&.
        step_in_bar := step % sixteenths_per_bar;
        if step_in_bar == 0 || step_in_bar == 6 || step_in_bar == 10 {
            add_kick(drum_bus, t, 0.95);
        }

        // Backbeat spark on beats 2 and 4.
        if sixteenth_in_beat == 0 && (beat_in_bar == 1 || beat_in_bar == 3) {
            add_spark(drum_bus, t, 0.85, *noise);
        }
    }

    apply_repeating_low_pass_sweep(hihat, bpm);
    apply_constant_low_pass(breakdown_drums, BREAKDOWN_LOW_PASS_HZ);
    for i: 0..samples.count - 1 samples[i] += hihat[i];
    for i: 0..samples.count - 1 samples[i] += breakdown_drums[i];

    breakdown_melody: [..] float;
    array_resize(*breakdown_melody, samples.count);
    defer array_free(breakdown_melody);
    for 0..breakdown_melody.count - 1 breakdown_melody[it] = 0.0;

    add_breakdown_melody(breakdown_melody, bpm, bars, first_bar = BREAKDOWN_START_BAR);
    apply_repeating_low_pass_sweep(breakdown_melody, bpm);
    apply_reverb_to_melody(samples, breakdown_melody);

    breakdown_sparks: [..] float;
    array_resize(*breakdown_sparks, samples.count);
    defer array_free(breakdown_sparks);
    for 0..breakdown_sparks.count - 1 breakdown_sparks[it] = 0.0;

    add_breakdown_sparks(breakdown_sparks, bpm, bars);
    apply_reverb_to_signal(samples, breakdown_sparks, dry_gain = 0.18, wet_gain = 1.35);

    melody: [..] float;
    array_resize(*melody, samples.count);
    defer array_free(melody);
    for 0..melody.count - 1 melody[it] = 0.0;

    add_default_sine_melody(melody, bpm, bars, first_bar = INTRO_START_BAR);
    apply_repeating_low_pass_sweep(melody, bpm);
    apply_reverb_to_melody(samples, melody);

    add_synth(samples, bpm, bars);
    add_bass(samples, bpm, bars);

    normalize(samples, 0.95);
    return samples;
}

mute_from_bar :: (samples: [] float, bpm: int, first_muted_bar: int) {
    seconds_per_beat := 60.0 / cast(float) bpm;
    samples_per_bar := cast(int) (4.0 * seconds_per_beat * cast(float) SAMPLE_RATE_HZ + 0.5);
    if samples_per_bar < 1 return;

    first_muted_sample := first_muted_bar * samples_per_bar;
    for i: 0..samples.count - 1 {
        if i >= first_muted_sample samples[i] = 0.0;
    }
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

add_default_sine_melody :: (samples: [] float, bpm: int, bars: int, first_bar: int) {
    seconds_per_beat := 60.0 / cast(float) bpm;
    seconds_per_sixteenth := seconds_per_beat / 4.0;
    sixteenths_per_bar := 16;
    total_sixteenths := bars * sixteenths_per_bar;

    phrase_start_bar := first_bar;
    while phrase_start_bar < bars {
        phrase_start_step := phrase_start_bar * sixteenths_per_bar;

        add_melody_step(samples, phrase_start_step + 0,  7,       4, seconds_per_sixteenth, total_sixteenths);
        add_melody_step(samples, phrase_start_step + 4,  7,       4, seconds_per_sixteenth, total_sixteenths);
        add_melody_step(samples, phrase_start_step + 12, 0 + 12,  2, seconds_per_sixteenth, total_sixteenths);
        add_melody_step(samples, phrase_start_step + 14, 2 + 12,  2, seconds_per_sixteenth, total_sixteenths);

        add_melody_step(samples, phrase_start_step + 16, 3 + 12,  2, seconds_per_sixteenth, total_sixteenths);
        add_melody_step(samples, phrase_start_step + 18, 2 + 12,  2, seconds_per_sixteenth, total_sixteenths);
        add_melody_step(samples, phrase_start_step + 28, 3,       2, seconds_per_sixteenth, total_sixteenths);
        add_melody_step(samples, phrase_start_step + 30, 2,       2, seconds_per_sixteenth, total_sixteenths);

        add_melody_step(samples, phrase_start_step + 32, 3,       2, seconds_per_sixteenth, total_sixteenths);
        add_melody_step(samples, phrase_start_step + 34, 2,       2, seconds_per_sixteenth, total_sixteenths);
        add_melody_step(samples, phrase_start_step + 44, 10,      2, seconds_per_sixteenth, total_sixteenths);
        add_melody_step(samples, phrase_start_step + 46, 7,       2, seconds_per_sixteenth, total_sixteenths);

        phrase_start_bar += 4;
    }
}

add_synth :: (mix: [] float, bpm: int, bars: int) {
    dry_synth: [..] float;
    array_resize(*dry_synth, mix.count);
    defer array_free(dry_synth);
    for 0..dry_synth.count - 1 dry_synth[it] = 0.0;

    reverbed_synth: [..] float;
    array_resize(*reverbed_synth, mix.count);
    defer array_free(reverbed_synth);
    for 0..reverbed_synth.count - 1 reverbed_synth[it] = 0.0;

    seconds_per_beat := 60.0 / cast(float) bpm;
    seconds_per_sixteenth := seconds_per_beat / 4.0;
    sixteenths_per_bar := 16;
    total_sixteenths := bars * sixteenths_per_bar;

    pulse_first_step := GROOVE_START_BAR * sixteenths_per_bar;
    pulse_last_step := min(total_sixteenths, pulse_first_step + GROOVE_SECTION_BARS * sixteenths_per_bar);

    for step: pulse_first_step..pulse_last_step - 1 {
        pattern_step := (step - pulse_first_step) % sixteenths_per_bar;
        if !synth_pulse_pattern_is_on(pattern_step) continue;

        bar_offset := (step / sixteenths_per_bar) - GROOVE_START_BAR;
        relative_note := synth_pulse_relative_note_for_bar(bar_offset);
        semitones_from_c4 := MELODY_ANCHOR + relative_note;
        start_seconds := cast(float) step * seconds_per_sixteenth;
        duration_seconds := seconds_per_sixteenth * 0.78;
        add_sine_synth_note(dry_synth, start_seconds, duration_seconds, semitones_from_c4, 0.26);
    }

    pattern_first_step := SYNTH_PATTERN_START_BAR * sixteenths_per_bar;
    pattern_last_step := min(total_sixteenths, pattern_first_step + 16 * sixteenths_per_bar);
    events := synth_pattern_events();

    for repeat: 0..3 {
        repeat_step := pattern_first_step + repeat * 4 * sixteenths_per_bar;
        if repeat_step >= pattern_last_step break;

        for events {
            step := repeat_step + it.step_offset;
            if step >= pattern_last_step break;

            start_seconds := cast(float) step * seconds_per_sixteenth;
            duration_seconds := seconds_per_sixteenth * 1.85;
            semitones_from_c4 := MELODY_ANCHOR + it.relative_note;
            add_sine_synth_note(reverbed_synth, start_seconds, duration_seconds, semitones_from_c4, 0.20);
        }
    }

    for i: 0..mix.count - 1 mix[i] += dry_synth[i] * 1.18;
    apply_reverb_to_signal(mix, reverbed_synth, dry_gain = 0.86, wet_gain = 0.58);
}

synth_pulse_pattern_is_on :: (step_in_bar: int) -> bool {
    // |00x0|x000|00x0|x000| where 0 = note on, x = rest.
    if step_in_bar == 0  return true;
    if step_in_bar == 1  return true;
    if step_in_bar == 3  return true;
    if step_in_bar == 6  return true;
    if step_in_bar == 7  return true;
    if step_in_bar == 8  return true;
    if step_in_bar == 9  return true;
    if step_in_bar == 11 return true;
    if step_in_bar == 14 return true;
    if step_in_bar == 15 return true;
    return false;
}

synth_pulse_relative_note_for_bar :: (bar_offset: int) -> int {
    note_index := bar_offset % 4;
    if note_index == 0 return 0;
    if note_index == 1 return 8 - 12;
    if note_index == 2 return 3 - 12;
    return 7 - 12;
}

add_bass :: (mix: [] float, bpm: int, bars: int) {
    bass: [..] float;
    array_resize(*bass, mix.count);
    defer array_free(bass);
    for 0..bass.count - 1 bass[it] = 0.0;

    seconds_per_beat := 60.0 / cast(float) bpm;
    seconds_per_sixteenth := seconds_per_beat / 4.0;
    sixteenths_per_bar := 16;
    total_sixteenths := bars * sixteenths_per_bar;
    first_step := BASS_START_BAR * sixteenths_per_bar;
    last_step := min(total_sixteenths, INTRO_START_BAR * sixteenths_per_bar);
    notes := bass_pattern_notes();

    repeat := 0;
    while true {
        repeat_step := first_step + repeat * 4 * sixteenths_per_bar;
        if repeat_step >= last_step break;

        for i: 0..notes.count - 1 {
            step := repeat_step + i * sixteenths_per_bar;
            if step >= last_step break;

            start_seconds := cast(float) step * seconds_per_sixteenth;
            duration_seconds := seconds_per_sixteenth * 15.5;
            semitones_from_c4 := MELODY_ANCHOR + notes[i] - 24;
            add_bass_synth_note(bass, start_seconds, duration_seconds, semitones_from_c4, 0.34);
        }

        repeat += 1;
    }

    for i: 0..mix.count - 1 mix[i] += bass[i] * 0.88;
}

add_breakdown_melody :: (samples: [] float, bpm: int, bars: int, first_bar: int) {
    if first_bar >= bars return;

    seconds_per_beat := 60.0 / cast(float) bpm;
    seconds_per_sixteenth := seconds_per_beat / 4.0;
    sixteenths_per_bar := 16;
    total_sixteenths := bars * sixteenths_per_bar;
    first_step := first_bar * sixteenths_per_bar;
    notes := breakdown_melody_notes();

    for repeat: 0..1 {
        repeat_start_step := first_step + repeat * notes.count * 4;
        for i: 0..notes.count - 1 {
            step := repeat_start_step + i * 4;
            if step >= total_sixteenths return;
            add_melody_step(samples, step, notes[i], 4, seconds_per_sixteenth, total_sixteenths);
        }
    }

    first_half_start_sample := cast(int) floor(cast(float) first_step * seconds_per_sixteenth * cast(float) SAMPLE_RATE_HZ);
    first_half_samples := cast(int) floor(8.0 * 4.0 * seconds_per_beat * cast(float) SAMPLE_RATE_HZ);
    second_half_start_sample := first_half_start_sample + first_half_samples;

    for i: 0..first_half_samples - 1 {
        destination := second_half_start_sample + i;
        source := first_half_start_sample + first_half_samples - 1 - i;
        if destination >= samples.count || source >= samples.count break;
        samples[destination] = samples[source];
    }
}

add_breakdown_sparks :: (samples: [] float, bpm: int, bars: int) {
    start_bar := INTRO_START_BAR - 4;
    if start_bar < BREAKDOWN_START_BAR start_bar = BREAKDOWN_START_BAR;
    if start_bar >= bars return;

    seconds_per_beat := 60.0 / cast(float) bpm;
    first_step := start_bar * 16;
    total_sixteenths := bars * 16;
    last_step := min(total_sixteenths, INTRO_START_BAR * 16);

    spark_noise: Noise_State;
    spark_noise.value = 0x62F3A91D;

    step := first_step;
    while step < last_step {
        start_seconds := cast(float) step * seconds_per_beat / 4.0;
        add_spark(samples, start_seconds, 0.54, *spark_noise);
        step += 4;
    }
}

synth_pattern_events :: () -> [] Melody_Event {
    return .[
        .{0, 0},
        .{12, 2},
        .{14, 3},
        .{16, 8},
        .{28, 8},
        .{30, 10},
        .{32, 3},
        .{44, 3},
        .{46, 5},
        .{48, 2},
    ];
}

bass_pattern_notes :: () -> [] int {
    return .[8, 5, 0, 10];
}

breakdown_melody_notes :: () -> [] int {
    return .[
        7,  0 + 12, 2 + 12, 3 + 12,
        8,  0 + 12, 2 + 12, 5 + 12,
        10, 0 + 12, 3 + 12, 7 + 12,
        5 + 12, 3 + 12, 2 + 12, 3 + 12,
    ];
}

add_melody_step :: (samples: [] float, step: int, relative_note: int, duration_steps: int, seconds_per_sixteenth: float, total_sixteenths: int) {
    if step >= total_sixteenths return;

    remaining_steps := total_sixteenths - step;
    actual_duration_steps := min(duration_steps, remaining_steps);
    start_seconds := cast(float) step * seconds_per_sixteenth;
    duration_seconds := cast(float) actual_duration_steps * seconds_per_sixteenth * 0.96;
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
