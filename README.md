# Poissonnier - adding extra [mise](https://mise.jdx.dev/) powers to the `fish` shell

## Name

Poissonnier means fishmonger. But it is also the name for the fish cook in a French kitchen brigade,
which `mise` also takes its name from.

## Features

### Automatically Activate Mise in directories with local configs

For some people, you may not want to activate `mise` as part of your shell configuration all the
time.

But then you have to remember to `mise activate`/`mise deactivate` in project directories, or you
have to lean on` mise exec`/`mise x`.

The primary goal of `poissonnier` is to give you the best of both worlds; if you aren't in a `mise`
project directory, then mise won't be activated. But if you enter a `mise` project directory during
an interactive session (we rely on the `fish_prompt` event), then `mise` will get activated for
as long as you're in the project's directory tree.

#### Respecting Manual Activation

The plugin's hook shouldn't fire if `mise` was activated manually or by some means outside of the
plugin's purview. Failing to do so is a bug.

#### Disabling this feature entirely

You can disable the automatic activation functionality by setting the variable `POISSONNIER_AUTOHOOK_DISABLE` to `1`:

```fish
# Disable across all sessions
set -U POISSONNIER_AUTOHOOK_DISABLE 1

# Disable globally for this session
set -g -x POISSONNIER_AUTOHOOK_DISABLE 1
```

### Environment Repair

There are some edge cases in mise where some environment variables that exist before an activation can get
un-set entirely upon deactivation. Here's an example of this that has since been fixed: <https://github.com/jdx/mise/pull/6689>

There are other situations where this can happen as well.

This plugin provides a function, `poissonnier_install_env_repair_hook`, that will monitor the shell
process's environment and PATH whenever the base plugin hook fires, and any time `mise` is
deactivated for any reason, will attempt to repair any accidentally deleted PATH entries or
variables.

You'll need to enable it for every shell session; if you want it always enabled, call it in your fish configuration
file or config snippets.

> [!note]
> The environment repair hook leverages functionality in the main auto-activation hook, and is coupled to it.
> If `POISSONNIER_AUTOHOOK_DISABLE` is set to `1`, then the environment repair hook will also be disabled.

### Auto Dispatcher for `mise x`/`mise exec`

This plugin also provides the function `poissonnier_enable_auto_dispatch`. When this function is called and the feature is
enabled, it installs a special "dispatch" function that looks for commands with a special prefix, and if those commands
result in a "command not found" error, it will attempt to dispatch that command to `mise exec` after doing a best-guess
lookup of the tool that the command belongs to.

This relies on redefining `fish_command_not_found`; if a custom version of this handler is defined, it will be
preserved as a falblack. If the definition for the handler gets replaced after activating, the replacement needs
to call through to the existing version of the function that gets registered when this is enabled.

This feature requires that the target command already be installed with `mise`; it won't automatically `mise use` or `mise install`
a tool for you.

This is a convenience technique for accessing tools installed with `mise use -g` without actually activating mise and
clobbering system tooling. You can also use it in project directories if you have the plugin's main hook disabled.

The default prefix is `@`; this can be changed by passing `-p/--prefix=` to `poissonnier_enable_auto_dispatch`

This will need to be enabled for every shell session; like the environment repair tool, you can add this to your shell config
scripts to have it always available.

> [!note]
> The auto-dispatch function proxy *does not* rely on the auto-hook; if the auto-hook is disabled, the dispatcher
> will continue to work if it has been activated.

#### Auto Dispatcher Completions

When auto-dispatch is enabled, it will also attempt to register a completion function that passes through to the target
binary.

> [!note]
> Due to the nature of fish's completion functions, the completion wrapper won't work until the dispatcher has been
> triggered for the given command at least once.

#### Example

```console
$ mise use -g npm:@bitwarden/cli

$ bw --help
fish: Unknown command: bw

$ @bw --help
Usage: bw [options] [command]

Options:
  --pretty                                    Format output. JSON is tabbed with two spaces.
  --raw                                       Return raw output instead of a descriptive message.
  --response                                  Return a JSON formatted version of response output.
  --cleanexit                                 Exit with a success exit code (0) unless an error is thrown.
  --quiet                                     Don't return anything to stdout.
  --nointeraction                             Do not prompt for interactive user input.
  --session <session>                         Pass session key instead of reading from env.
  -v, --version                               output the version number
  -h, --help                                  display help for command
  
# -- snip --
```

### [tide](https://github.com/IlanCosman/tide) prompt item

For [tide](https://github.com/IlanCosman/tide), users, installing this plugin will also make a `mise`
prompt item available that shows the currenty "closest" config file if `mise` has been activated,
whether manually or via this plugin's hooks.

#### `tide` prompt item configurations

The prompt item's properties are set as Universal variables with the following default values;
the convention for overriding them is to get a *global* variable that shadows the Universal variable's
name.

```fish
# A nerd font icon to use in the prompt item
set -U tide_mise_icon '󰆍'
# the default foreground color used for both icon and text
set -U tide_mise_color 00D9FF
# the default background color
set -U tide_mise_bg_color 161618
# Override `tide_mise_color` for the icon color
set -U tide_mise_icon_color $tide_mise_color
# Override `tide_mise_color` for the text of the config file path
set -U tide_mise_config_color $tide_mise_color
```
