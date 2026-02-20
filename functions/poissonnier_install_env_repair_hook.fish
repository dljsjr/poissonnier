# Mise has a few bugs where it will nuke certain portions of the environment
# that existed before it was activated if it *also* manages that thing in the environment.
#
# The canonical example is Rust stuff; if mise is managing rust via a mise.toml or via
# a a rust-toolchain.toml, but you also have Rust available via a system wide configuration,
# (e.g. you've sourced ~/.cargo/env/fish), it can blow away the non-mise config upon deactivation.
#
# This doesn't handle cases where the environment gets *edited*; it only handles cases where
# mise removes an env var that existed before it was activated.
function poissonnier_install_env_repair_hook
    function __poissonnier_env_repair_hook --on-event poissonnier_env_hook
        set -f __mise_previous_state $argv[1]
        set -f __mise_current_state $argv[2]

        if test "$__mise_current_state" = 1 -o "$POISSONNIER_AUTOHOOK_DISABLE" = 1;
            return
        end

        if test "$__mise_previous_state" = 0 -a "$__mise_current_state" = 0
            __poissonnier_save_env
            return $status
        end

        if test "$__mise_previous_state" = 1 -a "$__mise_current_state" = 0
            __poissonnier_repair_env
            return $status
        end
    end
end
