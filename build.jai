OUTPUT_EXECUTABLE_NAME :: "tbx_music";

#run {
    set_build_options_dc(.{do_output = false});

    make_directory_if_it_does_not_exist("bin", recursive = true);

    w := compiler_create_workspace("Target Program");
    options := get_build_options(w);
    options.output_executable_name = OUTPUT_EXECUTABLE_NAME;
    options.output_path = "bin/";

    import_path: [..] string;
    array_add(*import_path, ..options.import_path);
    array_add(*import_path, "src/");
    options.import_path = import_path;

    set_build_options(options, w);

    add_build_file("src/main.jai", w);
};

#import "Basic";
#import "Compiler";
#import "File";
