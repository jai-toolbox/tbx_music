SONG_TWO_ANCHOR :: 5;
SONG_TWO_RHYTHM_FIRST_HALF :: "[[xxxx][xxx~][xxx~][xxx~]] [[x~xx][xxx~][x~x~][xxxx]]";
SONG_TWO_RHYTHM_SECOND_HALF :: "[[~xxx][xxx~][xxx~][xx~x]] [[~xxx][xxx~][x~x~][x~x~]]";
SONG_TWO_CHORD_ONE :: "(0 4 7 11)";
SONG_TWO_CHORD_TWO :: "(3 10 2' 7')";

render_song_two :: (bpm: int, bars: int) -> [..] Stereo_Sample {
    beats_per_bar := 4;
    sixteenths_per_bar := 16;
    total_sixteenths := bars * sixteenths_per_bar;
    tail_seconds := 0.55;
    seconds_per_beat := 60.0 / cast(float) bpm;
    seconds_per_sixteenth := seconds_per_beat / 4.0;
    total_seconds := cast(float) bars * cast(float) beats_per_bar * seconds_per_beat + tail_seconds;
    total_samples := cast(int) ceil(total_seconds * cast(float) SAMPLE_RATE_HZ);

    samples: [..] Stereo_Sample;
    array_resize(*samples, total_samples);
    for 0..samples.count - 1 {
        samples[it].left = 0.0;
        samples[it].right = 0.0;
    }

    notation := song_two_chord_notation();
    events := parse_note_pattern(notation, .UNTIL_NEXT_NOTE, 0.0);
    defer array_free(events);

    phrase_length_sixteenths := count_note_pattern_sixteenths(notation);
    for current_sixteenth: 0..total_sixteenths - 1 {
        phrase_sixteenth_index := current_sixteenth % phrase_length_sixteenths;
        add_matching_raw_detuned_saw_event(samples, events, phrase_sixteenth_index, current_sixteenth, phrase_length_sixteenths, seconds_per_sixteenth, total_sixteenths, 0.13);
    }

    return samples;
}

song_two_chord_notation :: () -> string {
    first_half := replace_song_two_rhythm_marker(SONG_TWO_RHYTHM_FIRST_HALF, SONG_TWO_CHORD_ONE);
    second_half := replace_song_two_rhythm_marker(SONG_TWO_RHYTHM_SECOND_HALF, SONG_TWO_CHORD_TWO);
    return tprint("%%", first_half, second_half);
}

replace_song_two_rhythm_marker :: (rhythm: string, chord: string) -> string {
    builder: String_Builder;
    defer free_buffers(*builder);

    for rhythm {
        if it == #char "x" {
            append(*builder, chord);
        } else if it == #char "[" {
            append(*builder, "[");
        } else if it == #char "]" {
            append(*builder, "]");
        } else if it == #char "~" {
            append(*builder, "~");
        }
    }

    return builder_to_string(*builder);
}

add_matching_raw_detuned_saw_event :: (
    samples: [] Stereo_Sample,
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
            semitones_from_c4 := SONG_TWO_ANCHOR + event.relative_notes[note_index];
            add_raw_detuned_saw_note(samples, start_seconds, duration_seconds, semitones_from_c4, chord_gain, current_sixteenth, seconds_per_sixteenth, phrase_length_sixteenths);
        }
    }
}

add_raw_detuned_saw_note :: (
    samples: [] Stereo_Sample,
    start_seconds: float,
    duration_seconds: float,
    semitones_from_c4: int,
    amp: float,
    start_sixteenth: int,
    seconds_per_sixteenth: float,
    phrase_length_sixteenths: int
) {
    start := cast(int) floor(start_seconds * cast(float) SAMPLE_RATE_HZ);
    length := cast(int) ceil(duration_seconds * cast(float) SAMPLE_RATE_HZ);
    base_frequency := note_frequency_from_c4(semitones_from_c4);
    detune_ratio := pow(2.0, 6.0 / 1200.0);
    pan: Pan_2;
    pan2_init(*pan);

    for i: 0..length - 1 {
        index := start + i;
        if index < 0 || index >= samples.count break;

        t := cast(float) i / cast(float) SAMPLE_RATE_HZ;
        oscillator_a := sine_with_harmonics_wave(base_frequency / detune_ratio, t);
        oscillator_b := sine_with_harmonics_wave(base_frequency * detune_ratio, t);
        sample := 0.5 * (oscillator_a + oscillator_b);

        envelope := song_two_amp_envelope(t, duration_seconds);

        pan.pan = song_two_pan_for_sixteenth_position(start_sixteenth, i, seconds_per_sixteenth, phrase_length_sixteenths);
        panned := pan2_process(*pan, sample * amp * envelope);
        samples[index].left += panned.left;
        samples[index].right += panned.right;
    }
}

song_two_amp_envelope :: (t: float, duration_seconds: float) -> float {
    attack_seconds := 0.018;
    decay_seconds := 0.280;
    sustain_level := 0.38;
    release_seconds := min(0.180, duration_seconds * 0.35);

    attack := clamp(t / attack_seconds, 0.0, 1.0);

    after_attack := max(0.0, t - attack_seconds);
    decay_progress := clamp(after_attack / decay_seconds, 0.0, 1.0);
    body := linear_interpolate(1.0, sustain_level, decay_progress);

    remaining := duration_seconds - t;
    release := clamp(remaining / release_seconds, 0.0, 1.0);

    return min(attack, body) * release;
}

song_two_pan_for_sixteenth_position :: (start_sixteenth: int, sample_offset: int, seconds_per_sixteenth: float, phrase_length_sixteenths: int) -> float {
    sample_sixteenth_offset := (cast(float) sample_offset / cast(float) SAMPLE_RATE_HZ) / seconds_per_sixteenth;
    phrase_position := cast(float) (start_sixteenth % phrase_length_sixteenths) + sample_sixteenth_offset;
    while phrase_position >= cast(float) phrase_length_sixteenths phrase_position -= cast(float) phrase_length_sixteenths;

    half_phrase := cast(float) phrase_length_sixteenths * 0.5;
    first_chord := phrase_position < half_phrase;
    position_in_half := ifx first_chord then phrase_position else phrase_position - half_phrase;
    half_progress := position_in_half / half_phrase;
    triangle := ifx half_progress < 0.5 then half_progress * 2.0 else (1.0 - half_progress) * 2.0;

    return ifx first_chord then triangle else -triangle;
}
