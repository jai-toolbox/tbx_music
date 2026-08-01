MELODY_ANCHOR :: 5;
BREAKDOWN_LOW_PASS_HZ :: 800.0;

render_song_one :: (bpm: int, bars: int) -> [..] float {

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

synth_pulse_pattern_notation :: () -> string {
    notation := #string END
[ [ 0 0 - 0 ] [ - 0 0 0 ] [ 0 0 - 0 ] [ - 0 0 0 ] ]
[ [ 8, 8, - 8, ] [ - 8, 8, 8, ] [ 8, 8, - 8, ] [ - 8, 8, 8, ] ]
[ [ 3, 3, - 3, ] [ - 3, 3, 3, ] [ 3, 3, - 3, ] [ - 3, 3, 3, ] ]
[ [ 7, 7, - 7, ] [ - 7, 7, 7, ] [ 7, 7, - 7, ] [ - 7, 7, 7, ] ]
END
    return notation;
}

synth_pattern_notation :: () -> string {
    notation := #string END
[ [ 0 ~ ~ ~ ] [ ~ ~ ~ ~ ] [ ~ ~ ~ ~ ] [ 2 ~ 3 ~ ] ]
[ [ 8 ~ ~ ~ ] [ ~ ~ ~ ~ ] [ ~ ~ ~ ~ ] [ 8 ~ 10 ~ ] ]
[ [ 3 ~ ~ ~ ] [ ~ ~ ~ ~ ] [ ~ ~ ~ ~ ] [ 3 ~ 5 ~ ] ]
[ [ 2 ~ ~ ~ ] [ ~ ~ ~ ~ ] [ ~ ~ ~ ~ ] [ ~ ~ ~ ~ ] ]
END
    return notation;
}

intro_melody_phrase_notation :: () -> string {
    notation := #string END
[ [ 0 7, 2 7, ] [ 3 7, 5 7, ] [ 3 7, 0 7, ] [ 2 7, 7, 7, ] ]
[ [ 3 10, 5 10, ] [ 7 10, 8 10,] [ 7 10, 3 10, ] [ 5 10, 10, 10,] ]
[ [ 7 2 8 2 ] [ 10 2 0' 2 ] [ 10 2 7 2 ] [ 8 2 2 2 ] ]
[ [ 10 5 0' 5 ] [ 2' 5 3' 5 ] [ 2' 5 10 5 ] [ 0' 5 5 5 ] ]
[ [ 0' 7 2' 7 ] [ 3' 7 5' 7 ] [ 3' 7 0' 7 ] [ 2' 7 7 7 ] ]
[ [ 8 3 10 3 ] [ 0' 3 2' 3 ] [ 0' 3 8 3 ] [ 10 3 3 3 ] ]
[ [ 5 0 7 0 ] [ 8 0 10 0 ] [ 8 0 5 0 ] [ 7 0 0 0 ] ]
[ [ 2 10, 3 10, ] [ 5 10, 7 10, ] [ 5 10, 2 10, ] [ 3 10,  10, ] ]
END
    return notation;
}

later_melody_phrase_notation :: () -> string {
    notation := #string END
[ [ 7 ~ ~ ~ ] [ 7 ~ ~ ~ ] [ - - - - ] [ 0' ~ 2' ~ ] ]
[ [ 3' ~ 2' ~ ] [ - - - - ] [ - - - - ] [ 3 ~ 2 ~ ] ]
[ [ 3 ~ 2 ~ ] [ - - - - ] [ - - - - ] [ 10 ~ 7 ~ ] ]
[ [ - - - - ] [ - - - - ] [ - - - - ] [ - - - - ] ]
END
    return notation;
}

bass_pattern_notation :: () -> string {
    notation := #string END
[ [ 8,, ~ ~ ~ ] [ ~ ~ ~ ~ ] [ ~ ~ ~ ~ ] [ ~ ~ ~ ~ ] ]
[ [ 5,, ~ ~ ~ ] [ ~ ~ ~ ~ ] [ ~ ~ ~ ~ ] [ ~ ~ ~ ~ ] ]
[ [ 0,, ~ ~ ~ ] [ ~ ~ ~ ~ ] [ ~ ~ ~ ~ ] [ ~ ~ ~ ~ ] ]
[ [ 10,, ~ ~ ~ ] [ ~ ~ ~ ~ ] [ ~ ~ ~ ~ ] [ ~ ~ ~ ~ ] ]
END
    return notation;
}

breakdown_melody_notation :: () -> string {
    notation := #string END
[ [ 0' ~ ~ ~ ] [ 7 ~ ~ ~ ] [ 2' ~ ~ ~ ] [ 3' ~ ~ ~ ] ]
[ [ 8 ~ ~ ~ ] [ ~ ~ ~ ~ ] [ 3' ~ ~ ~ ] [ 5' ~ ~ ~ ] ]
[ [ 7' ~ ~ ~ ] [ 10 ~ ~ ~ ] [ 7' ~ ~ ~ ] [ 8' ~ ~ ~ ] ]
[ [ (5' 10) ~ ~ ~ ] [ ~ ~ ~ ~ ] [ ~ ~ ~ ~ ] [ ~ ~ ~ ~ ] ]

[ [ 0' ~ ~ ~ ] [ 10 ~ ~ ~ ] [ 2' ~ ~ ~ ] [ 3' ~ ~ ~ ] ]
[ [ 8 ~ ~ ~ ] [ ~ ~ ~ ~ ] [ 3' ~ ~ ~ ] [ 5' ~ ~ ~ ] ]
[ [ 7' ~ ~ ~ ] [ 3 ~ ~ ~ ] [ 7' ~ ~ ~ ] [ 8' ~ ~ ~ ] ]
[ [ (5' 2) ~ ~ ~ ] [ ~ ~ ~ ~ ] [ ~ ~ ~ ~ ] [ ~ ~ ~ ~ ] ]

END
    return notation;
}
