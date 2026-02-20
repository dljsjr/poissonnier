function poissonnier_enable_auto_dispatch
    argparse --name=poissonnier_enable_auto_dispatch 'p/prefix=' -- $argv
    or return

    if set -q _flag_prefix
        set -f mise_dispatch_prefix $_flag_prefix
    end

    function __poissonnier_mise_dispatcher --inherit-variable mise_dispatch_prefix
        { test -n "$mise_dispatch_prefix" && echo "$mise_dispatch_prefix" || echo "@"; } | read --function --line mise_dispatch_prefix
        set -f target_cmd $argv[1]
        set -e argv[1]

        set -f mise_tool_plugin (mise --quiet --silent which --plugin "$target_cmd" 2>/dev/null)
        set -f is_bin (test -n "$mise_tool_plugin" && echo -n true || echo -n false)
        set -f mise_tool_name (mise --quiet --silent ls --installed --no-header 2> /dev/null | string split ' ' -f1 | string match -m 1 --regex "^.*$target_cmd\$")

        set -f funcproxy {$mise_dispatch_prefix}{$target_cmd}
        set -f complproxy __{$funcproxy}_complete

        if test -n "$mise_tool_name"
            echo "
    function $funcproxy
        mise x \"$mise_tool_name\" -- $target_cmd \$argv
    end
            " | tee $__fish_config_dir/functions/{$funcproxy}.fish | source

            echo "
    function $complproxy
        set -f compl_str (commandline --cut-at-cursor | string trim -l -c '$mise_dispatch_prefix')
        mise x \"$mise_tool_name\" -- (status fish-path) -c \"complete -C \\\"\$compl_str\\\"\"
    end
    complete --keep-order --exclusive --command $funcproxy --arguments \"($complproxy)\"
            " | tee $__fish_config_dir/completions/{$funcproxy}.fish | source

        else if test -n "$mise_tool_plugin"
            echo "
    function $funcproxy
        mise x \"$mise_tool_plugin\" -- $target_cmd \$argv
    end
            " | tee $__fish_config_dir/functions/{$funcproxy}.fish | source

            echo "
    function $complproxy
        set -f compl_str (commandline --cut-at-cursor | string trim -l -c '$mise_dispatch_prefix')
        mise x \"$mise_tool_plugin\" -- (status fish-path) -c \"complete -C \\\"\$compl_str\\\"\"
    end
    complete --keep-order --exclusive --command $funcproxy --arguments \"($complproxy)\"
            " | tee $__fish_config_dir/completions/{$funcproxy}.fish | source
        end

        $funcproxy $argv
        return $status
    end

    if functions -q fish_command_not_found; and not functions -q __poissonnier_fish_original_not_found_handler
        functions -e __poissonnier_fish_original_not_found_handler
        functions -c fish_command_not_found __poissonnier_fish_original_not_found_handler
    end

    echo "function fish_command_not_found --on-event fish_command_not_found
        { test -n \"\$mise_dispatch_prefix\" && echo \"\$mise_dispatch_prefix\" || echo "@"; } | read --function --line mise_dispatch_prefix
        set -l dispatch_cmd (string replace --filter --regex \"^\$mise_dispatch_prefix\" '' \$argv[1])
        if test -n \"\$dispatch_cmd\"
           set -e argv[1]
           _mise_dispatch \$dispatch_cmd \$argv
       else if functions -q __poissonnier_fish_original_not_found_handler
           __poissonnier_fish_original_not_found_handler \$argv
       else
           __fish_default_command_not_found_handler \$argv
       end
    end" | source
end
