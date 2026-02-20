function __poissonnier_statevar
    for varname in $argv
        echo __POISSONNIER_{$varname}__{$fish_pid}
    end
end

function __poissonnier_state_cleanup
    for varbasename in BEFORE_ENV_VAR_VALS BEFORE_ENV_VAR_DETAILS BEFORE_PATH MISE_STATE ACTIVE
        set -f statevar_prefix "__POISSONNIER_$varbasename"
        set -f statevar (__poissonnier_statevar "$varbasename")

        if test "$varbasename" = "ACTIVE" -a -z "$$statevar"
            set -U $statevar 0
        end

        for existing_var in (set --names --universal | string match --entire --regex "^$statevar_prefix")
            if string match --regex --quiet "[a-zA-Z]__(?<__other_pid>[0-9]+)" "$existing_var"
                if not ps -p $__other_pid > /dev/null 2>&1
                    set -e $existing_var
                end
            end
        end

        if not set -q "$statevar"
            set -U $statevar
        end
    end
end

if type -q mise && status is-interactive
    function __poissonnier_var_inflate -a var
        echo "$$var" | base64 -d | zcat -q
    end

    function __poissonnier_get_saved_var_details
        __poissonnier_var_inflate (__poissonnier_statevar BEFORE_ENV_VAR_DETAILS) | string match --regex --entire ": set in"
        return $status
    end

    function __poissonnier_get_saved_var_value
        set -l varname $argv[1]
        set -e argv[1]
        set -l varvals $argv
        if string match --regex --quiet "^$varname (?<__varval>.*)\$" (printf %s\n $varvals)
            echo $__varval
        end
        return $status
    end

    function __poissonnier_get_saved_path
        __poissonnier_var_inflate (__poissonnier_statevar BEFORE_PATH) | string split ':'
    end

    function __poissonnier_get_var_scope -a details
        if string match --quiet --regex 'set in (?<__scope>[^\s]+) scope' "$details"
            printf %s $__scope
        end
    end

    function __poissonnier_get_export_status -a details
        if string match --quiet --regex 'scope, (?<__export>[^,]+),' "$details"
            printf %s $__export | string trim --right --chars 'ed'
        end
    end

    function __poissonnier_is_pathvar -a details
        string match --regex --quiet 'a path variable' "$details"
        return $status
    end

    # Mise has a few bugs where it will nuke certain portions of the environment
    # that existed before it was activated if it *also* manages that thing in the environment.
    #
    # The canonical example is Rust stuff; if mise is managing rust via a mise.toml or via
    # a a rust-toolchain.toml, but you also have Rust available via a system wide configuration,
    # (e.g. you've sourced ~/.cargo/env/fish), it can blow away the non-mise config upon deactivation.
    #
    # This doesn't handle cases where the environment gets *edited*; it only handles cases where
    # mise removes an env var that existed before it was activated.
    #
    # This gets run in a disowned background shell because all of the compression and encoding stuff can
    # take a second or two; long enough for the `fish_prompt` hook to create significant prompt latency.
    function __poissonnier_save_env
        set __POISSONNIER_VALS_RAW (set --long | string escape)
        set __POISSONNIER_DETAILS_RAW (set --show | string escape)
        set __POISSONNIER_PATH_RAW (echo "$PATH" | string escape)

        set __POISSONNIER_BEFORE_ENV_VALS_VARNAME (__poissonnier_statevar BEFORE_ENV_VAR_VALS)
        set __POISSONNIER_BEFORE_ENV_DETAILS_VARNAME (__poissonnier_statevar BEFORE_ENV_VAR_DETAILS)
        set __POISSONNIER_BEFORE_PATH_VARNAME (__poissonnier_statevar BEFORE_PATH)
        fish --private --command "
        set -U $__POISSONNIER_BEFORE_ENV_VALS_VARNAME (printf %s\n $__POISSONNIER_VALS_RAW | string match --entire --invert --regex '^\\\$?history' | string match --entire --invert --regex '^\\\$?argv' |  string match --entire --invert --regex '^\\\$?__POISSONNIER' | gzip --fast --stdout | base64)
        set -U $__POISSONNIER_BEFORE_ENV_DETAILS_VARNAME (printf %s\n $__POISSONNIER_DETAILS_RAW | string match --entire --invert --regex '^\\\$?history' | string match --entire --invert --regex '^\\\$?argv' |  string match --entire --invert --regex '^\\\$?__POISSONNIER' | string match --regex --entire ': set in' | string match --entire --regex --invert '\\\(read-only\\\)' | gzip --fast --stdout | base64)
        set -U $__POISSONNIER_BEFORE_PATH_VARNAME (printf %s\n $__POISSONNIER_PATH_RAW | gzip --fast --stdout | base64)
        " &; disown
    end

    # Similar to env repair, this handles cases where `mise` accidentally removes elements
    # from the $PATH.
    function __poissonnier_repair_path
        set -f saved_path (__poissonnier_get_saved_path)

        set -f current_saved_item_index 1
        for pathitem in $saved_path
            if not contains $pathitem $PATH
                set -l prev_saved_idx (math $current_saved_item_index - 1)
                set -l next_saved_idx (math $current_saved_item_index + 1)
                set -l num_saved_items (count $saved_path)

                set -l prev_saved_item
                set -l next_saved_item
                if test "$prev_saved_idx" -gt 0
                    set prev_saved_item $saved_path[$prev_saved_idx]
                end

                if test "$next_saved_idx" -le "$num_saved_items"
                    set next_saved_item $saved_path[$next_saved_idx]
                end

                if test -n "$prev_saved_item" && set -l insert_idx (contains --index $prev_saved_item $PATH)
                    set PATH $PATH[..$insert_idx] $pathitem $PATH[(math $insert_idx + 1)..]
                else if test -n "$next_saved_item" && set -l insert_idx (contains --index $next_saved_item $PATH)
                    set PATH $PATH[..(math $insert_idx -1)] $pathitem $PATH[(math $insert_idx)..]
                else
                    set --append PATH $pathitem
                end
            end
            set current_saved_item_index (math $current_saved_item_index + 1)
        end
    end

    function __poissonnier_repair_var
        set -l varname $argv[1]
        set -e argv[1]
        set -l envvar_details $argv[1]
        set -e argv[1]
        set -l envvar_vals $argv

        set -f envvar_scope (__poissonnier_get_var_scope "$envvar_details")
        switch $envvar_scope
            case universal
                set -a variable_restore_args "--universal"
            case global
                set -a variable_restore_args "--global"
        end

        set -f envvar_export (__poissonnier_get_export_status "$envvar_details")

        switch $envvar_export
            case export
                set -a variable_restore_args "--export"
            case '*'
                set -a variable_restore_args "--unexport"
        end

        if __poissonnier_is_pathvar $envvar_details
            set -a variable_restore_args "--path"
        else
            set -a variable_restore_args "--unpath"
        end

        if set -f varval (__poissonnier_get_saved_var_value "$varname" $envvar_vals)
            eval "set $variable_restore_args $varname $varval"
        end
    end

    function __poissonnier_repair_env
        # handle path repair explicitly since it won't be entirely missing from the env diff
        __poissonnier_repair_path

        __poissonnier_get_saved_var_details | read --null --local --list --delimiter \n var_details
        __poissonnier_var_inflate (__poissonnier_statevar BEFORE_ENV_VAR_VALS) | read --null --local --list --delimiter \n var_vals_inflated
        for var_detail_line in $var_details[..-2]
            if string match --regex --quiet "^\\\$(?<__varname>[^:]+):" "$var_detail_line" && not set -q $__varname
                __poissonnier_repair_var "$__varname" "$var_detail_line" $var_vals_inflated
            end
        end
        set -e -U (__poissonnier_statevar BEFORE_ENV_VAR_VALS)
        set -e -U (__poissonnier_statevar BEFORE_ENV_VAR_DETAILS)
        set -e -U (__poissonnier_statevar BEFORE_PATH)
    end

    function __poissonnier_activate
        __poissonnier_save_env && mise activate fish | source && set -U (__poissonnier_statevar ACTIVE) 1
    end

    function __poissonnier_deactivate
        mise deactivate && set -U (__poissonnier_statevar ACTIVE) 0 && __poissonnier_repair_env
    end

    function __poissonnier_mise_hook_impl
        set -l active (__poissonnier_statevar ACTIVE)

        # if disable env var is set, bail out
        if set -q POISSONNIER_AUTOHOOK_DISABLE && test "$POISSONNIER_AUTOHOOK_DISABLE" = 1
            return
        end

        # if mise was activated manually, bail out
        if test -n "$__MISE_DIFF" -a "$$active" = 0
            return
        end

        set -f curr_dir (command pwd -P)
        set -f closest_cfg (eval "path resolve $(mise cfg ls --no-header | tail -n 1 | string split -f1 ' ')")
        set -f mise_global_cfg_root (mise --quiet --silent settings --raw global_config_root 2>/dev/null || echo "$HOME")
        set -f mise_system_config_file (mise --quiet --silent settings --raw system_config_file 2>/dev/null || echo "/etc/mise/config.toml")

        { test -n "$MISE_CONFIG_DIR" && echo "$MISE_CONFIG_DIR" || { test -n "$XDG_CONFIG_HOME" && echo "$XDG_CONFIG_HOME/mise" || echo "$HOME/.config/mise"; }; } | read --function --line mise_cfg_root
        { test -n "$MISE_DEFAULT_CONFIG_FILENAME" && echo "$MISE_DEFAULT_CONFIG_FILENAME" || echo "mise.toml" } | read --function --line mise_cfg_root

        set -f mise_cfg_patterns (mise settings override_config_filenames | string trim --left --chars '[' | string trim --right --chars ']' | string split ", " | string unescape)
        # see: https://github.com/jdx/mise/blob/2a825caf2b92303ce41273dac09d0cd6ebd5dece/src/config/mod.rs#L966-L987
        if test -z "$mise_cfg_patterns"
                set mise_cfg_patterns "$MISE_DEFAULT_CONFIG_FILENAME" '.config/mise/conf.d/*.toml' '.config/mise/config.toml' '.config/mise/mise.toml' '.config/mise.toml' '.mise/config.toml' 'mise/config.toml' '.rtx.toml' 'mise.toml' '.mise.toml' '.config/mise/config.local.toml' '.config/mise/mise.local.toml' '.config/mise.local.toml' '.mise/config.local.toml' 'mise/config.local.toml' '.rtx.local.toml' 'mise.local.toml' '.mise.local.toml'
        end

        # if the closest config isn't a local config, check for deactivate then early return.
        if contains $closest_cfg $mise_global_cfg_root/$mise_cfg_patterns ||\
            string match --quiet --regex "$mise_cfg_root" "$closest_cfg" ||\
            test "$curr_dir" = "$mise_global_cfg_root" -o "$curr_dir" = "$HOME" -o "$closest_cfg" = "$MISE_GLOBAL_CONFIG_FILE" -o "$closest_cfg" = "$MISE_SYSTEM_CONFIG_FILE"
                if test -n "$__MISE_DIFF" -a "$$active" = 1
                    __poissonnier_deactivate
                    return $status
                else
                    return
                end
        end

        if test -z "$__MISE_DIFF" -a "$$active" = 0
            __poissonnier_activate
            return $status
        end
    end

    # entrypoint to the main functionality; check for
    function __poissonnier_mise_hook --on-event fish_prompt
        __poissonnier_state_cleanup
        set -l mise_state (__poissonnier_statevar MISE_STATE)
        if test -n "$$mise_state"
            set -f __mise_start_state $$mise_state
        else
            set -f __mise_start_state (test -n "$__MISE_DIFF" -o "$$active" = 1 && echo 1 || echo 0)
        end

        __poissonnier_mise_hook_impl
        set -l funcstatus $status

        set -f __mise_end_state (test -n "$__MISE_DIFF" -o "$$active" = 1 && echo 1 || echo 0)
        set -U $mise_state $__mise_end_state
        emit poissonnier_env_hook $__mise_start_state $__mise_end_state
        return $funcstatus
    end
end
